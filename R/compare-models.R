#' Compare sdmTMB models
#'
#' @description
#' Compares a set of fitted sdmTMB models by calculating survey indices,
#' per-grid-cell prediction differences relative to a reference model, and model
#' sanity checks. The result can be plotted with
#' [plot.sdmTMB_model_comparison()].
#'
#' @param ... A set of fitted [sdmTMB::sdmTMB()] models to compare, either as
#'   individual arguments or as a single (optionally named) list. List names are
#'   used as model names; otherwise default names are assigned.
#' @param newdata A data frame for predictions, with the same predictor columns
#'   as the fitted data and a time column matching the fitted data.
#' @param reference_model Integer. Index of the model to use as the reference for
#'   comparison. Default `1`.
#' @param object_crs Coordinate reference system for the model data. If `NULL`
#'   (default), extracted from the first model's mesh when available.
#' @param bias_correct Logical. Apply bias correction via [TMB::sdreport()]?
#'   Default `FALSE`.
#' @param level Numeric. Confidence level for index intervals. Default `0.95`.
#' @param area Grid cell area for area-weighted index calculation. Passed to
#'   [sdmTMB::get_index_split()].
#' @param silent Logical. Suppress model output? Default `TRUE`.
#' @param n_workers Integer. Number of parallel workers. Default `1`.
#' @param nsplit Integer. Number of splits for [sdmTMB::get_index_split()].
#' @param future_seed Logical or integer. Future-compatible random seed for
#'   parallel processing. See [future.apply::future_lapply()].
#'
#' @return An object of class `sdmTMB_model_comparison`, a list with elements
#'   `sanity`, `nll`, `index` and `grid` (a list of per-cell prediction-
#'   difference data frames). Carries `crs`, `reference_model` and `model_names`
#'   attributes.
#'
#' @author Mikko Vihtakari
#' @seealso [sdmTMB::sdmTMB()], [sdmTMB::get_index_split()],
#'   [plot.sdmTMB_model_comparison()]
#'
#' @importFrom rlang .data
#' @examples
#' \dontrun{
#' mesh <- sdmTMB::make_mesh(sdmTMB::pcod, c("X", "Y"), cutoff = 20)
#' m1 <- sdmTMB::sdmTMB(
#'   data = sdmTMB::pcod, formula = density ~ 0 + as.factor(year),
#'   time = "year", mesh = mesh, family = sdmTMB::tweedie(link = "log")
#' )
#' m2 <- sdmTMB::sdmTMB(
#'   data = sdmTMB::pcod, formula = density ~ 0 + as.factor(year) + depth_scaled,
#'   time = "year", mesh = mesh, family = sdmTMB::tweedie(link = "log")
#' )
#' nd <- sdmTMB::replicate_df(sdmTMB::qcs_grid, "year", unique(sdmTMB::pcod$year))
#' x <- compare_models(m1, m2, newdata = nd, object_crs = 32609)
#' plot(x)
#' plot(x, type = "spatial")
#' }
#' @export
compare_models <- function(
  ...,
  newdata,
  reference_model = 1,
  object_crs = NULL,
  bias_correct = FALSE,
  level = 0.95,
  area = 1,
  silent = TRUE,
  n_workers = 1,
  nsplit = 3,
  future_seed = TRUE
) {
  args <- list(...)
  models <- if (length(args) == 1 && is.list(args[[1]]) &&
                !inherits(args[[1]], "sdmTMB")) {
    args[[1]]
  } else {
    args
  }

  if (is.null(names(models))) {
    names(models) <- paste0("Model_", seq_along(models))
  }

  if (length(models) < 2) {
    stop("At least two models must be provided for comparison.")
  }
  if (!all(vapply(models, inherits, logical(1), "sdmTMB"))) {
    stop("All provided models must be fitted using sdmTMB.")
  }
  if (missing(newdata)) {
    stop("`newdata` must be provided for predictions.")
  }

  if (is.null(object_crs) && !is.null(models[[1]]$spde$mesh$crs)) {
    object_crs <- sf::st_crs(models[[1]]$spde$mesh$crs)
  }

  old_plan <- .setup_parallel(n_workers)
  on.exit(future::plan(old_plan), add = TRUE)

  # Sanity + negative log-likelihood ------------------------------------------
  model_sanity <- as.data.frame(
    sapply(models, function(k) sdmTMB::sanity(k, silent = TRUE))
  )
  model_nll <- as.data.frame(
    lapply(models, function(k) round(k$model$objective)),
    row.names = "NLL"
  )

  # Index comparison ----------------------------------------------------------
  model_indices <- future.apply::future_lapply(
    seq_along(models),
    function(i) {
      idx <- .safe_index(
        mod = models[[i]], newdata = newdata, time_col = models[[i]]$time,
        nsplit = nsplit, bias_correct = bias_correct, level = level,
        area = area, silent = silent
      )
      tibble::add_column(idx, model = names(models)[i], .before = 1)
    },
    future.seed = future_seed
  ) |>
    dplyr::bind_rows()

  # Prediction grid differences -----------------------------------------------
  ref_mod <- models[[reference_model]]
  ref_name <- names(models)[reference_model]
  compared <- models[-reference_model]

  pred_diff <- future.apply::future_lapply(
    seq_along(compared),
    function(i) {
      k <- compared[[i]]
      comp_name <- names(compared)[i]
      if (inherits(k, "try-error")) {
        return(data.frame(
          reference_model = ref_name, compared_model = comp_name,
          year = newdata[[ref_mod$time]], X = newdata$X, Y = newdata$Y,
          est = NA, ref_est = NA, diff = NA, pr_diff = NA, mean_pr_diff = NA
        ))
      }
      base <- .pred_diff_base(k, ref_mod, newdata, ref_mod$time)
      base$reference_model <- ref_name
      base$compared_model <- comp_name
      base |>
        dplyr::group_by(.data$reference_model, .data$compared_model,
                        .data$X, .data$Y) |>
        # Fixed: mean percent difference across years for each grid cell,
        # relative to the reference model's mean prediction in that cell.
        dplyr::mutate(
          mean_pr_diff = 100 * mean(.data$diff, na.rm = TRUE) /
            mean(.data$ref_est, na.rm = TRUE)
        ) |>
        dplyr::ungroup()
    },
    future.seed = future_seed
  )

  names(pred_diff) <- vapply(pred_diff, function(k) {
    paste(unique(k$reference_model), "vs", unique(k$compared_model))
  }, character(1))

  out <- list(
    sanity = model_sanity, nll = model_nll,
    index = model_indices, grid = pred_diff
  )
  class(out) <- "sdmTMB_model_comparison"
  attributes(out)$crs <- object_crs
  attributes(out)$reference_model <- ref_name
  attributes(out)$model_names <- names(models)
  out
}

#' Plot sdmTMB model comparison results
#'
#' @description
#' Plots the results of [compare_models()] as either a time series of survey
#' indices (`type = "index"`) or spatial maps of prediction differences
#' (`type = "spatial"`, rendered on a [ggOceanMaps::basemap()]).
#'
#' @param x An object of class `sdmTMB_model_comparison`.
#' @param type Character. `"index"` (default) or `"spatial"`.
#' @param index_divisor Optional numeric divisor applied to index values.
#' @param unit Character. Unit label for axes. If `NA`, `"Index value"` is used.
#' @param viridis Logical. Use the viridis palette for model groups? Default
#'   `FALSE` (a fixed colour vector).
#' @param spatial_response Character. Column mapped in spatial plots: one of
#'   `"mean"`, `"pr_mean"` or `"mean_pr_diff"`. Default `"pr_mean"`.
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
#' @seealso [compare_models()]
#' @import ggplot2
#' @importFrom rlang .data
#' @method plot sdmTMB_model_comparison
#' @export
plot.sdmTMB_model_comparison <- function(
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
  if (type == "index") {
    dat <- x$index
    if (!is.null(index_divisor)) {
      dat <- dplyr::mutate(
        dat, est = .data$est / index_divisor,
        lwr = .data$lwr / index_divisor, upr = .data$upr / index_divisor
      )
    }

    rho <- mohns_rho(dat, group_col = "model",
                     reference = attributes(x)$reference_model)
    rho_lab <- data.frame(label = paste("Mohn's rho = ", round(rho, 3)))

    n_other <- length(unique(dat$model)) - 1
    index_colors <- if (viridis) {
      c("black", viridis::viridis(n_other))
    } else {
      c("black", .index_color_vector[seq_len(n_other)])
    }

    return(
      ggplot2::ggplot(
        dat,
        ggplot2::aes(
          x = .data$year, y = .data$est, ymin = .data$lwr, ymax = .data$upr,
          color = .data$model, fill = .data$model
        )
      ) +
        ggplot2::geom_ribbon(color = NA, alpha = 0.2) +
        ggplot2::geom_path() +
        ggplot2::scale_color_manual(values = index_colors) +
        ggplot2::scale_fill_manual(
          values = dplyr::recode(index_colors, "black" = "grey")
        ) +
        ggplot2::geom_text(
          data = rho_lab, ggplot2::aes(-Inf, Inf, label = .data$label),
          vjust = 2, hjust = -0.25, size = base_size / 2.845276,
          inherit.aes = FALSE
        ) +
        ggplot2::labs(
          y = if (!is.na(unit)) paste0("Index value (", unit, ")") else "Index value",
          x = "Year", col = "Model", fill = "Model"
        ) +
        ggplot2::expand_limits(y = 0) +
        ggplot2::coord_cartesian(expand = FALSE) +
        ggplot2::scale_y_continuous(n.breaks = 6) +
        ggplot2::scale_x_continuous(breaks = scales::pretty_breaks(n = 10)) +
        ggplot2::theme_classic(base_size = base_size) +
        ggplot2::theme(legend.position = "bottom")
    )
  }

  if (type == "spatial") {
    return(cowplot::plot_grid(
      plotlist = lapply(seq_along(x$grid), function(i) {
        .spatial_diff_map(
          grid = x$grid[[i]], crs = attributes(x)$crs,
          spatial_response = spatial_response, unit = unit,
          transform_color_scale = transform_color_scale,
          limit_rounding = limit_rounding, break_rounding = break_rounding,
          base_size = base_size, title = names(x$grid)[i]
        )
      })
    ))
  }
}
