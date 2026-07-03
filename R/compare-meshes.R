#' Compare survey indices across different mesh cutoff values
#'
#' @description
#' Refits an sdmTMB model using a range of mesh cutoff values and compares the
#' resulting survey indices and predictions to the original (reference) model.
#' Useful for assessing the sensitivity of an index to mesh resolution.
#'
#' @param object A fitted model from [sdmTMB::sdmTMB()].
#' @param mesh_cutoffs Numeric vector of mesh cutoff values (in the units of the
#'   model coordinates, typically km) to compare.
#' @param newdata A data frame for predictions, with the same predictor columns
#'   as the fitted data and a time column matching the fitted data. Must contain
#'   `X` and `Y` columns.
#' @param object_crs Coordinate reference system for the model data. If `NULL`
#'   (default), extracted from the model's mesh.
#' @param bias_correct Logical. Apply bias correction via [TMB::sdreport()]?
#'   Default `FALSE`.
#' @param level Numeric. Confidence level for index intervals. Default `0.95`.
#' @param area Grid cell area for area-weighted index calculation. Passed to
#'   [sdmTMB::get_index_split()].
#' @param save_models Logical. Retain fitted model objects in the output? Default
#'   `FALSE`.
#' @param silent Logical. Suppress model output? Default `TRUE`.
#' @param n_workers Integer. Number of parallel workers. Default `1`.
#' @param nsplit Integer. Number of splits for [sdmTMB::get_index_split()].
#'   Default `3`.
#' @param future_seed Logical or integer. Future-compatible random seed for
#'   parallel processing.
#' @param reference_name Character. Label for the reference (original) model.
#'   Default `"Reference"`.
#'
#' @return An object of class `sdmTMB_mesh_comparison`, a list with `index`,
#'   `pred_diff` (and optionally `models`). Carries `crs` and `reference_name`
#'   attributes.
#'
#' @author Mikko Vihtakari
#' @seealso [sdmTMB::sdmTMB()], [sdmTMB::get_index_split()],
#'   [plot.sdmTMB_mesh_comparison()]
#'
#' @importFrom rlang .data
#' @examples
#' \donttest{
#' mesh <- sdmTMB::make_mesh(sdmTMB::pcod, c("X", "Y"), cutoff = 20)
#' m <- sdmTMB::sdmTMB(
#'   data = sdmTMB::pcod, formula = density ~ 0 + as.factor(year),
#'   time = "year", mesh = mesh, family = sdmTMB::tweedie(link = "log")
#' )
#' nd <- sdmTMB::replicate_df(sdmTMB::qcs_grid, "year", unique(sdmTMB::pcod$year))
#' mesh_indices <- compare_meshes(
#'   object = m, mesh_cutoffs = c(10, 30), newdata = nd, object_crs = 32609,
#'   reference_name = "20 km"
#' )
#' plot(mesh_indices)
#' }
#' @export
compare_meshes <- function(
  object,
  mesh_cutoffs,
  newdata,
  object_crs = NULL,
  bias_correct = FALSE,
  level = 0.95,
  area = 1,
  save_models = FALSE,
  silent = TRUE,
  n_workers = 1,
  nsplit = 3,
  future_seed = TRUE,
  reference_name = "Reference"
) {
  if (!inherits(object, "sdmTMB")) {
    stop("`object` must be a fitted sdmTMB model.")
  }
  if (!all(c("X", "Y") %in% names(newdata))) {
    stop("`newdata` must contain `X` and `Y` columns matching the model coordinates.")
  }

  dt <- object$data
  if (!all(c("X", "Y") %in% names(dt))) {
    stop("The model data must contain `X` and `Y` columns.")
  }

  if (is.null(object_crs)) {
    mesh_crs <- object$spde$mesh$crs
    # make_mesh() has no `crs` argument, so a mesh built the usual way
    # carries an NA (not NULL) crs; catch both, otherwise this silently
    # passes an NA CRS through to the spatial plot (see compare_surveys()).
    if (is.null(mesh_crs) || is.na(sf::st_crs(mesh_crs))) {
      stop("Model CRS not found in the mesh object. Specify `object_crs`.")
    }
    object_crs <- sf::st_crs(mesh_crs)
  }

  old_plan <- .setup_parallel(n_workers)
  on.exit(future::plan(old_plan), add = TRUE)

  # Meshes (alternative cutoffs + the original as reference) ------------------
  meshes <- lapply(mesh_cutoffs, function(k) {
    if (is.integer(future_seed)) set.seed(future_seed)
    sdmTMB::make_mesh(dt, xy_cols = c("X", "Y"), cutoff = k)
  })
  names(meshes) <- mesh_cutoffs
  meshes <- c(meshes, stats::setNames(list(object$spde), reference_name))

  # Model fitting -------------------------------------------------------------
  mmods <- future.apply::future_lapply(
    seq_along(meshes),
    function(j) {
      try(
        sdmTMB::sdmTMB(
          formula = if (length(object$formula) > 1) object$formula else object$formula[[1]],
          data = dt,
          mesh = meshes[[j]],
          time = object$time,
          offset = object$offset,
          family = object$family,
          spatial = lapply(object$spatial, function(g) g),
          spatiotemporal = lapply(object$spatiotemporal, function(g) g),
          control = object$control,
          silent = silent
        ),
        silent = TRUE
      )
    },
    future.seed = future_seed
  )
  names(mmods) <- names(meshes)

  # Index calculation ---------------------------------------------------------
  mesh_index <- future.apply::future_lapply(
    seq_along(mmods),
    function(l) {
      idx <- .safe_index(
        mod = mmods[[l]], newdata = newdata, time_col = object$time,
        nsplit = nsplit, bias_correct = bias_correct, level = level,
        area = area, silent = silent
      )
      tibble::add_column(idx, cutoff = names(mmods)[l], .before = 1)
    },
    future.seed = future_seed
  ) |>
    dplyr::bind_rows() |>
    dplyr::mutate(
      cutoff = factor(
        .data$cutoff,
        levels = unique(c(
          reference_name,
          sort(suppressWarnings(as.integer(unique(.data$cutoff))))
        ))
      )
    )

  # Prediction grid differences ----------------------------------------------
  ref_mod <- mmods[[reference_name]]
  alt <- mmods[!names(mmods) %in% reference_name]

  pred_diff <- future.apply::future_lapply(
    seq_along(alt),
    function(i) {
      k <- alt[[i]]
      cutoff_name <- names(alt)[i]
      if (inherits(k, "try-error")) {
        return(data.frame(
          cutoff = cutoff_name, year = newdata[[object$time]],
          X = newdata$X, Y = newdata$Y,
          depth = if ("depth" %in% names(newdata)) newdata$depth else NA,
          est = NA, ref_est = NA, diff = NA, pr_diff = NA, mean_pr_diff = NA
        ))
      }
      base <- .pred_diff_base(k, ref_mod, newdata, object$time)
      base$cutoff <- cutoff_name
      base |>
        dplyr::group_by(.data$cutoff, .data$X, .data$Y) |>
        # See `.pred_diff_base()`/`.spatial_diff_map()` for why this ratio-of-
        # means differs from (and is more robust than) mean(pr_diff).
        dplyr::mutate(
          mean_pr_diff = 100 * mean(.data$diff, na.rm = TRUE) /
            mean(.data$ref_est, na.rm = TRUE)
        ) |>
        dplyr::ungroup()
    },
    future.seed = future_seed
  )
  names(pred_diff) <- names(alt)

  out <- if (save_models) {
    list(models = mmods, index = mesh_index, pred_diff = pred_diff)
  } else {
    list(index = mesh_index, pred_diff = pred_diff)
  }
  class(out) <- "sdmTMB_mesh_comparison"
  attributes(out)$crs <- object_crs
  attributes(out)$reference_name <- reference_name
  out
}

#' Plot mesh comparison results
#'
#' @description
#' Plots survey index time series from a mesh cutoff comparison (reference in
#' black, alternative cutoffs in colour, with Mohn's rho annotated), or spatial
#' maps of prediction differences on a [ggOceanMaps::basemap()].
#'
#' @details
#' For `type = "spatial"`, each grid cell is compared between a model fitted
#' with an alternative mesh cutoff and the model fitted with the reference
#' cutoff, for every year they share, on the response scale (i.e.
#' `predict(..., type = "response")`, e.g. density rather than log density):
#' `diff = est - ref_est` and `pr_diff = 100 * diff / ref_est` (percent).
#' `spatial_response` selects how these per-year values are summarised across
#' years into the single value mapped for each cell:
#' * `"mean"`: `mean(diff)` — the average absolute difference, in response
#'   units. Useful for the raw magnitude of disagreement, but not comparable
#'   across cells with very different baseline abundance.
#' * `"pr_mean"`: `mean(pr_diff)` — the average of the yearly percent
#'   differences. Because each year is divided by that year's own (possibly
#'   small) reference value, a handful of low-abundance years/cells can
#'   dominate this average with large percentage swings even when the
#'   absolute difference is small.
#' * `"mean_pr_diff"` (default): `100 * mean(diff) / mean(ref_est)` — the
#'   percent difference between the across-year mean predictions (a ratio of
#'   means, not a mean of ratios). This is usually the more robust
#'   percent-based summary, since a cell's overall multi-year baseline is used
#'   in the denominator instead of each individual year's value.
#'
#' @param x An object of class `sdmTMB_mesh_comparison`.
#' @param type Character. `"index"` (default) or `"spatial"`.
#' @param index_divisor Optional numeric divisor applied to index values.
#' @param unit Character. Unit label. If `NA`, `"Index value"` is used.
#' @param mohn Logical. Annotate the index plot with Mohn's rho (via
#'   [mohns_rho()])? Default `FALSE`. Only applies when `type = "index"`.
#' @param cutoff_label Character. Label for the cutoff colour/fill legend.
#'   Default `"Cutoff"`.
#' @param viridis Logical. Use the viridis palette for cutoff levels? If `FALSE`
#'   (default), a palette-safe Set1 is used.
#' @param spatial_response Character. Column mapped in spatial plots: one of
#'   `"mean"`, `"pr_mean"` or `"mean_pr_diff"`. Default `"mean_pr_diff"`. See
#'   Details.
#' @param transform_color_scale Logical. Apply a signed square-root colour scale
#'   for spatial plots? Default `TRUE`.
#' @param limit_rounding,break_rounding Numeric rounding for map fill limits and
#'   breaks. Defaults `10` and `5`.
#' @param base_size Numeric. Base font size. Default `11`.
#' @param ... Currently ignored.
#'
#' @return A `ggplot` object (`type = "index"`) or a `cowplot` grid
#'   (`type = "spatial"`).
#'
#' @author Mikko Vihtakari
#' @seealso [compare_meshes()]
#' @import ggplot2
#' @importFrom rlang .data
#' @examples
#' \donttest{
#' mesh <- sdmTMB::make_mesh(sdmTMB::pcod, c("X", "Y"), cutoff = 20)
#' m <- sdmTMB::sdmTMB(
#'   data = sdmTMB::pcod, formula = density ~ 0 + as.factor(year),
#'   time = "year", mesh = mesh, family = sdmTMB::tweedie(link = "log")
#' )
#' nd <- sdmTMB::replicate_df(sdmTMB::qcs_grid, "year", unique(sdmTMB::pcod$year))
#' mesh_indices <- compare_meshes(
#'   object = m, mesh_cutoffs = c(10, 30), newdata = nd, object_crs = 32609,
#'   reference_name = "20 km"
#' )
#' plot(mesh_indices, cutoff_label = "Cutoff (km)")
#' plot(mesh_indices, type = "spatial")
#' }
#' @method plot sdmTMB_mesh_comparison
#' @export
plot.sdmTMB_mesh_comparison <- function(
  x,
  type = "index",
  index_divisor = NULL,
  unit = NA,
  mohn = FALSE,
  cutoff_label = "Cutoff",
  viridis = FALSE,
  spatial_response = "mean_pr_diff",
  transform_color_scale = TRUE,
  limit_rounding = 10,
  break_rounding = 5,
  base_size = 11,
  ...
) {
  if (type == "index") {
    dat <- x$index
    if (!is.null(index_divisor)) {
      dat <- dplyr::mutate(
        dat, est = .data$est / index_divisor,
        lwr = .data$lwr / index_divisor, upr = .data$upr / index_divisor
      )
    }

    n_other <- length(unique(dat$cutoff)) - 1
    index_colors <- if (viridis) {
      c("black", viridis::viridis(n_other))
    } else {
      c("black", .safe_brewer(n_other, "Set1"))
    }

    p <- ggplot2::ggplot(
        dat,
        ggplot2::aes(
          x = .data$year, y = .data$est, ymin = .data$lwr, ymax = .data$upr,
          color = .data$cutoff, fill = .data$cutoff
        )
      ) +
        ggplot2::geom_ribbon(color = NA, alpha = 0.2) +
        ggplot2::geom_path() +
        ggplot2::scale_color_manual(values = index_colors) +
        ggplot2::scale_fill_manual(values = index_colors)

    if (isTRUE(mohn)) {
      rho <- mohns_rho(dat, group_col = "cutoff",
                       reference = attributes(x)$reference_name)
      rho_lab <- data.frame(label = paste("Mohn's rho = ", round(rho, 3)))
      p <- p + ggplot2::geom_text(
        data = rho_lab, ggplot2::aes(-Inf, Inf, label = .data$label),
        vjust = 2, hjust = -0.25, size = base_size / 2.845276,
        inherit.aes = FALSE
      )
    }

    return(
      p +
        ggplot2::labs(
          y = if (!is.na(unit)) paste0("Index value (", unit, ")") else "Index value",
          x = "Year", col = cutoff_label, fill = cutoff_label
        ) +
        ggplot2::expand_limits(y = 0) +
        ggplot2::scale_y_continuous(n.breaks = 6) +
        ggplot2::theme_classic(base_size = base_size) +
        .index_axis_layers() +
        ggplot2::theme(legend.position = "bottom")
    )
  }

  if (type == "spatial") {
    return(cowplot::plot_grid(
      plotlist = lapply(seq_along(x$pred_diff), function(i) {
        .spatial_diff_map(
          grid = x$pred_diff[[i]], crs = attributes(x)$crs,
          spatial_response = spatial_response, unit = unit,
          transform_color_scale = transform_color_scale,
          limit_rounding = limit_rounding, break_rounding = break_rounding,
          base_size = base_size,
          title = paste("Cutoff:", names(x$pred_diff)[i], "vs",
                        attributes(x)$reference_name)
        )
      })
    ))
  }
}
