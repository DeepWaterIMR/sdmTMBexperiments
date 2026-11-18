#' Refit an sdmTMB index under alternative data filters
#'
#' @description
#' Refits a fitted [sdmTMB::sdmTMB()] model once per scenario, each scenario
#' being a rule that drops or modifies data rows (e.g. drop tows shorter than
#' a limit, cap densities at a quantile, drop a cruise series) or a different
#' prediction grid (e.g. restrict the index to an area sampled every year). All
#' refits reuse the model's mesh and every setting of its original call, so
#' only the data or the grid change, and the full model's estimates are used
#' as starting values.
#'
#' The function is meant for deciding how to handle an anomalous index value:
#' test general rules first, and compare them with a named exclusion of the
#' cruise or survey behind the anomaly. A general rule that removes the
#' anomaly without distorting other years is preferable; an exclusion is
#' defensible when no general rule does, and the scenario table documents why.
#' Haul-level rules (trimming or capping densities, minimum tow length) cannot
#' remove an anomaly that builds up over many moderate hauls of one cruise; use
#' [sdmTMB_leave_out()] to see whether an anomaly is driven by single hauls or
#' by whole cruises.
#'
#' @param object A fitted [sdmTMB::sdmTMB()] model.
#' @param scenarios A named list of scenarios. Each element is either
#'   * a function of the model data returning a logical vector, `TRUE` for the
#'     rows to keep (e.g. `function(d) d$tow_length >= 0.75`);
#'   * a function returning a data frame with the same rows as the model data
#'     and modified values (e.g. densities capped at a quantile); or
#'   * a list with optional elements `data` (one of the two functions above)
#'     and `newdata` (a prediction grid used for that scenario instead of
#'     `newdata`; its index is not on the same domain as the others, so compare
#'     it with `plot(x, type = "scaled")` or [peak_ratio()]).
#'
#'   A model fitted with a numeric `offset` vector keeps the original offset of
#'   each kept row, so a scenario that changes effort (e.g. swept area) only
#'   changes the offset when the model's offset was given as a column name.
#' @param newdata Prediction grid with the predictors of the fitted model and
#'   its time column.
#' @param area Grid cell area: a single value, a column name in the grids, or
#'   a numeric vector with one value per row of `newdata` (only for scenarios
#'   that use `newdata`).
#' @param baseline Character. Name of the reference scenario: a refit to all
#'   data on `newdata`. Default `"Baseline"`.
#' @param index Character. `"plugin"` (default) or `"split"` (see
#'   [sdmTMB_leave_out()]).
#' @param nsplit,bias_correct,level Passed to [sdmTMB::get_index_split()] when
#'   `index = "split"`.
#' @param warm_start Logical. Use the full model's estimates as starting
#'   values? Default `TRUE`.
#' @param n_workers Integer. Number of parallel workers. Default `1`, which
#'   uses whatever [future::plan()] is currently set. Values `> 1` set a
#'   temporary parallel plan (forked `future::multicore` where supported,
#'   otherwise `future::multisession`).
#' @param future_seed Logical or integer. Future-compatible random seed.
#' @param verbose Logical. Show progress messages? Default `TRUE`.
#'
#' @return An object of class `sdmTMB_data_scenarios`, a list with
#'   * `index`: the index of each scenario by year, with columns `scenario`,
#'     `year`, `est` (and `lwr`, `upr`, `se` for `index = "split"`), `ratio`
#'     (`est` divided by the baseline) and `removed` (`TRUE` for years without
#'     data in the scenario, where `est` is `NA`);
#'   * `summary`: one row per scenario with `n_rows` (rows kept),
#'     `n_modified` (rows whose values changed), `grid` (`"own"` when the
#'     scenario has its own grid), `mean_abs_change` (mean absolute relative
#'     change from the baseline over the years) and `all_ok` (whether the
#'     refit passed [sdmTMB::sanity()]).
#'
#' @section AI assistance:
#' AI-assisted (model not recorded); not yet reviewed in full by the current
#' model.
#'
#' @author Mikko Vihtakari
#' @seealso [peak_ratio()], [plot.sdmTMB_data_scenarios()],
#'   [sdmTMB_leave_out()], [density_share()]
#' @importFrom rlang .data
#' @examples
#' \donttest{
#' data(sebastes)
#' sub <- subset(sebastes, cruiseseries %in% c("EcoS", "WinterS") & year >= 2018)
#' mesh <- sdmTMB::make_mesh(sub, c("X", "Y"), cutoff = 60)
#' fit <- sdmTMB::sdmTMB(
#'   biomass ~ 1, data = sub, time = "year", mesh = mesh,
#'   family = sdmTMB::tweedie(), spatiotemporal = "ar1",
#'   offset = log(sub$swept_area)
#' )
#' region <- make_survey_prediction_region(sub, crs = 32633)
#' grid <- sdmTMB::replicate_df(
#'   make_prediction_grid(region, resolution = 30), "year", unique(sub$year)
#' )
#' cap <- function(d) {
#'   lim <- stats::quantile(d$density, 0.99)
#'   d$biomass <- pmin(d$biomass, lim * d$swept_area)
#'   d
#' }
#' sc <- sdmTMB_data_scenarios(
#'   fit,
#'   scenarios = list(
#'     "Drop density > 99 %" = function(d) d$density <= stats::quantile(d$density, 0.99),
#'     "Cap density at 99 %" = cap,
#'     "No EcoS" = function(d) d$cruiseseries != "EcoS",
#'     "Grid south of 74N" = list(newdata = grid[grid$Y < 8200, ])
#'   ),
#'   newdata = grid, area = (30 / 1.852)^2
#' )
#' sc$summary
#' peak_ratio(sc, year = 2020)
#' plot(sc)
#' plot(sc, type = "scaled")
#' }
#' @export
sdmTMB_data_scenarios <- function(
  object,
  scenarios,
  newdata,
  area = 1,
  baseline = "Baseline",
  index = c("plugin", "split"),
  nsplit = NULL,
  bias_correct = FALSE,
  level = 0.95,
  warm_start = TRUE,
  n_workers = 1,
  future_seed = TRUE,
  verbose = TRUE
) {
  if (!inherits(object, "sdmTMB")) stop("`object` must be a fitted sdmTMB model.")
  index <- match.arg(index)
  if (!is.list(scenarios) || is.null(names(scenarios)) ||
      any(names(scenarios) == "")) {
    stop("`scenarios` must be a named list.")
  }
  if (baseline %in% names(scenarios)) {
    stop("`baseline` ('", baseline, "') must not be a scenario name.")
  }
  time_col <- object$time
  dat <- object$data
  data_years <- unique(dat[[time_col]])

  prep_grid <- function(nd, a) {
    keep <- nd[[time_col]] %in% object$fitted_time
    a <- .subset_area(a, keep, nrow(nd))
    nd <- nd[keep, , drop = FALSE]
    if (is.character(a)) a <- nd[[a]]
    list(newdata = nd, area = a)
  }
  main_grid <- prep_grid(newdata, area)

  # Resolve every scenario to the rows kept, the (modified) data and a grid on
  # the main process, so that workers only refit
  specs <- lapply(names(scenarios), function(nm) {
    s <- scenarios[[nm]]
    if (is.function(s)) s <- list(data = s)
    if (!is.list(s) || !all(names(s) %in% c("data", "newdata"))) {
      stop("Scenario '", nm, "' must be a function or a list with `data` ",
           "and/or `newdata`.")
    }
    keep <- rep(TRUE, nrow(dat))
    x <- dat
    if (!is.null(s$data)) {
      res <- s$data(dat)
      if (is.logical(res)) {
        if (length(res) != nrow(dat)) {
          stop("Scenario '", nm, "' returned a logical vector of the wrong length.")
        }
        keep <- !is.na(res) & res
        x <- dat[keep, , drop = FALSE]
      } else if (is.data.frame(res)) {
        if (nrow(res) != nrow(dat)) {
          stop("Scenario '", nm, "' must return all rows of the data when it ",
               "returns a data frame; return a logical vector to drop rows.")
        }
        x <- res
      } else {
        stop("Scenario '", nm, "' must return a logical vector or a data frame.")
      }
    }
    if (sum(keep) == 0) stop("Scenario '", nm, "' keeps no rows.")
    orig <- dat[keep, , drop = FALSE]
    changed <- rep(FALSE, nrow(x))
    for (nm in intersect(names(dat), names(x))) {
      a <- x[[nm]]
      b <- orig[[nm]]
      same <- (is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & a == b)
      changed <- changed | !same
    }
    n_modified <- as.integer(sum(changed))
    list(
      name = nm, keep = keep, data = x, n_modified = n_modified,
      grid = if (is.null(s$newdata)) NULL else prep_grid(s$newdata, area)
    )
  })
  names(specs) <- names(scenarios)

  start_pars <- if (warm_start) sdmTMB::get_pars(object) else NULL
  refit_args <- .refit_args(object)

  run_one <- function(spec) {
    mod <- try(.refit_on_mesh(object, spec$data, spec$keep, refit_args,
                              start_pars, data_years), silent = TRUE)
    if (inherits(mod, "try-error") && warm_start) {
      mod <- try(.refit_on_mesh(object, spec$data, spec$keep, refit_args,
                                NULL, data_years), silent = TRUE)
    }
    if (inherits(mod, "try-error")) {
      return(list(index = NULL, all_ok = NA,
                  error = conditionMessage(attr(mod, "condition"))))
    }
    g <- if (is.null(spec$grid)) main_grid else spec$grid
    idx <- .grid_index(mod, g$newdata, g$area, time_col, index = index,
                       nsplit = nsplit, bias_correct = bias_correct,
                       level = level)
    idx$removed <- idx$year %in% setdiff(data_years, spec$data[[time_col]])
    value_cols <- intersect(c("est", "lwr", "upr", "se"), names(idx))
    idx[idx$removed, value_cols] <- NA
    list(index = idx, all_ok = sdmTMB::sanity(mod, silent = TRUE)$all_ok,
         error = NULL)
  }

  use_cli <- isTRUE(verbose) && requireNamespace("cli", quietly = TRUE)
  step <- function(msg) if (use_cli) cli::cli_progress_step(msg, spinner = TRUE)
  done <- function() if (use_cli) cli::cli_progress_done()

  base_spec <- list(name = baseline, keep = rep(TRUE, nrow(dat)), data = dat,
                    n_modified = 0L, grid = NULL)
  step("Refitting the baseline")
  base <- run_one(base_spec)
  done()
  if (is.null(base$index)) stop("The baseline refit failed: ", base$error)

  old_parallel <- .setup_parallel(n_workers)
  on.exit(.restore_parallel(old_parallel), add = TRUE)
  step(paste("Refitting", length(specs), "scenarios"))
  res <- future.apply::future_lapply(specs, run_one, future.seed = future_seed)
  done()
  for (nm in names(res)) {
    if (!is.null(res[[nm]]$error)) {
      warning("Scenario '", nm, "' failed: ", res[[nm]]$error, call. = FALSE)
    }
  }

  all_res <- c(stats::setNames(list(base), baseline), res)
  index_out <- dplyr::bind_rows(lapply(names(all_res), function(nm) {
    idx <- all_res[[nm]]$index
    if (is.null(idx)) return(NULL)
    dplyr::mutate(idx, scenario = nm, .before = 1)
  })) |>
    dplyr::left_join(dplyr::select(base$index, "year", est_base = "est"),
                     by = "year") |>
    dplyr::mutate(ratio = .data$est / .data$est_base) |>
    dplyr::select(-"est_base")
  index_out$scenario <- factor(index_out$scenario, levels = names(all_res))

  all_specs <- c(stats::setNames(list(base_spec), baseline), specs)
  summary_out <- tibble::tibble(
    scenario = factor(names(all_specs), levels = names(all_res)),
    n_rows = unname(vapply(all_specs, function(s) sum(s$keep), integer(1))),
    n_modified = unname(vapply(all_specs, `[[`, integer(1), "n_modified")),
    grid = unname(vapply(all_specs, function(s) if (is.null(s$grid)) "main" else "own",
                  character(1))),
    all_ok = unname(vapply(all_res, function(r) as.logical(r$all_ok), logical(1)))
  ) |>
    dplyr::left_join(
      index_out |>
        dplyr::summarise(
          mean_abs_change = mean(abs(.data$ratio - 1), na.rm = TRUE),
          .by = "scenario"
        ),
      by = "scenario"
    ) |>
    dplyr::relocate("all_ok", .after = dplyr::last_col())

  structure(
    list(index = index_out, summary = summary_out),
    class = "sdmTMB_data_scenarios",
    baseline = baseline,
    index_type = index
  )
}

#' Ratio of an index value to its neighbouring years
#'
#' @description
#' Quantifies a peak (or trough) in an index as the value in `year` divided by
#' the mean of the `neighbours`. A ratio is unaffected by the level of the
#' index, so it compares scenarios with different prediction grids.
#'
#' @param x An object from [sdmTMB_data_scenarios()] or [sdmTMB_leave_out()],
#'   or a data frame with columns `year`, `est` and optionally a grouping
#'   column.
#' @param year The year of the peak.
#' @param neighbours The years to compare with. Default the years before and
#'   after `year`.
#' @param group Name of the grouping column for a data frame. Default
#'   `"scenario"` for scenario objects and `"id"` for leave-out objects.
#'
#' @return A tibble with the group, `peak` (the index in `year`),
#'   `neighbours` (mean of the neighbouring years) and `peak_ratio`.
#'
#' @section AI assistance:
#' AI-assisted (model not recorded); not yet reviewed in full by the current
#' model.
#'
#' @author Mikko Vihtakari
#' @seealso [sdmTMB_data_scenarios()]
#' @importFrom rlang .data
#' @examples
#' idx <- data.frame(year = 2000:2004, est = c(10, 11, 20, 12, 10))
#' peak_ratio(idx, year = 2002)
#' @export
peak_ratio <- function(x, year, neighbours = c(year - 1, year + 1), group = NULL) {
  if (inherits(x, "sdmTMB_data_scenarios")) {
    dat <- x$index
    if (is.null(group)) group <- "scenario"
  } else if (inherits(x, "sdmTMB_leave_out")) {
    dat <- dplyr::bind_rows(dplyr::mutate(x$full, id = "All data"), x$index)
    if (is.null(group)) group <- "id"
  } else if (is.data.frame(x)) {
    dat <- x
  } else {
    stop("`x` must be a scenario or leave-out object or a data frame.")
  }
  if (!all(c("year", "est") %in% names(dat))) {
    stop("The index needs columns `year` and `est`.")
  }
  if (is.null(group)) {
    dat$.group <- "Index"
    group <- ".group"
  }
  peak_year <- year
  dat |>
    dplyr::summarise(
      peak = sum(.data$est[.data$year == peak_year]),
      neighbours = mean(.data$est[.data$year %in% neighbours]),
      .by = dplyr::all_of(group)
    ) |>
    dplyr::mutate(peak_ratio = .data$peak / .data$neighbours)
}

#' Plot data-filter scenarios
#'
#' @param x An object from [sdmTMB_data_scenarios()].
#' @param type Character. `"index"` (default), `"ratio"` (each scenario
#'   divided by the baseline) or `"scaled"` (each scenario divided by its own
#'   mean, which compares scenarios with different grids).
#' @param scenarios Optional subset of scenarios to plot (the baseline is
#'   always drawn).
#' @param index_divisor Optional numeric divisor applied to index values.
#' @param unit Character. Unit label for the index axis. Default `NA`.
#' @param base_size Numeric. Base font size. Default `11`.
#' @param ... Currently ignored.
#' @return A `ggplot` object.
#' @section AI assistance:
#' AI-assisted (model not recorded); not yet reviewed in full by the current
#' model.
#'
#' @author Mikko Vihtakari
#' @seealso [sdmTMB_data_scenarios()]
#' @importFrom rlang .data
#' @method plot sdmTMB_data_scenarios
#' @export
plot.sdmTMB_data_scenarios <- function(
  x,
  type = "index",
  scenarios = NULL,
  index_divisor = NULL,
  unit = NA,
  base_size = 11,
  ...
) {
  type <- match.arg(type, c("index", "ratio", "scaled"))
  base <- attr(x, "baseline")
  dat <- x$index
  if (!is.null(scenarios)) {
    dat <- dplyr::filter(dat, .data$scenario %in% c(base, scenarios))
  }
  dat$scenario <- droplevels(dat$scenario)
  levs <- levels(dat$scenario)
  cols <- c(stats::setNames("black", base),
            stats::setNames(.safe_brewer(length(levs) - 1, "Set1"),
                            setdiff(levs, base)))

  if (type == "ratio") {
    dat <- dplyr::filter(dat, .data$scenario != base)
    yvar <- "ratio"
    ylab <- "Index ratio (scenario / baseline)"
  } else if (type == "scaled") {
    dat <- dplyr::mutate(dat, est = .data$est / mean(.data$est, na.rm = TRUE),
                         .by = "scenario")
    yvar <- "est"
    ylab <- "Index / scenario mean"
  } else {
    if (!is.null(index_divisor)) {
      value_cols <- intersect(c("est", "lwr", "upr"), names(dat))
      dat[value_cols] <- dat[value_cols] / index_divisor
    }
    yvar <- "est"
    ylab <- if (!is.na(unit)) paste0("Index value (", unit, ")") else "Index value"
  }

  p <- ggplot2::ggplot(dat, ggplot2::aes(
    x = .data$year, y = .data[[yvar]], color = .data$scenario
  ))
  if (type != "index") {
    p <- p + ggplot2::geom_hline(yintercept = 1, linetype = 2, color = "grey50")
  }
  p +
    ggplot2::geom_path() +
    ggplot2::geom_point(size = 0.8) +
    ggplot2::scale_color_manual(values = cols) +
    ggplot2::labs(x = "Year", y = ylab, color = NULL) +
    ggplot2::expand_limits(y = 0) +
    ggplot2::theme_classic(base_size = base_size) +
    .index_axis_layers() +
    ggplot2::theme(legend.position = "bottom")
}
