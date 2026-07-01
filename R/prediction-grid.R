#' Build a concave-hull prediction region from survey positions
#'
#' @description
#' Creates an `sf` polygon describing the spatial footprint of a set of sampling
#' positions, using a concave hull ([concaveman::concaveman()]). This is used to
#' restrict a prediction grid to the area a survey actually covers, rather than
#' the full model domain.
#'
#' @param data A data frame with coordinate columns (see `xy_cols`) in the same
#'   units as the model (typically km).
#' @param crs Coordinate reference system of the projected coordinates.
#' @param xy_cols Character vector of length two naming the coordinate columns.
#'   Default `c("X", "Y")`.
#' @param coord_multiplier Numeric factor to convert `xy_cols` to the CRS units
#'   (e.g. `1000` to convert km to m). Default `1000`.
#' @param concavity Numeric. Concavity parameter passed to
#'   [concaveman::concaveman()]. Larger values give looser (more convex) hulls.
#'   Default `5`.
#' @param buffer Numeric. Buffer (in CRS units) applied to the hull to avoid
#'   clipping the outermost stations. Default `1`.
#'
#' @return An `sf` polygon (single feature) in the given `crs`.
#'
#' @author Mikko Vihtakari
#' @seealso [make_prediction_grid()], [compare_surveys()]
#' @importFrom rlang .data
#' @examples
#' \donttest{
#' d <- data.frame(X = runif(50, 0, 100), Y = runif(50, 0, 100))
#' region <- make_survey_prediction_region(d, crs = 32633)
#' }
#' @export
make_survey_prediction_region <- function(
  data,
  crs,
  xy_cols = c("X", "Y"),
  coord_multiplier = 1000,
  concavity = 5,
  buffer = 1
) {
  if (!requireNamespace("concaveman", quietly = TRUE)) {
    stop("Package 'concaveman' is required for make_survey_prediction_region().")
  }
  stopifnot(length(xy_cols) == 2, all(xy_cols %in% names(data)))

  pts <- data[, xy_cols, drop = FALSE]
  pts <- unique(pts)
  pts[[xy_cols[1]]] <- pts[[xy_cols[1]]] * coord_multiplier
  pts[[xy_cols[2]]] <- pts[[xy_cols[2]]] * coord_multiplier

  pts_sf <- sf::st_as_sf(
    pts, coords = xy_cols, crs = suppressWarnings(sf::st_crs(crs))
  )

  hull <- pts_sf |>
    dplyr::summarise(geometry = sf::st_combine(.data$geometry)) |>
    concaveman::concaveman(concavity = concavity) |>
    sf::st_make_valid()

  if (!is.null(buffer) && buffer != 0) {
    hull <- sf::st_buffer(hull, buffer)
  }
  hull
}

#' Clip prediction-grid points to a region
#'
#' Internal helper: keep only the rows of a coordinate data frame that fall
#' inside `region`. Coordinates are returned in their original (un-multiplied)
#' units.
#'
#' @keywords internal
#' @noRd
.clip_points_to_region <- function(data, region, xy_cols = c("X", "Y"),
                                   coord_multiplier = 1000) {
  d <- data
  d[[xy_cols[1]]] <- d[[xy_cols[1]]] * coord_multiplier
  d[[xy_cols[2]]] <- d[[xy_cols[2]]] * coord_multiplier
  d_sf <- sf::st_as_sf(
    d, coords = xy_cols,
    crs = suppressWarnings(sf::st_crs(region)), remove = FALSE
  )
  kept <- sf::st_filter(d_sf, region)
  kept <- sf::st_drop_geometry(kept)
  kept[[xy_cols[1]]] <- kept[[xy_cols[1]]] / coord_multiplier
  kept[[xy_cols[2]]] <- kept[[xy_cols[2]]] / coord_multiplier
  kept
}

#' Build a regular prediction grid over a region
#'
#' @description
#' Creates a regular grid of centre points covering an `sf` `region`, at a given
#' spatial resolution. Optionally filters the grid by depth using a
#' user-supplied depth function. Coordinates are returned in the same units as
#' the model (divided by `coord_multiplier`).
#'
#' @param region An `sf` polygon defining the prediction area (e.g. from
#'   [make_survey_prediction_region()]).
#' @param resolution Numeric. Grid cell side length, in the model coordinate
#'   units (e.g. km). Internally multiplied by `coord_multiplier` to match the
#'   CRS units.
#' @param crs Coordinate reference system. If `NULL` (default), taken from
#'   `region`.
#' @param coord_multiplier Numeric factor to convert model units to CRS units.
#'   Default `1000`.
#' @param max_depth Optional numeric. If supplied together with `depth_fun`,
#'   grid cells with depth outside `c(1, max_depth)` are dropped.
#' @param depth_fun Optional function taking an `sf` points object and returning
#'   a numeric vector of (positive) depths. Only used when `max_depth` is set.
#'
#' @return A data frame with columns `X`, `Y` (in model units) and, when depth
#'   filtering is applied, a `depth` column.
#'
#' @author Mikko Vihtakari
#' @seealso [make_survey_prediction_region()]
#' @examples
#' \donttest{
#' d <- data.frame(X = runif(50, 0, 100), Y = runif(50, 0, 100))
#' region <- make_survey_prediction_region(d, crs = 32633)
#' grid <- make_prediction_grid(region, resolution = 10)
#' }
#' @export
make_prediction_grid <- function(
  region,
  resolution,
  crs = NULL,
  coord_multiplier = 1000,
  max_depth = NULL,
  depth_fun = NULL
) {
  if (!inherits(region, c("sf", "sfc"))) {
    stop("`region` must be an sf or sfc object.")
  }
  if (is.null(crs)) crs <- sf::st_crs(region)

  cellsize <- resolution * coord_multiplier
  centers <- sf::st_make_grid(region, cellsize = cellsize, what = "centers")
  centers <- centers[region]  # keep points inside the region

  coords <- sf::st_coordinates(centers)
  out <- data.frame(
    X = coords[, 1] / coord_multiplier,
    Y = coords[, 2] / coord_multiplier
  )

  if (!is.null(max_depth) && !is.null(depth_fun)) {
    depth <- depth_fun(sf::st_as_sf(
      data.frame(X = coords[, 1], Y = coords[, 2]),
      coords = c("X", "Y"), crs = suppressWarnings(sf::st_crs(crs))
    ))
    out$depth <- depth
    out <- out[!is.na(out$depth) & out$depth >= 1 & out$depth <= max_depth, ,
               drop = FALSE]
  }
  out
}
