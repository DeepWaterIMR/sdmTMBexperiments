## Internal helper functions shared across sdmTMBexperiments -------------------
## These are not exported. They centralise the parallel-processing setup, the
## index calculation, and the prediction-difference computation that were
## previously duplicated across the comparison functions.

#' Configure a future parallel plan
#'
#' Captures the current future plan, installs a new one, and sets a sensible
#' `future.globals.maxSize`. Returns the previous plan so the caller can restore
#' it with `on.exit()`.
#'
#' A portable `multisession` plan is used for `n_workers > 1` (works on all
#' platforms, including Windows). Users who want forked (`multicore`) or
#' cluster workers can set their own plan before calling and pass
#' `n_workers = 1` to leave it untouched.
#'
#' @param n_workers Integer number of workers.
#' @return The previous future plan.
#' @keywords internal
#' @noRd
.setup_parallel <- function(n_workers) {
  old_plan <- future::plan()
  if (n_workers > 1) {
    future::plan(future::multisession, workers = n_workers)
  } else {
    future::plan(future::sequential)
  }
  .set_future_memory()
  old_plan
}

#' Set future.globals.maxSize based on free system memory
#'
#' Uses \pkg{ps} when available to size the globals limit to the free RAM,
#' otherwise removes the limit. Fixes the earlier behaviour where the fallback
#' branch computed a value without assigning it to `options()`.
#'
#' @keywords internal
#' @noRd
.set_future_memory <- function() {
  free <- tryCatch(
    if (requireNamespace("ps", quietly = TRUE)) {
      as.numeric(ps::ps_system_memory()$free)
    } else {
      NA_real_
    },
    error = function(e) NA_real_
  )

  if (is.na(free)) {
    options(future.globals.maxSize = Inf)
  } else if (free / 1024^3 > 15) {
    options(future.globals.maxSize = 14e3 * 1024^2)
  } else {
    options(future.globals.maxSize = free * 0.8)
  }
  invisible(NULL)
}

#' A data frame representing a crashed (non-converged) index
#'
#' @param years The years to fill with `NA` index values.
#' @keywords internal
#' @noRd
.crashed_index <- function(years) {
  data.frame(
    year = years,
    est = NA_real_,
    lwr = NA_real_,
    upr = NA_real_,
    log_est = NA_real_,
    se = NA_real_,
    type = "crashed"
  )
}

#' Safely calculate a split survey index for one model
#'
#' Wraps [sdmTMB::get_index_split()] with a graceful fallback for models that
#' failed to fit (returned a `try-error` or `NULL`), and appends a coefficient
#' of variation (`cv`) column.
#'
#' @param mod A fitted sdmTMB model, a `try-error`, or `NULL`.
#' @param newdata Prediction grid data frame.
#' @param time_col Name of the time column (used for the crashed fallback).
#' @param nsplit,bias_correct,level,area,silent Passed to
#'   [sdmTMB::get_index_split()].
#' @return A data frame with the index and a `cv` column.
#' @keywords internal
#' @noRd
.safe_index <- function(mod, newdata, time_col, nsplit, bias_correct, level,
                        area, silent) {
  if (is.null(mod) || inherits(mod, "try-error")) {
    return(.crashed_index(unique(newdata[[time_col]])))
  }
  idx <- suppressMessages(
    sdmTMB::get_index_split(
      obj = mod,
      newdata = newdata,
      nsplit = nsplit,
      bias_correct = bias_correct,
      level = level,
      area = area,
      silent = silent
    )
  )
  idx$cv <- sqrt(exp(idx$se^2) - 1)
  idx
}

#' Per-grid-cell prediction difference between a model and a reference model
#'
#' Predicts both models onto the years shared with `mod`, and returns a data
#' frame with the response predictions, their difference, and a per-cell percent
#' difference. A `depth` column is carried through when present in `newdata`.
#'
#' @param mod,ref_mod Fitted sdmTMB models.
#' @param newdata Prediction grid data frame with `X`, `Y` and `time_col`.
#' @param time_col Name of the time column.
#' @return A data frame with `year`, `X`, `Y`, (`depth`), `est`, `ref_est`,
#'   `diff`, `pr_diff`.
#' @keywords internal
#' @noRd
.pred_diff_base <- function(mod, ref_mod, newdata, time_col) {
  nd <- dplyr::filter(
    newdata,
    .data[[time_col]] %in% unique(mod$data[[time_col]])
  )
  pred <- stats::predict(mod, newdata = nd, type = "response", model = NA)
  pred_ref <- stats::predict(ref_mod, newdata = nd, type = "response", model = NA)

  out <- data.frame(
    year = nd[[time_col]],
    X = nd$X,
    Y = nd$Y,
    est = pred$est,
    ref_est = pred_ref$est,
    diff = pred$est - pred_ref$est,
    pr_diff = 100 * (pred$est - pred_ref$est) / pred_ref$est
  )
  if ("depth" %in% names(nd)) out$depth <- nd$depth
  out
}

#' A palette-safe wrapper around RColorBrewer
#'
#' [RColorBrewer::brewer.pal()] errors for `n` outside the palette's supported
#' range. This returns `n` colours for any `n >= 1` by clamping small requests
#' and interpolating large ones.
#'
#' @param n Number of colours requested.
#' @param palette A qualitative RColorBrewer palette name.
#' @return A character vector of `n` colours.
#' @keywords internal
#' @noRd
.safe_brewer <- function(n, palette = "Set1") {
  n <- max(1L, as.integer(n))
  if (!requireNamespace("RColorBrewer", quietly = TRUE)) {
    return(grDevices::hcl.colors(n, "Dark 3"))
  }
  max_n <- RColorBrewer::brewer.pal.info[palette, "maxcolors"]
  if (n <= 2) {
    RColorBrewer::brewer.pal(3, palette)[seq_len(n)]
  } else if (n <= max_n) {
    RColorBrewer::brewer.pal(n, palette)
  } else {
    grDevices::colorRampPalette(RColorBrewer::brewer.pal(max_n, palette))(n)
  }
}

## Shared negative-square-root transformation used by the spatial map plots ----

#' A signed square-root scales transformation
#'
#' Emphasises small deviations around zero while keeping the sign, for diverging
#' anomaly maps.
#'
#' @keywords internal
#' @noRd
.negsqrt_trans <- function() {
  scales::trans_new(
    name = "negsqrt",
    transform = function(x) ifelse(x < 0, -sqrt(abs(x)), sqrt(abs(x))),
    inverse = function(x) ifelse(x < 0, -x^2, x^2)
  )
}

# Standard color vector for grouped index series (reference is drawn in black)
.index_color_vector <- c(
  "#D696C8", "#449BCF", "#82C893", "#FF5F68",
  "#FF9252", "#FFC95B", "#056A89"
)

#' Build one spatial prediction-difference map on a ggOceanMaps basemap
#'
#' Shared by the `plot()` methods of the model, mesh and survey comparisons.
#' Aggregates a per-cell/per-year difference grid over years, converts it to
#' `sf`, and draws it on [ggOceanMaps::basemap()].
#'
#' @param grid A data frame with columns `X`, `Y`, `diff`, `pr_diff` and
#'   optionally `mean_pr_diff`.
#' @param crs Coordinate reference system of the grid.
#' @param spatial_response Column to map: `"mean"`, `"pr_mean"` or
#'   `"mean_pr_diff"`.
#' @param unit Optional unit label used when `spatial_response` is an absolute
#'   difference.
#' @param transform_color_scale Apply the signed square-root colour scale?
#' @param limit_rounding,break_rounding Rounding for fill limits and breaks.
#' @param base_size Base font size.
#' @param title Panel title.
#' @keywords internal
#' @noRd
.spatial_diff_map <- function(grid, crs, spatial_response = "pr_mean",
                              unit = NA, transform_color_scale = TRUE,
                              limit_rounding = 10, break_rounding = 5,
                              base_size = 11, title = NULL) {
  has_mpd <- "mean_pr_diff" %in% names(grid)
  agg <- grid |>
    dplyr::group_by(.data$X, .data$Y) |>
    dplyr::reframe(
      mean = mean(.data$diff, na.rm = TRUE),
      pr_mean = mean(.data$pr_diff, na.rm = TRUE),
      mean_pr_diff = if (has_mpd) mean(.data$mean_pr_diff, na.rm = TRUE) else NA_real_
    ) |>
    dplyr::mutate(X = 1000 * .data$X, Y = 1000 * .data$Y) |>
    sf::st_as_sf(
      coords = c("X", "Y"), crs = suppressWarnings(crs), remove = FALSE
    )

  vals <- agg[[spatial_response]]
  limits <- c(
    floor(stats::quantile(vals, 0, na.rm = TRUE) / limit_rounding) * limit_rounding,
    ceiling(stats::quantile(vals, 1, na.rm = TRUE) / limit_rounding) * limit_rounding
  )
  breaks <- seq(sign(limits[1]) * sqrt(abs(limits[1])), sqrt(limits[2]),
                length.out = 6)
  breaks <- round(sign(breaks) * breaks^2 / break_rounding) * break_rounding

  fill_scale <- if (transform_color_scale) {
    ggplot2::scale_fill_gradient2(
      trans = .negsqrt_trans(), breaks = breaks, midpoint = 0, limits = limits
    )
  } else {
    ggplot2::scale_fill_gradient2(midpoint = 0)
  }

  fill_lab <- if (spatial_response %in% c(
    "pr_anomaly", "total_pr_anomaly", "max_pr_anomaly", "pr_mean", "mean_pr_diff"
  )) {
    "Biomass density\npercent anomaly"
  } else if (is.na(unit)) {
    expression(atop(Biomass ~ density, anomaly))
  } else {
    bquote(atop(
      Biomass ~ density,
      paste("anomaly (", .(unit), " ", nmi^{-2}, ")")
    ))
  }

  ggOceanMaps::basemap(agg, crs = crs, base_size = base_size) +
    ggplot2::geom_raster(
      data = agg,
      ggplot2::aes(x = .data$X, y = .data$Y, fill = .data[[spatial_response]])
    ) +
    fill_scale +
    ggplot2::labs(fill = fill_lab, title = title) +
    ggplot2::theme(
      legend.position = "bottom",
      axis.text = ggplot2::element_blank(),
      axis.title = ggplot2::element_blank(),
      axis.ticks = ggplot2::element_blank(),
      strip.background = ggplot2::element_blank(),
      panel.background = ggplot2::element_blank(),
      plot.background = ggplot2::element_blank(),
      legend.background = ggplot2::element_blank(),
      strip.text.x = ggplot2::element_text(size = 10),
      legend.box.background = ggplot2::element_blank(),
      plot.margin = ggplot2::margin(5.5, 10, 5.5, 5.5)
    )
}
