#' Leave-one-out influence of surveys, cruises or hauls on an sdmTMB index
#'
#' @description
#' Refits a fitted [sdmTMB::sdmTMB()] model once for each identifier in `ids`
#' with all rows of that identifier removed, and compares the resulting index
#' with the index of a refit to all data. The identifier can be a survey
#' series (which survey carries the signal of a compiled index?), a cruise, or
#' a single haul (which hauls drive an annual index value?).
#'
#' Each refit reuses the full model's mesh and every setting of its original
#' call (as [sdmTMB::update.sdmTMB()] does; formula, family, random fields,
#' offset, weights, priors, ...), so only the data change. By default the full
#' model's parameter estimates are used as starting values (falling back to a
#' cold start if the warm-started fit fails).
#'
#' Removing an identifier can leave years without data, for example when a
#' survey series was the only one sampled in some years. These years are
#' kept in the refit as `extra_time`, so that the random fields stay defined
#' and the warm start remains valid, and their index values are reported as
#' `NA`. A formula with a factor year effect cannot be estimated for such
#' years; use a smooth or random-field-only temporal structure, or expect
#' those refits to fail. Likewise, if `newdata` predicts for a level of a
#' factor in the formula (e.g. `cruiseseries = "SeriesA"`), that level cannot
#' be left out.
#'
#' @param object A fitted [sdmTMB::sdmTMB()] model. Its offset, if any, is taken
#'   from `object$offset`.
#' @param ids Values of `object$data[[id_col]]` to leave out one at a time. If
#'   `NULL` (default), every unique value.
#' @param id_col Name of the identifier column in `object$data`, e.g.
#'   `"cruiseseries"`, a cruise column or a haul identifier.
#' @param newdata Prediction grid with the predictors of the fitted model and
#'   its time column.
#' @param area Grid cell area: a single value, a column name in `newdata`, or
#'   a numeric vector with one value per row of `newdata`.
#' @param index Character. `"plugin"` (default) sums the response-scale grid
#'   predictions times `area`, which is fast and suits screening many
#'   identifiers (e.g. hauls); `"split"` uses [sdmTMB::get_index_split()] and
#'   returns standard errors and confidence intervals, which suits a few
#'   identifiers (e.g. survey series).
#' @param nsplit,bias_correct,level Passed to [sdmTMB::get_index_split()] when
#'   `index = "split"`.
#' @param warm_start Logical. Use the full model's estimates as starting
#'   values? Default `TRUE`.
#' @param n_workers Integer. Number of parallel workers. Default `1`, which
#'   uses whatever [future::plan()] is currently set. Values `> 1` set a
#'   temporary parallel plan (forked `future::multicore` where supported,
#'   otherwise `future::multisession`).
#' @param future_seed Logical or integer. Future-compatible random seed.
#' @param verbose Logical. Show progress messages (via \pkg{cli} when
#'   installed)? Default `TRUE`.
#'
#' @return An object of class `sdmTMB_leave_out`, a list with
#'   * `full`: the index of the refit to all data, by year;
#'   * `index`: the index of each leave-out refit by year, with columns `id`,
#'     `year`, `est` (and `lwr`, `upr`, `se` for `index = "split"`), `ratio`
#'     (`est` divided by the full index) and `removed` (`TRUE` for years with
#'     no data left after removing `id`, where `est` is `NA`);
#'   * `influence`: one row per identifier with the number of rows removed,
#'     the years it has data in (`id_years`), `haul_share` (its share of the
#'     rows in those years), `influence` (one minus the geometric mean ratio
#'     over those years, so positive when the identifier raises the index),
#'     `leverage` (`influence / haul_share`), `max_abs_change` and
#'     `year_max_change` (the largest absolute relative change over all years)
#'     and `all_ok` (whether the refit passed [sdmTMB::sanity()]).
#'
#' @section Influence and leverage:
#' A large `influence` on its own mostly flags the main survey of a year: if a
#' cruise supplied 60 % of a year's hauls, removing it is expected to move the
#' index. `leverage` scales the influence by the identifier's share of the
#' hauls, so a value well above 1 marks an identifier that moves the index far
#' more than its sample size warrants, typically a one-off or auxiliary cruise
#' that sampled a high-density area few other cruises cover. A practical screen
#' is `influence >= 0.1 & leverage >= 2`; see `plot(x, type = "leverage")`.
#' Screen candidates cheaply first with [density_share()].
#'
#' @author Mikko Vihtakari
#' @seealso [density_share()], [sdmTMB_data_scenarios()], [compare_surveys()],
#'   [sdmTMB_retro()], [plot.sdmTMB_leave_out()]
#' @importFrom rlang .data
#' @examples
#' \donttest{
#' data(sebastes)
#' sub <- subset(sebastes, cruiseseries %in% c("EcoS", "WinterS", "EggaN") &
#'   year >= 2018)
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
#'
#' lo <- sdmTMB_leave_out(
#'   fit, id_col = "cruiseseries", newdata = grid, area = (30 / 1.852)^2
#' )
#' lo$influence
#' plot(lo)
#' plot(lo, type = "ratio")
#' }
#' @export
sdmTMB_leave_out <- function(
  object,
  ids = NULL,
  id_col,
  newdata,
  area = 1,
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
  time_col <- object$time
  dat <- object$data
  if (!id_col %in% names(dat)) {
    stop("`object$data` has no column '", id_col, "'.")
  }
  if (is.null(ids)) ids <- unique(dat[[id_col]])
  ids <- unique(as.character(ids))
  if (!all(ids %in% as.character(dat[[id_col]]))) {
    stop("Some `ids` were not found in object$data[[\"", id_col, "\"]].")
  }

  keep_nd <- newdata[[time_col]] %in% object$fitted_time
  cell_area <- .subset_area(area, keep_nd, nrow(newdata))
  newdata <- newdata[keep_nd, , drop = FALSE]
  if (is.character(cell_area)) cell_area <- newdata[[cell_area]]

  fit_index <- function(mod) {
    .grid_index(mod, newdata, cell_area, time_col, index = index,
                nsplit = nsplit, bias_correct = bias_correct, level = level)
  }

  start_pars <- if (warm_start) sdmTMB::get_pars(object) else NULL
  data_years <- unique(dat[[time_col]])
  # Evaluated on the main process so the arguments reach the workers
  refit_args <- .refit_args(object)

  refit <- function(keep, start) {
    .refit_on_mesh(object, dat[keep, , drop = FALSE], keep, refit_args, start,
                   data_years)
  }

  use_cli <- isTRUE(verbose) && requireNamespace("cli", quietly = TRUE)
  step <- function(msg) if (use_cli) cli::cli_progress_step(msg, spinner = TRUE)
  done <- function() if (use_cli) cli::cli_progress_done()

  # The reference is a refit to all data rather than `object` itself, so the
  # reference and the leave-out fits come from the same sdmTMB version and
  # optimiser path.
  step("Refitting the full model")
  full_mod <- refit(rep(TRUE, nrow(dat)), start_pars)
  full <- fit_index(full_mod)
  rm(full_mod)
  done()

  old_parallel <- .setup_parallel(n_workers)
  on.exit(.restore_parallel(old_parallel), add = TRUE)

  step(paste("Refitting without each of", length(ids), "identifiers"))
  res <- future.apply::future_lapply(
    ids,
    function(k) {
      keep <- as.character(dat[[id_col]]) != k
      removed_years <- setdiff(data_years, dat[[time_col]][keep])
      mod <- try(refit(keep, start_pars), silent = TRUE)
      if (inherits(mod, "try-error") && warm_start) {
        mod <- try(refit(keep, NULL), silent = TRUE)
      }
      if (inherits(mod, "try-error")) {
        return(list(id = k, index = NULL, all_ok = NA))
      }
      idx <- fit_index(mod)
      idx$removed <- idx$year %in% removed_years
      value_cols <- intersect(c("est", "lwr", "upr", "se"), names(idx))
      idx[idx$removed, value_cols] <- NA
      list(
        id = k,
        index = dplyr::mutate(idx, id = k, .before = 1),
        all_ok = sdmTMB::sanity(mod, silent = TRUE)$all_ok
      )
    },
    future.seed = future_seed
  )
  done()

  index_out <- dplyr::bind_rows(lapply(res, `[[`, "index"))
  if (nrow(index_out) > 0) {
    index_out <- index_out |>
      dplyr::left_join(dplyr::select(full, "year", est_full = "est"), by = "year") |>
      dplyr::mutate(ratio = .data$est / .data$est_full) |>
      dplyr::select(-"est_full")
  }

  rows_by_year <- table(dat[[time_col]])
  id_info <- tibble::tibble(id = as.character(dat[[id_col]]), year = dat[[time_col]]) |>
    dplyr::filter(.data$id %in% ids) |>
    dplyr::summarise(
      n_removed = dplyr::n(),
      id_years = list(sort(unique(.data$year))),
      .by = "id"
    )
  # Share of the rows (hauls) of the identifier's years that the identifier
  # supplied: the influence expected if every haul counted equally
  id_info$haul_share <- id_info$n_removed / vapply(
    id_info$id_years,
    function(y) sum(rows_by_year[as.character(y)]),
    numeric(1)
  )

  influence <- id_info |>
    dplyr::left_join(
      tibble::tibble(
        id = vapply(res, `[[`, character(1), "id"),
        all_ok = vapply(res, function(r) as.logical(r$all_ok), logical(1))
      ),
      by = "id"
    )
  if (nrow(index_out) > 0) {
    stats_by_id <- index_out |>
      dplyr::left_join(dplyr::select(id_info, "id", "id_years"), by = "id") |>
      dplyr::summarise(
        influence = {
          r <- .data$ratio[.data$year %in% .data$id_years[[1]] & !is.na(.data$ratio)]
          if (length(r) == 0) NA_real_ else 1 - exp(mean(log(r)))
        },
        max_abs_change = if (all(is.na(.data$ratio))) NA_real_ else
          max(abs(.data$ratio - 1), na.rm = TRUE),
        year_max_change = if (all(is.na(.data$ratio))) NA else
          .data$year[which.max(abs(.data$ratio - 1))],
        .by = "id"
      )
    influence <- dplyr::left_join(influence, stats_by_id, by = "id")
  } else {
    influence$influence <- NA_real_
    influence$max_abs_change <- NA_real_
    influence$year_max_change <- NA
  }
  influence$leverage <- influence$influence / influence$haul_share
  influence <- influence |>
    dplyr::relocate("leverage", .after = "influence") |>
    dplyr::relocate("all_ok", .after = dplyr::last_col()) |>
    dplyr::arrange(dplyr::desc(.data$influence))

  structure(
    list(full = full, index = index_out, influence = influence),
    class = "sdmTMB_leave_out",
    id_col = id_col,
    index_type = index
  )
}

#' Plot leave-one-out influence
#'
#' @description
#' Plots the results of [sdmTMB_leave_out()]: the full index together with the
#' index from each leave-out refit (`type = "index"`), the ratio of each
#' leave-out index to the full index (`type = "ratio"`), or influence against
#' haul share (`type = "leverage"`), where identifiers above the
#' `leverage_limit` line and the `influence_limit` line are labelled. Years
#' without data after removing an identifier are gaps.
#'
#' @param x An object of class `sdmTMB_leave_out`.
#' @param type Character. `"index"` (default), `"ratio"` or `"leverage"`.
#' @param influence_limit,leverage_limit Numeric. Flag limits for
#'   `type = "leverage"`. Defaults `0.1` and `2`.
#' @param ids Optional subset of identifiers to plot. Defaults to all; for many
#'   identifiers (e.g. hauls), pass the most influential ones.
#' @param index_divisor Optional numeric divisor applied to index values.
#' @param unit Character. Unit label for the index axis. Default `NA`.
#' @param base_size Numeric. Base font size. Default `11`.
#' @param ... Currently ignored.
#'
#' @return A `ggplot` object.
#'
#' @author Mikko Vihtakari
#' @seealso [sdmTMB_leave_out()]
#' @import ggplot2
#' @importFrom rlang .data
#' @examples
#' \donttest{
#' data(sebastes)
#' sub <- subset(sebastes, cruiseseries %in% c("EcoS", "WinterS") & year >= 2020)
#' mesh <- sdmTMB::make_mesh(sub, c("X", "Y"), cutoff = 60)
#' fit <- sdmTMB::sdmTMB(
#'   biomass ~ 1, data = sub, time = "year", mesh = mesh,
#'   family = sdmTMB::tweedie(), spatiotemporal = "iid",
#'   offset = log(sub$swept_area)
#' )
#' region <- make_survey_prediction_region(sub, crs = 32633)
#' grid <- sdmTMB::replicate_df(
#'   make_prediction_grid(region, resolution = 30), "year", unique(sub$year)
#' )
#' lo <- sdmTMB_leave_out(fit, id_col = "cruiseseries", newdata = grid)
#' plot(lo)
#' plot(lo, type = "ratio")
#' plot(lo, type = "leverage")
#' }
#' @method plot sdmTMB_leave_out
#' @export
plot.sdmTMB_leave_out <- function(
  x,
  type = "index",
  ids = NULL,
  index_divisor = NULL,
  unit = NA,
  base_size = 11,
  influence_limit = 0.1,
  leverage_limit = 2,
  ...
) {
  type <- match.arg(type, c("index", "ratio", "leverage"))
  if (type == "leverage") {
    inf <- x$influence
    if (!is.null(ids)) inf <- dplyr::filter(inf, .data$id %in% ids)
    inf <- dplyr::filter(inf, is.finite(.data$influence))
    if (nrow(inf) == 0) stop("No influence values to plot.")
    inf$flagged <- inf$influence >= influence_limit &
      inf$leverage >= leverage_limit
    share_max <- max(inf$haul_share, na.rm = TRUE)
    return(
      ggplot2::ggplot(inf, ggplot2::aes(x = .data$haul_share, y = .data$influence)) +
        ggplot2::geom_hline(yintercept = c(0, influence_limit),
                            linetype = c(1, 2), color = "grey60") +
        ggplot2::geom_abline(slope = c(1, leverage_limit), intercept = 0,
                             linetype = c(3, 2), color = "grey60") +
        ggplot2::geom_point(ggplot2::aes(color = .data$flagged)) +
        ggplot2::geom_text(
          data = inf[inf$flagged, , drop = FALSE],
          ggplot2::aes(label = .data$id), size = base_size / 4,
          hjust = -0.1, vjust = 0.5, check_overlap = TRUE
        ) +
        ggplot2::scale_color_manual(
          values = c(`FALSE` = "grey40", `TRUE` = "#E41A1C"), guide = "none"
        ) +
        ggplot2::coord_cartesian(xlim = c(0, share_max * 1.15)) +
        ggplot2::labs(
          x = paste("Share of the year's hauls,", attr(x, "id_col")),
          y = "Influence (1 - leave-out / full)"
        ) +
        ggplot2::theme_classic(base_size = base_size)
    )
  }
  idx <- x$index
  if (!is.null(ids)) idx <- dplyr::filter(idx, .data$id %in% ids)
  if (nrow(idx) == 0) stop("No leave-out indices to plot.")
  id_levels <- unique(idx$id)
  id_colors <- stats::setNames(.safe_brewer(length(id_levels), "Set1"), id_levels)
  id_lab <- paste("Without", attr(x, "id_col"))

  if (type == "ratio") {
    return(
      ggplot2::ggplot(idx, ggplot2::aes(
        x = .data$year, y = .data$ratio, color = .data$id
      )) +
        ggplot2::geom_hline(yintercept = 1, linetype = 2, color = "grey50") +
        ggplot2::geom_path() +
        ggplot2::geom_point(size = 0.8) +
        ggplot2::scale_color_manual(values = id_colors) +
        ggplot2::labs(x = "Year", y = "Index ratio (leave-out / full)",
                      color = id_lab) +
        ggplot2::theme_classic(base_size = base_size) +
        .index_axis_layers() +
        ggplot2::theme(legend.position = "bottom")
    )
  }

  divisor <- if (is.null(index_divisor)) 1 else index_divisor
  full <- dplyr::mutate(x$full, id = "All data")
  dat <- dplyr::bind_rows(full, idx)
  dat$id <- factor(dat$id, levels = c("All data", id_levels))
  value_cols <- intersect(c("est", "lwr", "upr"), names(dat))
  dat[value_cols] <- dat[value_cols] / divisor
  colors <- c("All data" = "black", id_colors)

  p <- ggplot2::ggplot(dat, ggplot2::aes(
    x = .data$year, y = .data$est, color = .data$id
  ))
  if (all(c("lwr", "upr") %in% names(dat))) {
    p <- p + ggplot2::geom_ribbon(
      ggplot2::aes(ymin = .data$lwr, ymax = .data$upr, fill = .data$id),
      color = NA, alpha = 0.15
    ) +
      ggplot2::scale_fill_manual(
        values = c("All data" = "grey", id_colors), guide = "none"
      )
  }
  p +
    ggplot2::geom_path() +
    ggplot2::scale_color_manual(values = colors) +
    ggplot2::labs(
      x = "Year",
      y = if (!is.na(unit)) paste0("Index value (", unit, ")") else "Index value",
      color = NULL
    ) +
    ggplot2::expand_limits(y = 0) +
    ggplot2::theme_classic(base_size = base_size) +
    .index_axis_layers() +
    ggplot2::theme(legend.position = "bottom")
}
