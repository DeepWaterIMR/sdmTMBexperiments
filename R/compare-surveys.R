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
#'   identifying the survey series (see `survey_col`) and coordinate columns
#'   (see `xy_cols`).
#' @param compiled_index A data frame of the compiled reference index, with
#'   columns `year`, `est`, `lwr`, `upr`, `se`.
#' @param compiled_model A fitted [sdmTMB::sdmTMB()] model for the compiled
#'   index, or `NULL` (default). When provided, all settings of its original
#'   call (as with [sdmTMB::update.sdmTMB()]; e.g. family, random fields, time
#'   column, `spatial_varying`, `priors`, ...), its coordinate columns and CRS
#'   are inherited, except those overridden by `formula`, `family`, `spatial`,
#'   `spatiotemporal`, `control` and `offset_col`. Its `data` and `mesh` are
#'   replaced by each survey's data and a new mesh. A numeric `offset` or
#'   `weights` vector in the original call cannot be carried over to the
#'   survey subsets and gives an error (use `offset_col` or column-name
#'   arguments instead). Spatial prediction differences are computed. When
#'   `NULL`, spatial differences are skipped, `formula`, `family` and
#'   `object_crs` must be supplied, and the survey models use only `formula`,
#'   `family`, `spatial`, `spatiotemporal`, `control`, `offset_col`, a `"year"`
#'   time column and the `xy_cols` coordinates.
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
#' @param xy_cols Character vector of the coordinate columns in `data` and
#'   `newdata`. Only used when `compiled_model = NULL`; otherwise taken from
#'   the model mesh. Default `c("X", "Y")`.
#' @param bias_correct Logical. Apply bias correction? Default `FALSE`.
#' @param level Numeric. Confidence level for index intervals. Default `0.95`.
#' @param area Grid cell area for index calculation. Passed to
#'   [sdmTMB::get_index_split()].
#' @param silent Logical. Suppress model output? Default `TRUE`.
#' @param nsplit Integer. Number of splits for [sdmTMB::get_index_split()].
#'   Default `3`.
#' @param n_workers Integer. Number of parallel workers. Default `1`, which
#'   uses whatever [future::plan()] is currently set. Values `> 1` set a
#'   temporary `future::multisession` plan.
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
#' @examples
#' \donttest{
#' data(sebastes)
#' sub <- subset(sebastes, cruiseseries %in% c("EcoS", "WinterS") & year >= 2020)
#'
#' # A simple "compiled" full-domain model and index, used as the reference.
#' # `biomass` (raw catch), not `density`, is the response here: `density` is
#' # already swept_area-normalised, so using it together with the swept_area
#' # offset below would double-correct for effort.
#' compiled_mesh <- sdmTMB::make_mesh(sub, c("X", "Y"), cutoff = 50)
#' compiled_model <- sdmTMB::sdmTMB(
#'   biomass ~ 0 + as.factor(year), data = sub, time = "year",
#'   mesh = compiled_mesh, family = sdmTMB::tweedie(), spatiotemporal = "off",
#'   offset = log(sub$swept_area)
#' )
#' full_region <- make_survey_prediction_region(sub, crs = 32633, concavity = 5)
#' full_grid <- sdmTMB::replicate_df(
#'   make_prediction_grid(full_region, resolution = 20), "year", unique(sub$year)
#' )
#' # swept_area is in square nautical miles, so cell area must be too: convert
#' # the 20 km grid resolution to nautical miles before squaring.
#' cell_area <- (20 / 1.852)^2
#' compiled_index <- sdmTMB::get_index_split(
#'   compiled_model, newdata = full_grid, area = cell_area, nsplit = 3, silent = TRUE
#' )
#'
#' sc <- compare_surveys(
#'   data = sub, compiled_index = compiled_index, compiled_model = compiled_model,
#'   surveys = c("EcoS", "WinterS"), newdata = full_grid, object_crs = 32633,
#'   mesh_cutoff = 50, offset_col = "swept_area", area = cell_area
#' )
#' plot(sc)
#' plot(sc, type = "scatter")
#' plot(sc, type = "spatial", fill_prefix = "Biomass density")
#' }
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
  xy_cols = c("X", "Y"),
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
    # Only user-supplied settings override those of the compiled model call
    overrides <- list(
      formula = formula, family = family, spatial = spatial,
      spatiotemporal = spatiotemporal, control = control
    )
    overrides <- overrides[!vapply(overrides, is.null, logical(1))]
    # offset_col replaces the original offset (set per survey below)
    if (!is.null(offset_col)) overrides["offset"] <- list(NULL)
    # Evaluated on the main process so the arguments reach the workers
    fit_args <- do.call(
      .refit_args, c(list(compiled_model), overrides, subset_ok = FALSE)
    )
    xy_cols <- compiled_model$spde$xy_cols
    if (is.null(object_crs)) {
      mesh_crs <- compiled_model$spde$mesh$crs
      # make_mesh() has no `crs` argument, so a mesh built the usual way
      # carries an NA (not NULL) crs; catch both, otherwise this silently
      # passes an NA CRS through to the spatial plot.
      if (is.null(mesh_crs) || is.na(sf::st_crs(mesh_crs))) {
        stop("CRS not found in compiled_model mesh. Specify `object_crs`.")
      }
      object_crs <- sf::st_crs(mesh_crs)
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
    fit_args <- list(
      formula = formula, family = family, spatial = spatial,
      spatiotemporal = spatiotemporal, time = time_col, control = control
    )
  }
  if (!all(xy_cols %in% names(data)) || !all(xy_cols %in% names(newdata))) {
    stop("`data` and `newdata` must contain the coordinate columns ",
         paste(xy_cols, collapse = ", "), ".")
  }

  use_cli <- isTRUE(verbose) && requireNamespace("cli", quietly = TRUE)
  step <- function(msg) if (use_cli) cli::cli_progress_step(msg, spinner = TRUE)
  done <- function() if (use_cli) cli::cli_progress_done()
  ok <- function(msg) if (use_cli) cli::cli_alert_success(msg)
  bad <- function(msg) if (use_cli) cli::cli_alert_danger("{msg}")

  old_parallel <- .setup_parallel(n_workers)
  on.exit(.restore_parallel(old_parallel), add = TRUE)

  # Model fitting per survey series -------------------------------------------
  step(paste("Fitting", length(surveys), "survey models"))
  survey_mods <- future.apply::future_lapply(
    surveys,
    function(survey) {
      x <- dplyr::filter(data, .data[[survey_col]] == survey)
      mesh <- sdmTMB::make_mesh(x, xy_cols = xy_cols, cutoff = mesh_cutoff)
      args <- fit_args
      if (!is.null(offset_col)) args$offset <- log(x[[offset_col]])
      mod <- try(
        .refit(args, data = x, mesh = mesh, silent = silent),
        silent = TRUE
      )
      if (inherits(mod, "try-error")) {
        bad(paste0(survey, ": model failed: ",
                   conditionMessage(attr(mod, "condition"))))
      } else {
        ok(paste0(survey, ": model OK"))
      }
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
        survey_data, crs = object_crs, xy_cols = xy_cols, concavity = concavity
      )
      .clip_points_to_region(newdata, region, xy_cols = xy_cols)
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
            year = nd[[time_col]], X = nd[[xy_cols[1]]], Y = nd[[xy_cols[2]]],
            est = NA, ref_est = NA, diff = NA, pr_diff = NA, mean_pr_diff = NA
          )
        } else {
          base <- .pred_diff_base(k$mod, compiled_model, nd, time_col, xy_cols)
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
#' @details
#' For `type = "spatial"`, each grid cell is compared between a survey's
#' fitted model and the compiled reference model, for every year they share,
#' on the response scale (i.e. `predict(..., type = "response")`, e.g.
#' density rather than log density): `diff = est - ref_est` and
#' `pr_diff = 100 * diff / ref_est` (percent). `spatial_response` selects how
#' these per-year values are summarised across years into the single value
#' mapped for each cell:
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
#' @param x An object of class `sdmTMB_survey_comparison`.
#' @param type Character. `"index"` (default), `"scatter"` or `"spatial"`.
#' @param index_divisor Optional numeric divisor applied to index values.
#' @param unit Character. Unit label. If `NA`, `"Index value"` is used.
#' @param viridis Logical. Use the viridis palette for survey series? Default
#'   `FALSE`.
#' @param annotate_fit Logical. For `type = "scatter"`, annotate each survey's
#'   panel-free regression line with its fitted equation and R², coloured to
#'   match that survey? Default `TRUE`.
#' @param spatial_response Character. Column mapped in spatial plots: `"mean"`,
#'   `"pr_mean"` or `"mean_pr_diff"`. Default `"mean_pr_diff"`. See Details.
#' @param fill_prefix Character. Prefix for the spatial-plot fill legend title
#'   (`type = "spatial"`), e.g. `"Biomass density"` or `"CPUE"`. If `NULL`
#'   (default), the legend title is `"Percent anomaly"`; otherwise
#'   `paste(fill_prefix, "percent anomaly", sep = "\n")`. Surveys don't
#'   necessarily share a response variable, so this isn't inferred automatically.
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
#' @examples
#' \donttest{
#' data(sebastes)
#' sub <- subset(sebastes, cruiseseries %in% c("EcoS", "WinterS") & year >= 2020)
#' compiled_mesh <- sdmTMB::make_mesh(sub, c("X", "Y"), cutoff = 50)
#' # `biomass` (raw catch), not `density`, is the response: `density` is
#' # already swept_area-normalised, so pairing it with the swept_area offset
#' # below would double-correct for effort.
#' compiled_model <- sdmTMB::sdmTMB(
#'   biomass ~ 0 + as.factor(year), data = sub, time = "year",
#'   mesh = compiled_mesh, family = sdmTMB::tweedie(), spatiotemporal = "off",
#'   offset = log(sub$swept_area)
#' )
#' full_region <- make_survey_prediction_region(sub, crs = 32633, concavity = 5)
#' full_grid <- sdmTMB::replicate_df(
#'   make_prediction_grid(full_region, resolution = 20), "year", unique(sub$year)
#' )
#' # swept_area is in square nautical miles, so cell area must be too: convert
#' # the 20 km grid resolution to nautical miles before squaring.
#' cell_area <- (20 / 1.852)^2
#' compiled_index <- sdmTMB::get_index_split(
#'   compiled_model, newdata = full_grid, area = cell_area, nsplit = 3, silent = TRUE
#' )
#' sc <- compare_surveys(
#'   data = sub, compiled_index = compiled_index, compiled_model = compiled_model,
#'   surveys = c("EcoS", "WinterS"), newdata = full_grid, object_crs = 32633,
#'   mesh_cutoff = 50, offset_col = "swept_area", area = cell_area
#' )
#' plot(sc)                                              # scaled index time series
#' plot(sc, type = "scatter", annotate_fit = TRUE)       # survey vs compiled
#' plot(sc, type = "spatial", fill_prefix = "Biomass density") # prediction differences
#' }
#' @method plot sdmTMB_survey_comparison
#' @export
plot.sdmTMB_survey_comparison <- function(
  x,
  type = "index",
  index_divisor = NULL,
  unit = NA,
  viridis = FALSE,
  annotate_fit = TRUE,
  spatial_response = "mean_pr_diff",
  fill_prefix = NULL,
  transform_color_scale = TRUE,
  limit_rounding = 10,
  break_rounding = 5,
  base_size = 11,
  ...
) {
  surveys <- attributes(x)$surveys
  ref <- attributes(x)$reference_label

  survey_colors <- if (viridis) {
    stats::setNames(scales::viridis_pal()(length(surveys)), surveys)
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
        ggplot2::scale_y_continuous(n.breaks = 6) +
        ggplot2::theme_classic(base_size = base_size) +
        .index_axis_layers() +
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

    scatter_dat <- dat |>
      dplyr::filter(.data$model != ref) |>
      dplyr::left_join(ref_dat, by = "year")

    p <- ggplot2::ggplot(
        scatter_dat,
        ggplot2::aes(x = .data$ref_est, y = .data$est, color = .data$model)
      ) +
        ggplot2::geom_point() +
        ggplot2::geom_smooth(method = "lm", se = FALSE, formula = y ~ x) +
        ggplot2::scale_color_manual(values = survey_colors)

    if (isTRUE(annotate_fit)) {
      fit_labs <- lapply(surveys, function(s) {
        d <- dplyr::filter(scatter_dat, .data$model == s)
        if (sum(stats::complete.cases(d$ref_est, d$est)) < 2) return(NULL)
        m <- stats::lm(est ~ ref_est, data = d)
        cf <- stats::coef(m)
        r2 <- summary(m)$r.squared
        sign_op <- if (cf[2] < 0) "-" else "+"
        data.frame(
          model = s,
          label = sprintf(
            "y = %.3g %s %.3gx\nR\u00B2 = %.2f", cf[1], sign_op, abs(cf[2]), r2
          )
        )
      }) |>
        dplyr::bind_rows()
      fit_labs$model <- factor(fit_labs$model, levels = surveys)
      fit_labs <- fit_labs[order(fit_labs$model), ]
      fit_labs$vjust <- seq_len(nrow(fit_labs)) * 2.2 - 1

      p <- p + ggplot2::geom_text(
        data = fit_labs,
        ggplot2::aes(
          x = -Inf, y = Inf, label = .data$label, color = .data$model,
          vjust = .data$vjust
        ),
        hjust = -0.08, size = base_size / 3.5, inherit.aes = FALSE,
        show.legend = FALSE
      )
    }

    return(
      p +
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
    # The bare "Percent anomaly" (no "Biomass density" prefix) default only
    # applies to percent-based responses; a "mean" (absolute) response keeps
    # .spatial_diff_map()'s own label so it isn't mislabelled as a percent.
    is_pct_response <- spatial_response %in% .pct_spatial_responses
    return(cowplot::plot_grid(
      plotlist = lapply(seq_along(x$grid), function(i) {
        p <- .spatial_diff_map(
          grid = x$grid[[i]], crs = attributes(x)$crs,
          spatial_response = spatial_response, unit = unit,
          transform_color_scale = transform_color_scale,
          limit_rounding = limit_rounding, break_rounding = break_rounding,
          base_size = base_size, title = paste(names(x$grid)[i], "vs", ref),
          fill_prefix = fill_prefix
        )
        if (is_pct_response) {
          fill_lab <- if (is.null(fill_prefix)) {
            "Percent anomaly"
          } else {
            paste(fill_prefix, "percent anomaly", sep = "\n")
          }
          p <- p + ggplot2::labs(fill = fill_lab)
        }
        p
      })
    ))
  }
}
