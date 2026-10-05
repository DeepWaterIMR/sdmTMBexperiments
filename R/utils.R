## Internal helper functions shared across sdmTMBexperiments -------------------
## These are not exported. They centralise the parallel-processing setup, the
## index calculation, and the prediction-difference computation that were
## previously duplicated across the comparison functions.

#' Configure a future parallel plan
#'
#' Captures the current future plan and `future.globals.maxSize`, and sets a
#' sensible `future.globals.maxSize`. Returns the previous settings so the
#' caller can restore them with `on.exit(.restore_parallel(old))`.
#'
#' The user's own [future::plan()] is respected and left untouched when
#' `n_workers = 1`. Only when the user explicitly asks for `n_workers > 1` is a
#' portable `multisession` plan installed (works on all platforms, including
#' Windows) for the duration of the call. Users who want forked (`multicore`)
#' or cluster workers can set their own plan before calling and keep
#' `n_workers = 1`.
#'
#' @param n_workers Integer number of workers.
#' @return A list with the previous future plan and option value.
#' @keywords internal
#' @noRd
.setup_parallel <- function(n_workers) {
  old <- list(
    plan = future::plan(),
    max_size = getOption("future.globals.maxSize")
  )
  if (n_workers > 1) {
    future::plan(future::multisession, workers = n_workers)
  }
  .set_future_memory()
  old
}

#' Restore the settings changed by `.setup_parallel()`
#'
#' @param old The list returned by `.setup_parallel()`.
#' @keywords internal
#' @noRd
.restore_parallel <- function(old) {
  future::plan(old$plan)
  options(future.globals.maxSize = old$max_size)
  invisible(NULL)
}

#' Evaluate the arguments of the original sdmTMB call for refitting
#'
#' Starts from `object$call` (as [sdmTMB::update.sdmTMB()] does) so every
#' argument the user supplied to [sdmTMB::sdmTMB()] (e.g. `spatial_varying`,
#' `time_varying`, `extra_time`, `weights`, `priors`, `share_range`,
#' `anisotropy`, `reml`, ...) is carried over to refits. The arguments are
#' evaluated here, on the main process, because symbols inside a call object
#' (e.g. `priors = my_priors`) do not exist in a `future` worker and are not
#' seen by `future`'s globals detection. The result is a plain list that can
#' be sent to workers and used with `.refit()`.
#'
#' `data`, `mesh` and `silent` are supplied later by `.refit()`;
#' `previous_fit` is dropped since it does not apply to new data/meshes.
#' `control` is taken from the fitted object (including its backend).
#'
#' @param object A fitted sdmTMB model.
#' @param ... Named arguments that override those of the original call.
#' @param subset_ok Logical. Will the refits be on (a row subset of)
#'   `object$data`? If `FALSE`, row-aligned vector arguments (numeric `offset`,
#'   `weights`) cannot be carried over and an error is thrown.
#' @param envir Environment in which to evaluate the call's arguments.
#' @return A named list of arguments for [sdmTMB::sdmTMB()].
#' @keywords internal
#' @noRd
.refit_args <- function(
  object,
  ...,
  subset_ok = TRUE,
  envir = environment(object$formula[[1]])
) {
  if (is.null(envir)) envir <- globalenv()
  call_args <- as.list(object$call)[-1]
  call_args <- call_args[!names(call_args) %in%
    c("data", "mesh", "silent", "control", "previous_fit", "formula")]

  args <- lapply(names(call_args), function(nm) {
    tryCatch(
      eval(call_args[[nm]], envir = envir),
      error = function(e) {
        stop("Could not evaluate argument `", nm, "` of the original sdmTMB ",
             "call for refitting: ", conditionMessage(e), call. = FALSE)
      }
    )
  })
  names(args) <- names(call_args)

  args$formula <- if (length(object$formula) > 1) {
    object$formula
  } else {
    object$formula[[1]]
  }
  control <- object$control
  if (!is.null(object$backend)) control$backend <- object$backend
  args$control <- control

  overrides <- list(...)
  for (nm in names(overrides)) args[nm] <- list(overrides[[nm]])

  if (!subset_ok) {
    for (nm in c("offset", "weights")) {
      if (is.numeric(args[[nm]])) {
        stop("The model was fitted with a numeric `", nm, "` vector, which ",
             "cannot be carried over to new data. Refit the model with `",
             nm, "` given as a data column", if (nm == "offset") {
               " or supply `offset_col`"
             }, ".", call. = FALSE)
      }
    }
  }
  args
}

#' Refit an sdmTMB model with new data and mesh, keeping all other settings
#'
#' @param args A list from `.refit_args()`.
#' @param data The new data.
#' @param mesh The new mesh (built from `data`).
#' @param rows Logical or integer index of the rows of the original model data
#'   kept in `data`, used to subset row-aligned vector arguments (numeric
#'   `offset`, `weights`). Character (column name) offsets are left alone and
#'   looked up in the new `data`.
#' @param silent Passed to [sdmTMB::sdmTMB()].
#' @return A fitted sdmTMB model.
#' @keywords internal
#' @noRd
.refit <- function(args, data, mesh, rows = NULL, silent = TRUE) {
  for (nm in c("offset", "weights")) {
    if (is.numeric(args[[nm]]) && !is.null(rows)) {
      args[[nm]] <- args[[nm]][rows]
    }
  }
  args$data <- data
  args$mesh <- mesh
  args$silent <- silent
  do.call(sdmTMB::sdmTMB, args)
}

#' Report a failed or suspicious fit
#'
#' A `try-error` means the fit errored (not that it failed to converge); report
#' the actual error. Fits that ran but fail [sdmTMB::sanity()] are flagged
#' separately.
#'
#' @param fit A fitted sdmTMB model or a `try-error`.
#' @param label Character label used in the message.
#' @keywords internal
#' @noRd
.report_fit <- function(fit, label) {
  if (inherits(fit, "try-error")) {
    message("Model for ", label, " failed with error: ",
            conditionMessage(attr(fit, "condition")),
            " Adding NAs as index values.")
  } else if (!isTRUE(all(unlist(
    suppressMessages(sdmTMB::sanity(fit, silent = TRUE))
  )))) {
    message("Model for ", label, " did not pass sdmTMB::sanity() checks.")
  }
  invisible(NULL)
}

#' Set future.globals.maxSize for transferring fitted models to workers
#'
#' Fitted sdmTMB models are intentionally sent to parallel workers, so the
#' default `future.globals.maxSize` (which guards against accidental large
#' transfers) is raised. A generous floor (2 GiB) is always applied so the option
#' never drops below what legitimate model transfers need — this fixes both the
#' earlier "computed but never assigned" bug and a memory-constrained environment
#' setting the limit too low. When free RAM is known and large, the limit is
#' scaled up to it, capped at ~14 GiB.
#'
#' @keywords internal
#' @noRd
.set_future_memory <- function() {
  floor_bytes <- 2 * 1024^3
  cap_bytes <- 14e3 * 1024^2

  free <- tryCatch(
    if (requireNamespace("ps", quietly = TRUE)) {
      as.numeric(ps::ps_system_memory()$free)
    } else {
      NA_real_
    },
    error = function(e) NA_real_
  )

  size <- if (is.na(free)) {
    floor_bytes
  } else {
    min(max(free * 0.8, floor_bytes), cap_bytes)
  }
  options(future.globals.maxSize = size)
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
.safe_index <- function(
  mod,
  newdata,
  time_col,
  nsplit,
  bias_correct,
  level,
  area,
  silent
) {
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

#' Per-grid-cell, per-year prediction difference between a model and a
#' reference model
#'
#' Predicts both models onto the years shared with `mod`, on the response
#' scale (`type = "response"`, e.g. density rather than log density), and
#' returns one row per grid cell per year with the response predictions,
#' their absolute difference and a percent difference. Callers group this by
#' cell (and add a `mean_pr_diff` column) to summarise across years for a
#' spatial map — see the `spatial_response` argument documented in
#' `plot.sdmTMB_model_comparison()` for the exact formulas and the tradeoffs
#' between `pr_diff`-based and `mean_pr_diff`-based summaries. A `depth`
#' column is carried through when present in `newdata`.
#'
#' @param mod,ref_mod Fitted sdmTMB models.
#' @param newdata Prediction grid data frame with `xy_cols` and `time_col`.
#' @param time_col Name of the time column.
#' @param xy_cols Names of the coordinate columns in `newdata`. They are
#'   returned as `X` and `Y`.
#' @return A data frame with `year`, `X`, `Y`, (`depth`), `est`, `ref_est`,
#'   `diff` (`est - ref_est`), `pr_diff` (`100 * diff / ref_est`).
#' @keywords internal
#' @noRd
.pred_diff_base <- function(mod, ref_mod, newdata, time_col,
                            xy_cols = c("X", "Y")) {
  nd <- dplyr::filter(
    newdata,
    .data[[time_col]] %in% unique(mod$data[[time_col]])
  )
  # newdata has no offset column by design (grid cells aren't real hauls; we
  # want density predictions and area-weight them separately), so a fitted
  # model with an offset makes predict() emit an expected/benign cli_inform()
  # ("...assuming the offset vector is 0...") that would otherwise surface on
  # every call here.
  pred <- suppressMessages(
    stats::predict(mod, newdata = nd, type = "response", model = NA)
  )
  pred_ref <- suppressMessages(
    stats::predict(ref_mod, newdata = nd, type = "response", model = NA)
  )

  out <- data.frame(
    year = nd[[time_col]],
    X = nd[[xy_cols[1]]],
    Y = nd[[xy_cols[2]]],
    est = pred$est,
    ref_est = pred_ref$est,
    diff = pred$est - pred_ref$est,
    pr_diff = 100 * (pred$est - pred_ref$est) / pred_ref$est
  )
  if ("depth" %in% names(nd)) {
    out$depth <- nd$depth
  }
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

#' Whole-year-friendly axis breaks
#'
#' Wraps [scales::pretty_breaks()], but when the axis range itself is whole
#' numbers (the usual case for a `year` column) it searches for the largest
#' `n_try <= n` whose `pretty()` breaks are all whole numbers, so years are
#' shown as `2020`, not `2020.0`/`2020.5`. Ranges that aren't whole numbers
#' (a model using fractional years) fall back to the regular extended-breaks
#' algorithm.
#'
#' @param n Target number of breaks.
#' @keywords internal
#' @noRd
.year_breaks <- function(n = 10) {
  function(x) {
    if (!all(x == round(x), na.rm = TRUE)) {
      return(scales::extended_breaks(n = n)(x))
    }
    for (n_try in seq(n, 2)) {
      b <- pretty(x, n_try)
      if (all(b == round(b))) return(b)
    }
    round(pretty(x, 2))
  }
}

#' Shared x-axis/margin layers for yearly index plots
#'
#' Every index plot (`plot_index()` and the `type = "index"` methods of the
#' three comparison functions and `plot.sdmTMB_retro()`) uses
#' `coord_cartesian(expand = FALSE)` so the ribbon/path reach the panel edges.
#' That puts the last year's axis break exactly on the panel border, so its
#' tick label is only half covered by the axis strip and gets clipped by the
#' plot's outer margin unless that margin leaves it room.
#'
#' @return A list of ggplot2 layers: `coord_cartesian()`, `scale_x_continuous()`
#'   and a `theme()` with a wider right/top plot margin.
#' @keywords internal
#' @noRd
.index_axis_layers <- function() {
  list(
    ggplot2::coord_cartesian(expand = FALSE, clip = "off"),
    ggplot2::scale_x_continuous(breaks = .year_breaks(10)),
    ggplot2::theme(plot.margin = ggplot2::margin(t = 11, r = 20, b = 5.5, l = 5.5))
  )
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

#' Break points for a diverging (percent-anomaly) fill scale
#'
#' Always includes `limits` (so the map's actual range is legible) and `0`
#' (when `limits` spans it, since that's the "no change" reference for a
#' diverging scale), then fills in additional breaks -- evenly spaced in the
#' same signed-square-root space the colour scale itself uses -- up to `n`
#' total, skipping any candidate that would sit too close to an
#' already-chosen break. Without this de-crowding step, skewed/extreme ranges
#' produced breaks so close together after rounding that their labels
#' overlapped into illegible text.
#'
#' @param limits Numeric length-2 vector, the scale's `c(min, max)`.
#' @param rounding Numeric. Round breaks to a multiple of this.
#' @param n Integer. Target number of breaks (including limits/zero).
#' @keywords internal
#' @noRd
.diverging_breaks <- function(limits, rounding = 5, n = 6) {
  trans <- function(x) sign(x) * sqrt(abs(x))
  inv <- function(x) sign(x) * x^2

  span <- trans(limits[2]) - trans(limits[1])
  if (!is.finite(span) || span <= 0) return(limits)

  min_gap <- span / n

  # limits (and 0, when spanned) are kept exact; only interior candidates are
  # rounded, so the mandatory breaks are never nudged off their true value.
  kept_val <- limits
  kept_t <- trans(limits)
  if (limits[1] < 0 && limits[2] > 0) {
    kept_val <- c(kept_val, 0)
    kept_t <- c(kept_t, 0)
  }

  cand_t <- seq(trans(limits[1]), trans(limits[2]), length.out = 4 * n)
  cand_val <- round(inv(cand_t) / rounding) * rounding
  cand_t <- trans(cand_val)

  for (i in order(cand_t)) {
    if (length(kept_t) >= n) break
    if (all(abs(cand_t[i] - kept_t) >= min_gap)) {
      kept_t <- c(kept_t, cand_t[i])
      kept_val <- c(kept_val, cand_val[i])
    }
  }

  unique(kept_val[order(kept_t)])
}

# spatial_response values that are percentages (vs. absolute response-unit
# differences), shared between .spatial_diff_map()'s own fill-label logic and
# the comparison plot() methods that build a fill_prefix on top of it.
.pct_spatial_responses <- c(
  "pr_anomaly", "total_pr_anomaly", "max_pr_anomaly", "pr_mean", "mean_pr_diff"
)

# Standard color vector for grouped index series (reference is drawn in black)
.index_color_vector <- c(
  "#D696C8",
  "#449BCF",
  "#82C893",
  "#FF5F68",
  "#FF9252",
  "#FFC95B",
  "#056A89"
)

#' Build one spatial prediction-difference map on a ggOceanMaps basemap
#'
#' Shared by the `plot()` methods of the model, mesh and survey comparisons.
#' Aggregates a per-cell/per-year difference grid (see `.pred_diff_base()`)
#' over years, converts it to `sf`, and draws it on [ggOceanMaps::basemap()].
#' `mean = mean(diff)`, `pr_mean = mean(pr_diff)`, and `mean_pr_diff` is
#' carried through unchanged (it is already one constant value per cell,
#' computed by the caller as `100 * mean(diff) / mean(ref_est)`). See the
#' `spatial_response` argument documented in `plot.sdmTMB_model_comparison()`
#' for what these mean and when to prefer one over another.
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
#' @param fill_prefix Optional prefix for the fill legend title, replacing the
#'   default "Biomass density". `NULL` (default) keeps that default.
#' @keywords internal
#' @noRd
.spatial_diff_map <- function(
  grid,
  crs,
  spatial_response = "pr_mean",
  unit = NA,
  transform_color_scale = TRUE,
  limit_rounding = 10,
  break_rounding = 5,
  base_size = 11,
  title = NULL,
  fill_prefix = NULL
) {
  has_mpd <- "mean_pr_diff" %in% names(grid)
  agg <- grid |>
    dplyr::group_by(.data$X, .data$Y) |>
    dplyr::reframe(
      mean = mean(.data$diff, na.rm = TRUE),
      pr_mean = mean(.data$pr_diff, na.rm = TRUE),
      mean_pr_diff = if (has_mpd) {
        mean(.data$mean_pr_diff, na.rm = TRUE)
      } else {
        NA_real_
      }
    ) |>
    dplyr::mutate(X = 1000 * .data$X, Y = 1000 * .data$Y) |>
    sf::st_as_sf(
      coords = c("X", "Y"),
      crs = suppressWarnings(crs),
      remove = FALSE
    )

  vals <- agg[[spatial_response]]
  limits <- c(
    floor(stats::quantile(vals, 0, na.rm = TRUE) / limit_rounding) *
      limit_rounding,
    ceiling(stats::quantile(vals, 1, na.rm = TRUE) / limit_rounding) *
      limit_rounding
  )
  breaks <- .diverging_breaks(limits, rounding = break_rounding, n = 4)

  # Abbreviated labels (e.g. "-9.2M" instead of "-9232700"): break *values*
  # are already de-crowded above, but long, wide labels can still visually
  # collide on a legend of fixed width, especially for extreme/skewed ranges.
  break_labels <- scales::label_number(scale_cut = scales::cut_short_scale())

  fill_scale <- if (transform_color_scale) {
    ggplot2::scale_fill_gradient2(
      trans = .negsqrt_trans(),
      breaks = breaks,
      labels = break_labels,
      midpoint = 0,
      limits = limits
    )
  } else {
    ggplot2::scale_fill_gradient2(midpoint = 0, labels = break_labels)
  }

  fill_lab <- if (spatial_response %in% .pct_spatial_responses) {
    if (is.null(fill_prefix)) {
      "Biomass density\npercent anomaly"
    } else {
      paste(fill_prefix, "percent anomaly", sep = "\n")
    }
  } else {
    prefix <- if (is.null(fill_prefix)) quote(Biomass ~ density) else fill_prefix
    if (is.na(unit)) {
      bquote(atop(.(prefix), anomaly))
    } else {
      bquote(atop(.(prefix), paste("anomaly (", .(unit), " ", nmi^{
        -2
      }, ")")))
    }
  }

  .basemap(agg, crs = crs, base_size = base_size) +
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

#' Attach ggOceanMaps for the duration of the calling function
#'
#' ggOceanMaps looks up its built-in map data (e.g. `dd_land`) by name via the
#' search path, so map calls fail with "object 'dd_land' not found" when the
#' package is only loaded (`ggOceanMaps::`) and not attached (`library()`).
#' Attaches it if needed and detaches again when the caller exits.
#' @param env Frame whose exit triggers the detach.
#' @keywords internal
#' @noRd
.attach_ggOceanMaps <- function(env = parent.frame()) {
  if (!"package:ggOceanMaps" %in% search()) {
    suppressMessages(attachNamespace("ggOceanMaps"))
    do.call(on.exit, list(quote(detach("package:ggOceanMaps")), add = TRUE),
      envir = env)
  }
  invisible()
}

#' A basemap that falls back to a plain map without ggOceanMaps
#'
#' Uses [ggOceanMaps::basemap()] when \pkg{ggOceanMaps} is installed.
#' Otherwise returns a plain `ggplot2` map (no land polygons) with the extent
#' and projection of `data`, so non-marine users can still draw the maps.
#'
#' @param data An `sf` object defining the map extent.
#' @param crs Coordinate reference system of the map.
#' @param base_size Base font size.
#' @keywords internal
#' @noRd
.basemap <- function(data, crs, base_size = 11) {
  if (requireNamespace("ggOceanMaps", quietly = TRUE)) {
    .attach_ggOceanMaps()
    return(ggOceanMaps::basemap(data, crs = crs, base_size = base_size))
  }
  ggplot2::ggplot() +
    ggplot2::geom_sf(data = data, alpha = 0, inherit.aes = FALSE) +
    ggplot2::coord_sf(crs = suppressWarnings(sf::st_crs(crs))) +
    ggplot2::theme_bw(base_size = base_size)
}
