#' Retrospective analysis for an sdmTMB index
#'
#' @description
#' Runs an analytical retrospective on an index from [sdmTMB::sdmTMB()]. The
#' function refits the model for each peel (successively dropping the most recent
#' years) and calculates an index for each peel using
#' [sdmTMB::get_index_split()]. Model settings are inherited from the fitted
#' `object`.
#'
#' @param object A fitted model from [sdmTMB::sdmTMB()].
#' @param newdata A data frame to make predictions on, with the same predictor
#'   columns as the fitted data and a time column with the same name as in the
#'   fitted data. Must contain all years needed for the retrospective (see
#'   `nyears`).
#' @param nyears Integer. How many peels the retrospective should contain,
#'   including the terminal (most recent) year. Clamped to the number of fitted
#'   years available.
#' @param refit_meshes Logical. Rebuild the mesh for each peel from the peeled
#'   data (approximating the original cutoff)? If `FALSE` (default) the original
#'   model mesh is reused unchanged.
#' @param bias_correct Logical. Apply bias correction via [TMB::sdreport()]?
#'   Recommended `TRUE` for final analyses, `FALSE` (default) while
#'   experimenting.
#' @param level Numeric. Confidence level for the index intervals.
#' @param area Grid cell area for area weighting the index. Can be a numeric
#'   vector of length `nrow(newdata)`, a single numeric value, or a character
#'   column name in `newdata`. Passed to [sdmTMB::get_index_split()].
#' @param save_models Logical. Retain the fitted model object for each peel in
#'   the output?
#' @param silent Logical. Suppress model fitting output?
#' @param n_workers Integer. Number of parallel workers. Defaults to `nyears`.
#'   Set to 1 to run sequentially.
#' @param nsplit Integer. Number of splits for [sdmTMB::get_index_split()].
#' @param predict_args A list of arguments controlling the prediction grid used
#'   for the index. Currently `newdata` is filtered to the peeled years.
#' @param future_seed Logical or integer. Future-compatible random seed for
#'   parallel processing. See [future.apply::future_lapply()].
#'
#' @return A list of class `sdmTMB_retro`. Each element corresponds to a peel and
#'   contains an `index` data frame (and, if `save_models = TRUE`, the fitted
#'   model object).
#'
#' @author Mikko Vihtakari, with examples and documentation adapted from the
#'   \pkg{sdmTMB} package.
#' @seealso [sdmTMB::sdmTMB()], [sdmTMB::get_index()], [plot.sdmTMB_retro()]
#'
#' @importFrom rlang .data
#' @examples
#' \donttest{
#' mesh <- sdmTMB::make_mesh(sdmTMB::pcod, c("X", "Y"), cutoff = 25)
#' m <- sdmTMB::sdmTMB(
#'   data = sdmTMB::pcod,
#'   formula = density ~ 0 + as.factor(year),
#'   time = "year", mesh = mesh, family = sdmTMB::tweedie(link = "log")
#' )
#' nd <- sdmTMB::replicate_df(sdmTMB::qcs_grid, "year", unique(sdmTMB::pcod$year))
#' retr <- sdmTMB_retro(m, nd, nyears = 3, n_workers = 1)
#' plot(retr)
#' }
#' @export
sdmTMB_retro <- function(
  object,
  newdata,
  nyears = 5,
  refit_meshes = FALSE,
  bias_correct = FALSE,
  level = 0.95,
  area = 1,
  save_models = FALSE,
  silent = TRUE,
  n_workers = nyears,
  nsplit = 3,
  predict_args = list(),
  future_seed = TRUE
) {
  if (!inherits(object, "sdmTMB")) {
    stop("`object` must be a fitted sdmTMB model.")
  }

  fitted_years <- sort(unique(object$fitted_time))
  # Guard against nyears exceeding the number of available years (avoids NA).
  nyears <- min(nyears, length(fitted_years))
  years <- rev(fitted_years)[seq_len(nyears)]

  old_plan <- .setup_parallel(n_workers)
  on.exit(future::plan(old_plan), add = TRUE)

  peeled_output <- future.apply::future_lapply(
    years,
    function(k) {
      peel_data <- dplyr::filter(object$data, get(object$time) <= k)

      if (refit_meshes) {
        if (is.integer(future_seed)) set.seed(future_seed)
        knots <- object$spde$mesh$loc[, 1:2]
        approx_cutoff <- round(min(stats::dist(knots)), 0)
        mesh <- sdmTMB::make_mesh(
          peel_data,
          xy_cols = c("X", "Y"),
          cutoff = approx_cutoff
        )
      } else {
        # Reuse the original mesh geometry (SPDE vertices/triangulation)
        # unchanged, but rebuild the data-to-mesh mapping (loc_xy, A_st,
        # sdm_spatial_id) for the peeled data. An sdmTMBmesh object stores one
        # row per fitted observation, so passing it through unchanged (or
        # subsetting mesh$loc_xy by data rows) does not work once rows are
        # peeled off: sdmTMB() then errors because nrow(data) no longer
        # matches the mesh's stored coordinates.
        mesh <- sdmTMB::make_mesh(
          peel_data,
          xy_cols = object$spde$xy_cols,
          mesh = object$spde$mesh
        )
      }

      predict_args$newdata <- newdata |>
        dplyr::filter(get(object$time) <= k) |>
        dplyr::filter(get(object$time) %in% unique(object$data[[object$time]]))

      out <- try(
        sdmTMB::sdmTMB(
          formula = if (length(object$formula) > 1) {
            object$formula
          } else {
            object$formula[[1]]
          },
          data = peel_data,
          mesh = mesh,
          time = object$time,
          offset = object$offset[object$data[[object$time]] <= k],
          family = object$family,
          spatial = lapply(object$spatial, function(g) g),
          spatiotemporal = lapply(object$spatiotemporal, function(g) g),
          control = object$control,
          silent = silent
        ),
        silent = silent
      )

      if (inherits(out, "try-error")) {
        message("Model for ", k, " did not converge. Adding NAs as index values")
        index <- .crashed_index(unique(predict_args$newdata[[object$time]]))
      } else {
        index <- .safe_index(
          mod = out, newdata = predict_args$newdata, time_col = object$time,
          nsplit = nsplit, bias_correct = bias_correct, level = level,
          area = area, silent = silent
        )
      }

      if (save_models && !inherits(out, "try-error")) {
        list(index = index, model = out)
      } else {
        list(index = index)
      }
    },
    future.seed = future_seed
  )

  names(peeled_output) <- paste0("peel ", seq_len(nyears) - 1, ": ", years)
  class(peeled_output) <- "sdmTMB_retro"
  peeled_output
}

#' Plot retrospective indices from sdmTMB_retro
#'
#' @description
#' Creates a layered ggplot of retrospective (peeled) indices produced by
#' [sdmTMB_retro()], with confidence ribbons for each peel and Mohn's rho
#' (computed with [mohns_rho()]) annotated on the plot.
#'
#' @param x An object of class `sdmTMB_retro` (the output of [sdmTMB_retro()]).
#' @param index_divisor Optional numeric. Index values are divided by this before
#'   plotting (useful to rescale units). Default `NULL`.
#' @param index_unit Optional character shown in the y-axis label. If `NA`
#'   (default) the axis label is `"Index value"`.
#' @param base_size Base font size for the ggplot theme. Default `11`.
#' @param ... Currently ignored.
#'
#' @return A `ggplot` object.
#'
#' @author Mikko Vihtakari
#' @seealso [sdmTMB_retro()], [mohns_rho()]
#' @import ggplot2
#' @importFrom rlang .data
#' @examples
#' \donttest{
#' mesh <- sdmTMB::make_mesh(sdmTMB::pcod, c("X", "Y"), cutoff = 25)
#' m <- sdmTMB::sdmTMB(
#'   data = sdmTMB::pcod,
#'   formula = density ~ 0 + as.factor(year),
#'   time = "year", mesh = mesh, family = sdmTMB::tweedie(link = "log")
#' )
#' nd <- sdmTMB::replicate_df(sdmTMB::qcs_grid, "year", unique(sdmTMB::pcod$year))
#' retr <- sdmTMB_retro(m, nd, nyears = 3, n_workers = 1)
#' plot(retr, index_divisor = 1e3, index_unit = "1000 t")
#' }
#' @method plot sdmTMB_retro
#' @export
plot.sdmTMB_retro <- function(
  x,
  index_divisor = NULL,
  index_unit = NA,
  base_size = 11,
  ...
) {
  dat <- lapply(seq_along(x), function(i) {
    dplyr::mutate(x[[i]]$index, peel = names(x)[i], .before = 1)
  }) |>
    dplyr::bind_rows()

  if (!is.null(index_divisor)) {
    dat <- dplyr::mutate(
      dat,
      est = .data$est / index_divisor,
      lwr = .data$lwr / index_divisor,
      upr = .data$upr / index_divisor
    )
  }

  rho <- mohns_rho(dat, group_col = "peel", reference = names(x)[1])
  rho_lab <- data.frame(label = paste("Mohn's rho = ", round(rho, 3)))

  ggplot2::ggplot(
    dat,
    ggplot2::aes(
      x = .data$year, y = .data$est, ymin = .data$lwr, ymax = .data$upr,
      color = .data$peel, fill = .data$peel
    )
  ) +
    ggplot2::geom_ribbon(color = NA, alpha = 0.2) +
    ggplot2::geom_text(
      data = rho_lab,
      ggplot2::aes(-Inf, Inf, label = .data$label),
      vjust = 2, hjust = -0.25, size = base_size / 2.845276, inherit.aes = FALSE
    ) +
    ggplot2::geom_path() +
    ggplot2::labs(
      y = if (!is.na(index_unit)) paste0("Index value (", index_unit, ")") else "Index value",
      x = "Year", col = "Peel", fill = "Peel"
    ) +
    ggplot2::expand_limits(y = 0) +
    ggplot2::scale_color_viridis_d() +
    ggplot2::scale_fill_viridis_d() +
    ggplot2::scale_y_continuous(n.breaks = 6) +
    ggplot2::theme_classic(base_size = base_size) +
    .index_axis_layers() +
    ggplot2::theme(legend.position = "bottom")
}
