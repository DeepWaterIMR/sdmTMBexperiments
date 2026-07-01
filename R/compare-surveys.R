#' Compare individual survey indices to a compiled sdmTMB index
#'
#' @description
#' Fits separate sdmTMB models for individual survey series and compares the
#' resulting indices to a compiled reference index. Survey-specific prediction
#' grids are built from the spatial footprint of each survey using a concave
#' hull ([make_survey_prediction_region()]). The output can be plotted as a time
#' series, a scatter plot, or a spatial prediction-difference map.
#'
#' @param data A data frame containing the modelling data, with a column
#'   identifying the survey series (see `survey_col`) and `X`/`Y` coordinates.
#' @param compiled_index A data frame of the compiled reference index, with
#'   columns `year`, `est`, `lwr`, `upr`, `se`.
#' @param compiled_model A fitted [sdmTMB::sdmTMB()] model for the compiled
#'   index, or `NULL` (default). When provided, model settings (family,
#'   spatiotemporal structure, time column, CRS) are inherited unless overridden,
#'   and spatial prediction differences are computed. When `NULL`, spatial
#'   differences are skipped and `formula`, `family` and `object_crs` must be
#'   supplied.
#' @param surveys Character vector of survey series names to compare. If `NULL`
#'   (default), all unique values of `data[[survey_col]]` are used.
#' @param newdata A data frame (the global prediction grid) used to build
#'   survey-specific grids by spatial filtering.
#' @param object_crs Coordinate reference system. If `NULL`, taken from
#'   `compiled_model`.
#' @param formula Model formula. If `NULL`, inherited from `compiled_model`.
#' @param family sdmTMB family. If `NULL`, inherited from `compiled_model`.
#' @param spatial,spatiotemporal Random field settings. If `NULL`, inherited from
#'   `compiled_model` (falling back to `"on"`/`"ar1"`).
#' @param control An [sdmTMB::sdmTMBcontrol()] object. If `NULL`, inherited from
#'   `compiled_model` (falling back to `sdmTMBcontrol(newton_loops = 2)`).
#' @param mesh_cutoff Numeric. Mesh cutoff (km) for the survey models. Default
#'   `30`.
#' @param offset_col Character. Column in `data` to use as a log-offset (e.g.
#'   `"swept_area"`). `NULL` (default) means no offset.
#' @param survey_col Character. Column identifying the survey series. Default
#'   `"cruiseseries"`.
#' @param bias_correct Logical. Apply bias correction? Default `FALSE`.
#' @param level Numeric. Confidence level for index intervals. Default `0.95`.
#' @param area Grid cell area for index calculation. Passed to
#'   [sdmTMB::get_index_split()].
#' @param silent Logical. Suppress model output? Default `TRUE`.
#' @param nsplit Integer. Number of splits for [sdmTMB::get_index_split()].
#'   Default `3`.
#' @param n_workers Integer. Number of parallel workers. Default `1`.
#' @param future_seed Logical or integer. Future-compatible random seed.
#' @param concavity Numeric. Concavity for the survey footprint hulls (see
#'   [make_survey_prediction_region()]). Default `5`.
#' @param reference_label Character. Label for the compiled reference index.
#'   Default `"Compiled"`.
#' @param verbose Logical. Show progress messages (via \pkg{cli} when installed)?
#'   Default `TRUE`.
#'
#' @return An object of class `sdmTMB_survey_comparison`, a list with `sanity`,
#'   `index` and `grid`. Carries `crs`, `reference_label` and `surveys`
#'   attributes.
#'
#' @author Mikko Vihtakari
#' @seealso [plot.sdmTMB_survey_comparison()], [compare_models()],
#'   [make_survey_prediction_region()]
#'
#' @importFrom rlang .data
#' @export
compare_surveys <- function(
  data,
  compiled_index,
  compiled_model = NULL,
  surveys = NULL,
  newdata,
  object_crs = NULL,
  formula = NULL,
  family = NULL,
  spatial = NULL,
  spatiotemporal = NULL,
  control = NULL,
  mesh_cutoff = 30,
  offset_col = NULL,
  survey_col = "cruiseseries",
  bias_correct = FALSE,
  level = 0.95,
  area = 1,
  silent = TRUE,
  nsplit = 3,
  n_workers = 1,
  future_seed = TRUE,
  concavity = 5,
  reference_label = "Compiled",
  verbose = TRUE
) {
  if (!is.null(compiled_model) && !inherits(compiled_model, "sdmTMB")) {
    stop("`compiled_model` must be a fitted sdmTMB model or NULL.")
  }
  if (!survey_col %in% names(data)) {
    stop("`data` must contain the survey column '", survey_col, "'.")
  }
  if (is.null(surveys)) surveys <- unique(data[[survey_col]])

  # Inherit / require model settings ------------------------------------------
  if (!is.null(compiled_model)) {
    if (is.null(formula)) {
      formula <- if (length(compiled_model$formula) > 1) {
        compiled_model$formula
      } else {
        compiled_model$formula[[1]]
      }
    }
    if (is.null(family)) family <- compiled_model$family
    if (is.null(spatial)) spatial <- lapply(compiled_model$spatial, function(g) g)
    if (is.null(spatiotemporal)) {
      spatiotemporal <- lapply(compiled_model$spatiotemporal, function(g) g)
    }
    if (is.null(control)) control <- compiled_model$control
    if (is.null(object_crs)) {
      if (is.null(compiled_model$spde$mesh$crs)) {
        stop("CRS not found in compiled_model mesh. Specify `object_crs`.")
      }
      object_crs <- sf::st_crs(compiled_model$spde$mesh$crs)
    }
    time_col <- compiled_model$time
  } else {
    if (is.null(formula)) stop("`formula` must be provided when compiled_model = NULL.")
    if (is.null(family)) stop("`family` must be provided when compiled_model = NULL.")
    if (is.null(object_crs)) stop("`object_crs` must be provided when compiled_model = NULL.")
    if (is.null(spatial)) spatial <- "on"
    if (is.null(spatiotemporal)) spatiotemporal <- "ar1"
    if (is.null(control)) control <- sdmTMB::sdmTMBcontrol(newton_loops = 2)
    time_col <- "year"
  }

  use_cli <- isTRUE(verbose) && requireNamespace("cli", quietly = TRUE)
  step <- function(msg) if (use_cli) cli::cli_progress_step(msg, spinner = TRUE)
  done <- function() if (use_cli) cli::cli_progress_done()
  ok <- function(msg) if (use_cli) cli::cli_alert_success(msg)
  bad <- function(msg) if (use_cli) cli::cli_alert_danger(msg)

  old_plan <- .setup_parallel(n_workers)
  on.exit(future::plan(old_plan), add = TRUE)

  # Model fitting per survey series -------------------------------------------
  step(paste("Fitting", length(surveys), "survey models"))
  survey_mods <- future.apply::future_lapply(
    surveys,
    function(survey) {
      x <- dplyr::filter(data, .data[[survey_col]] == survey)
      mesh <- sdmTMB::make_mesh(x, xy_cols = c("X", "Y"), cutoff = mesh_cutoff)
      mod <- try(
        sdmTMB::sdmTMB(
          formula = formula, data = x, mesh = mesh,
          offset = if (!is.null(offset_col)) log(x[[offset_col]]) else NULL,
          family = family, spatial = spatial,
          spatiotemporal = spatiotemporal, time = time_col,
          control = control, silent = silent
        ),
        silent = TRUE
      )
      if (inherits(mod, "try-error")) bad(paste0(survey, ": model failed")) else ok(paste0(survey, ": model OK"))
      list(mod = mod, data = x, mesh = mesh, model = survey)
    },
    future.seed = future_seed
  )
  names(survey_mods) <- surveys
  done()

  # Survey-specific prediction grids ------------------------------------------
  step(paste("Building", length(surveys), "survey prediction grids"))
  prediction_grids <- future.apply::future_lapply(
    survey_mods,
    function(k) {
      survey_data <- if (!inherits(k$mod, "try-error")) k$mod$data else k$data
      region <- make_survey_prediction_region(
        survey_data, crs = object_crs, concavity = concavity
      )
      .clip_points_to_region(newdata, region)
    },
    future.seed = future_seed
  )
  done()

  # Sanity checks -------------------------------------------------------------
  model_sanity <- as.data.frame(sapply(survey_mods, function(k) {
    if (!inherits(k$mod, "try-error")) sdmTMB::sanity(k$mod, silent = TRUE) else rep(NA, 7)
  }))

  # Index calculation ---------------------------------------------------------
  step(paste("Computing", length(surveys), "survey indices"))
  survey_indices <- future.apply::future_lapply(
    seq_along(survey_mods),
    function(l) {
      idx <- .safe_index(
        mod = survey_mods[[l]]$mod, newdata = prediction_grids[[l]],
        time_col = time_col, nsplit = nsplit, bias_correct = bias_correct,
        level = level, area = area, silent = silent
      )
      ok(paste0(survey_mods[[l]]$model, ": index done"))
      tibble::add_column(idx, model = survey_mods[[l]]$model, .before = 1)
    },
    future.seed = future_seed
  ) |>
    dplyr::bind_rows()
  done()

  combined_index <- dplyr::bind_rows(
    survey_indices,
    dplyr::mutate(compiled_index, model = reference_label)
  )

  # Spatial prediction differences --------------------------------------------
  if (!is.null(compiled_model)) {
    step("Computing spatial prediction differences")
    pred_diff <- future.apply::future_lapply(
      seq_along(survey_mods),
      function(i) {
        k <- survey_mods[[i]]
        nd <- prediction_grids[[i]]
        if (inherits(k$mod, "try-error")) {
          out <- data.frame(
            reference_model = reference_label, survey = surveys[i],
            year = nd[[time_col]], X = nd$X, Y = nd$Y,
            est = NA, ref_est = NA, diff = NA, pr_diff = NA, mean_pr_diff = NA
          )
        } else {
          base <- .pred_diff_base(k$mod, compiled_model, nd, time_col)
          base$reference_model <- reference_label
          base$survey <- surveys[i]
          out <- base |>
            dplyr::group_by(.data$reference_model, .data$survey,
                            .data$X, .data$Y) |>
            dplyr::mutate(
              mean_pr_diff = 100 * mean(.data$diff, na.rm = TRUE) /
                mean(.data$ref_est, na.rm = TRUE)
            ) |>
            dplyr::ungroup()
        }
        ok(paste0(surveys[i], ": spatial diff done"))
        out
      },
      future.seed = future_seed
    )
    names(pred_diff) <- surveys
    done()
  } else {
    pred_diff <- NULL
  }

  out <- list(sanity = model_sanity, index = combined_index, grid = pred_diff)
  class(out) <- "sdmTMB_survey_comparison"
  attributes(out)$crs <- object_crs
  attributes(out)$reference_label <- reference_label
  attributes(out)$surveys <- surveys
  out
}

#' Plot survey comparison results
#'
#' @description
#' Plots the results of [compare_surveys()] as a time series of indices
#' (`type = "index"`), a scatter plot of survey vs compiled indices
#' (`type = "scatter"`), or a spatial prediction-difference map
#' (`type = "spatial"`, on a [ggOceanMaps::basemap()]).
#'
#' @param x An object of class `sdmTMB_survey_comparison`.
#' @param type Character. `"index"` (default), `"scatter"` or `"spatial"`.
#' @param index_divisor Optional numeric divisor applied to index values.
#' @param unit Character. Unit label. If `NA`, `"Index value"` is used.
#' @param viridis Logical. Use the viridis palette for survey series? Default
#'   `FALSE`.
#' @param spatial_response Character. Column mapped in spatial plots: `"mean"`,
#'   `"pr_mean"` or `"mean_pr_diff"`. Default `"pr_mean"`.
#' @param transform_color_scale Logical. Apply a signed square-root colour scale
#'   for spatial plots? Default `TRUE`.
#' @param limit_rounding,break_rounding Numeric rounding for map fill limits and
#'   breaks. Defaults `10` and `5`.
#' @param base_size Numeric. Base font size. Default `11`.
#' @param ... Currently ignored.
#'
#' @return A `ggplot` object (`type = "index"`/`"scatter"`) or a `cowplot` grid
#'   (`type = "spatial"`).
#'
#' @author Mikko Vihtakari
#' @seealso [compare_surveys()]
#' @import ggplot2
#' @importFrom rlang .data
#' @method plot sdmTMB_survey_comparison
#' @export
plot.sdmTMB_survey_comparison <- function(
  x,
  type = "index",
  index_divisor = NULL,
  unit = NA,
  viridis = FALSE,
  spatial_response = "pr_mean",
  transform_color_scale = TRUE,
  limit_rounding = 10,
  break_rounding = 5,
  base_size = 11,
  ...
) {
  surveys <- attributes(x)$surveys
  ref <- attributes(x)$reference_label

  survey_colors <- if (viridis) {
    stats::setNames(viridis::viridis(length(surveys)), surveys)
  } else {
    stats::setNames(.index_color_vector[seq_along(surveys)], surveys)
  }

  if (type == "index") {
    dat <- x$index
    if (!is.null(index_divisor)) {
      dat <- dplyr::mutate(
        dat, est = .data$est / index_divisor,
        lwr = .data$lwr / index_divisor, upr = .data$upr / index_divisor
      )
    }
    index_colors <- c(stats::setNames("black", ref), survey_colors)
    fill_colors <- dplyr::recode(index_colors, "black" = "grey")

    return(
      dat |>
        dplyr::mutate(model = factor(.data$model, levels = c(ref, surveys))) |>
        ggplot2::ggplot(ggplot2::aes(
          x = .data$year, y = .data$est, ymin = .data$lwr, ymax = .data$upr,
          color = .data$model, fill = .data$model
        )) +
        ggplot2::geom_ribbon(color = NA, alpha = 0.2) +
        ggplot2::geom_path() +
        ggplot2::scale_color_manual(values = index_colors) +
        ggplot2::scale_fill_manual(values = fill_colors) +
        ggplot2::labs(
          y = if (!is.na(unit)) paste0("Index value (", unit, ")") else "Index value",
          x = "Year", color = "Model", fill = "Model"
        ) +
        ggplot2::expand_limits(y = 0) +
        ggplot2::coord_cartesian(expand = FALSE) +
        ggplot2::scale_y_continuous(n.breaks = 6) +
        ggplot2::scale_x_continuous(breaks = scales::pretty_breaks(n = 10)) +
        ggplot2::theme_classic(base_size = base_size) +
        ggplot2::theme(legend.position = "bottom")
    )
  }

  if (type == "scatter") {
    dat <- x$index
    if (!is.null(index_divisor)) {
      dat <- dplyr::mutate(
        dat, est = .data$est / index_divisor,
        lwr = .data$lwr / index_divisor, upr = .data$upr / index_divisor
      )
    }
    ref_dat <- dat |>
      dplyr::filter(.data$model == ref) |>
      dplyr::select(.data$year, ref_est = .data$est)

    return(
      dat |>
        dplyr::filter(.data$model != ref) |>
        dplyr::left_join(ref_dat, by = "year") |>
        ggplot2::ggplot(ggplot2::aes(
          x = .data$ref_est, y = .data$est, color = .data$model
        )) +
        ggplot2::geom_point() +
        ggplot2::geom_smooth(method = "lm", se = FALSE, formula = y ~ x) +
        ggplot2::scale_color_manual(values = survey_colors) +
        ggplot2::labs(
          x = if (!is.na(unit)) paste0(ref, " index (", unit, ")") else paste0(ref, " index"),
          y = if (!is.na(unit)) paste0("Survey index (", unit, ")") else "Survey index",
          color = "Survey"
        ) +
        ggplot2::theme_classic(base_size = base_size) +
        ggplot2::theme(legend.position = "bottom")
    )
  }

  if (type == "spatial") {
    if (is.null(x$grid)) {
      stop("No spatial grid available. Re-run compare_surveys() with a compiled_model.")
    }
    return(cowplot::plot_grid(
      plotlist = lapply(seq_along(x$grid), function(i) {
        .spatial_diff_map(
          grid = x$grid[[i]], crs = attributes(x)$crs,
          spatial_response = spatial_response, unit = unit,
          transform_color_scale = transform_color_scale,
          limit_rounding = limit_rounding, break_rounding = break_rounding,
          base_size = base_size, title = paste(names(x$grid)[i], "vs", ref)
        )
      })
    ))
  }
}
