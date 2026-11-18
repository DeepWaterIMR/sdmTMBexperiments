#' Share of each haul or cruise in the annual summed density
#'
#' @description
#' A cheap, model-free screen for hauls, or groups of hauls such as cruises,
#' that may dominate an annual index value. For each year the swept-area
#' density of each haul (`value_col / effort_col`) is divided by the sum of
#' densities over all hauls of that year. With `group_col`, densities are first
#' summed within each group, so the share is the group's share of the year's
#' summed density.
#'
#' Use it to choose which identifiers to refit with [sdmTMB_leave_out()]:
#' leave-one-out refits are expensive, and the identifiers with the largest
#' density shares are the only ones that can move an annual index much. A
#' screen of the two largest shares per year plus every share of at least 5 %
#' (hauls) or 10 % (cruises) has worked well.
#'
#' @param data A data frame with one row per haul.
#' @param value_col Name of the catch column (biomass or numbers).
#' @param effort_col Name of the effort column (e.g. swept area).
#' @param time_col Name of the year column. Default `"year"`.
#' @param group_col Optional name of a grouping column (e.g. a cruise
#'   identifier). If `NULL` (default), shares are calculated per haul. Cruise
#'   numbers are often reused by different vessels, so build the group from the
#'   platform and the cruise number together.
#' @param top_n,min_share Optional screen: `candidate` is `TRUE` for the
#'   `top_n` largest shares of each year and for every share of at least
#'   `min_share`. Both `NULL` (default) gives no `candidate` column.
#'
#' @return A tibble. Without `group_col`, `data` with the columns `density`,
#'   `share`, `share_rank` (1 = largest share of the year) and `haul_share`
#'   (1 / number of hauls in the year) added. With `group_col`, one row per
#'   group and year with `n_hauls`, `n_positive`, `density` (summed), `share`,
#'   `share_rank` and `haul_share` (the group's share of the year's hauls).
#'   `share / haul_share` is a model-free analogue of the `leverage` returned by
#'   [sdmTMB_leave_out()]. A `candidate` column is added when `top_n` or
#'   `min_share` is given.
#'
#' @section AI assistance:
#' AI-assisted (model not recorded); not yet reviewed in full by the current
#' model.
#'
#' @author Mikko Vihtakari
#' @seealso [sdmTMB_leave_out()], [index_by_region()]
#' @importFrom rlang .data
#' @examples
#' data(sebastes)
#' # Haul shares, screened to the two largest per year and any share >= 5 %
#' hs <- density_share(sebastes, value_col = "biomass",
#'                     effort_col = "swept_area", top_n = 2, min_share = 0.05)
#' sum(hs$candidate)
#' # Survey-series shares (with cruise data, group by platform + cruise)
#' ss <- density_share(sebastes, value_col = "biomass",
#'                     effort_col = "swept_area", group_col = "cruiseseries")
#' head(ss[order(-ss$share / ss$haul_share), ])
#' @export
density_share <- function(
  data,
  value_col,
  effort_col = "swept_area",
  time_col = "year",
  group_col = NULL,
  top_n = NULL,
  min_share = NULL
) {
  cols <- c(value_col, effort_col, time_col, group_col)
  missing_cols <- setdiff(cols, names(data))
  if (length(missing_cols) > 0) {
    stop("`data` has no column(s) ", paste(missing_cols, collapse = ", "), ".")
  }
  if (any(data[[effort_col]] <= 0, na.rm = TRUE)) {
    stop("`", effort_col, "` must be positive.")
  }

  out <- tibble::as_tibble(data) |>
    dplyr::mutate(density = .data[[value_col]] / .data[[effort_col]])

  if (is.null(group_col)) {
    out <- dplyr::mutate(out, haul_share = 1 / dplyr::n(), .by = dplyr::all_of(time_col))
  } else {
    out <- out |>
      dplyr::summarise(
        n_hauls = dplyr::n(),
        n_positive = sum(.data[[value_col]] > 0, na.rm = TRUE),
        density = sum(.data$density, na.rm = TRUE),
        .by = dplyr::all_of(c(group_col, time_col))
      ) |>
      dplyr::mutate(
        haul_share = .data$n_hauls / sum(.data$n_hauls),
        .by = dplyr::all_of(time_col)
      )
  }

  out <- out |>
    dplyr::mutate(
      share = .data$density / sum(.data$density, na.rm = TRUE),
      share_rank = rank(-.data$density, ties.method = "first", na.last = "keep"),
      .by = dplyr::all_of(time_col)
    ) |>
    dplyr::relocate("haul_share", .after = "share_rank")

  if (!is.null(top_n) || !is.null(min_share)) {
    by_rank <- if (is.null(top_n)) FALSE else out$share_rank <= top_n
    by_share <- if (is.null(min_share)) FALSE else out$share >= min_share
    out$candidate <- !is.na(out$share) & (by_rank | by_share)
  }
  out
}

#' Split a gridded index by region
#'
#' @description
#' Sums the response-scale predictions of a fitted model over a prediction
#' grid by year and by a region column of the grid. The result shows which part
#' of the domain drives an index value: a peak carried by one region, sampled
#' unusually in that year, points to a coverage artefact rather than a stock
#' change. Regions can be anything in the grid: subareas, depth bands, inside
#' and outside a survey footprint.
#'
#' The index is the plug-in sum of predictions times `area`, without standard
#' errors. Its total over regions equals the plug-in index of the whole grid.
#'
#' @param object A fitted [sdmTMB::sdmTMB()] model, or a data frame of
#'   predictions on the response scale (`predict(fit, newdata, type =
#'   "response")`) that contains `est`, the time column and `region_col`.
#' @param newdata Prediction grid with `region_col`. Not used when `object` is
#'   a data frame of predictions.
#' @param region_col Name of the region column in `newdata`.
#' @param area Grid cell area: a single value, a column name, or a numeric
#'   vector with one value per grid row. Default `1`.
#' @param time_col Name of the time column. Defaults to `object$time` for a
#'   model and `"year"` otherwise.
#' @param ref_years Optional years over which each region's mean is taken for
#'   `rel_mean`. Default all years.
#'
#' @return An object of class `sdmTMB_region_index`: a tibble with `year`,
#'   `region`, `est` (the region's index), `share` (its share of the year's
#'   total) and `rel_mean` (`est` divided by the region's mean over
#'   `ref_years`).
#'
#' @section AI assistance:
#' AI-assisted (model not recorded); not yet reviewed in full by the current
#' model.
#'
#' @author Mikko Vihtakari
#' @seealso [plot.sdmTMB_region_index()], [density_share()],
#'   [sdmTMB_leave_out()]
#' @importFrom rlang .data
#' @examples
#' \donttest{
#' mesh <- sdmTMB::make_mesh(sdmTMB::pcod, c("X", "Y"), cutoff = 20)
#' fit <- sdmTMB::sdmTMB(density ~ 1, data = sdmTMB::pcod, time = "year",
#'   mesh = mesh, family = sdmTMB::tweedie(), spatiotemporal = "iid")
#' grid <- sdmTMB::replicate_df(sdmTMB::qcs_grid, "year", unique(sdmTMB::pcod$year))
#' grid$region <- ifelse(grid$Y > 5750, "North", "South")
#' ri <- index_by_region(fit, grid, region_col = "region", area = 4)
#' plot(ri)
#' plot(ri, type = "relative")
#' }
#' @export
index_by_region <- function(
  object,
  newdata = NULL,
  region_col,
  area = 1,
  time_col = NULL,
  ref_years = NULL
) {
  if (inherits(object, "sdmTMB")) {
    if (is.null(time_col)) time_col <- object$time
    if (is.null(newdata)) stop("`newdata` is required for a fitted model.")
    if (!region_col %in% names(newdata)) {
      stop("`newdata` has no column '", region_col, "'.")
    }
    keep <- newdata[[time_col]] %in% object$fitted_time
    area <- .subset_area(area, keep, nrow(newdata))
    newdata <- newdata[keep, , drop = FALSE]
    pred <- suppressMessages(
      stats::predict(object, newdata = newdata, type = "response")
    )
  } else if (is.data.frame(object)) {
    if (is.null(time_col)) time_col <- "year"
    pred <- object
    if (!all(c("est", time_col, region_col) %in% names(pred))) {
      stop("A prediction data frame needs columns `est`, '", time_col,
           "' and '", region_col, "'.")
    }
  } else {
    stop("`object` must be a fitted sdmTMB model or a data frame of predictions.")
  }
  if (is.character(area)) area <- pred[[area]]

  out <- tibble::tibble(
    year = pred[[time_col]],
    region = pred[[region_col]],
    est = pred$est * area
  ) |>
    dplyr::summarise(est = sum(.data$est), .by = c("year", "region")) |>
    dplyr::mutate(share = .data$est / sum(.data$est), .by = "year")

  ref <- if (is.null(ref_years)) unique(out$year) else ref_years
  out <- out |>
    dplyr::mutate(
      rel_mean = .data$est / mean(.data$est[.data$year %in% ref]),
      .by = "region"
    ) |>
    dplyr::arrange(.data$year, .data$region)

  class(out) <- c("sdmTMB_region_index", class(out))
  out
}

#' Plot an index split by region
#'
#' @param x An object from [index_by_region()].
#' @param type Character. `"index"` (default; stacked regional indices),
#'   `"share"` (each region's share of the year's index) or `"relative"` (each
#'   region's index divided by its own mean).
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
#' @seealso [index_by_region()]
#' @importFrom rlang .data
#' @method plot sdmTMB_region_index
#' @export
plot.sdmTMB_region_index <- function(
  x,
  type = "index",
  index_divisor = NULL,
  unit = NA,
  base_size = 11,
  ...
) {
  type <- match.arg(type, c("index", "share", "relative"))
  x <- tibble::as_tibble(unclass(x))
  if (!is.null(index_divisor)) x$est <- x$est / index_divisor
  regions <- unique(x$region)
  cols <- stats::setNames(.safe_brewer(length(regions), "Set1"), regions)

  if (type == "index") {
    p <- ggplot2::ggplot(x, ggplot2::aes(
      x = .data$year, y = .data$est, fill = .data$region
    )) +
      ggplot2::geom_area(color = "white", linewidth = 0.2) +
      ggplot2::scale_fill_manual(values = cols) +
      ggplot2::labs(
        x = "Year",
        y = if (!is.na(unit)) paste0("Index value (", unit, ")") else "Index value",
        fill = NULL
      )
  } else {
    yvar <- if (type == "share") "share" else "rel_mean"
    p <- ggplot2::ggplot(x, ggplot2::aes(
      x = .data$year, y = .data[[yvar]], color = .data$region
    )) +
      ggplot2::geom_path() +
      ggplot2::geom_point(size = 0.8) +
      ggplot2::scale_color_manual(values = cols) +
      ggplot2::labs(
        x = "Year",
        y = if (type == "share") "Share of the year's index" else
          "Index / regional mean",
        color = NULL
      )
    if (type == "relative") {
      p <- p + ggplot2::geom_hline(yintercept = 1, linetype = 2, color = "grey50")
    }
  }
  p +
    ggplot2::expand_limits(y = 0) +
    ggplot2::theme_classic(base_size = base_size) +
    .index_axis_layers() +
    ggplot2::theme(legend.position = "bottom")
}
