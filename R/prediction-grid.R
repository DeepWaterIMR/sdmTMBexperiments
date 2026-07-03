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
#' data(sebastes)
#' eggan <- subset(sebastes, cruiseseries == "EggaN")
#' region <- make_survey_prediction_region(eggan, crs = 32633, concavity = 5)
#' ggOceanMaps::qmap(region, fill = I(NA))
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
#' @param max_depth Optional numeric. If supplied, grid cells with depth
#'   outside `c(1, max_depth)` are dropped. Turns on depth extraction (see
#'   `depth_fun`/`bathy_style`).
#' @param depth_fun Optional function taking an `sf` points object and
#'   returning a numeric vector of (positive) depths. Only used when
#'   `max_depth` is set. If `NULL` (default) while `max_depth` is set, depth is
#'   extracted automatically via [ggOceanMaps::get_depth()] using `bathy_style`
#'   — supply your own `depth_fun` to use a different bathymetry source (e.g. a
#'   specific GEBCO file via `bathy.style = "raster_user"` and
#'   `options(ggOceanMaps.userpath = ...)`, or a local raster/interpolation).
#' @param bathy_style Character. `bathy.style` passed to
#'   [ggOceanMaps::get_depth()] when `depth_fun` is `NULL`. Default
#'   `"raster_continuous"` (ETOPO, bundled with ggOceanMaps — no extra
#'   download path needed). Ignored when `depth_fun` is supplied.
#'
#' @return A data frame (class `sdmTMB_prediction_grid`, so
#'   [plot.sdmTMB_prediction_grid()] can be used on it directly) with columns
#'   `X`, `Y` (in model units) and, when depth filtering is applied, a `depth`
#'   column. Carries `crs`, `coord_multiplier` and `resolution` attributes.
#'
#' @author Mikko Vihtakari
#' @seealso [make_survey_prediction_region()], [plot.sdmTMB_prediction_grid()]
#' @examples
#' \donttest{
#' data(sebastes)
#' eggan <- subset(sebastes, cruiseseries == "EggaN")
#' region <- make_survey_prediction_region(eggan, crs = 32633, concavity = 5)
#'
#' # max_depth turns on depth extraction, via ggOceanMaps::get_depth() by
#' # default (bathy_style controls the bathymetry source); cells outside
#' # c(1, max_depth) are dropped. plot() then colours by depth automatically.
#' grid <- make_prediction_grid(region, resolution = 20, max_depth = 1000)
#' range(grid$depth)
#' plot(grid)
#' }
#' @export
make_prediction_grid <- function(
  region,
  resolution,
  crs = NULL,
  coord_multiplier = 1000,
  max_depth = NULL,
  depth_fun = NULL,
  bathy_style = "raster_continuous"
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

  if (!is.null(max_depth)) {
    if (is.null(depth_fun)) {
      depth_fun <- function(pts) {
        ggOceanMaps::get_depth(pts, bathy.style = bathy_style, bind = FALSE)
      }
    }
    depth <- depth_fun(sf::st_as_sf(
      data.frame(X = coords[, 1], Y = coords[, 2]),
      coords = c("X", "Y"), crs = suppressWarnings(sf::st_crs(crs))
    ))
    out$depth <- depth
    out <- out[!is.na(out$depth) & out$depth >= 1 & out$depth <= max_depth, ,
               drop = FALSE]
  }

  class(out) <- c("sdmTMB_prediction_grid", class(out))
  attr(out, "crs") <- crs
  attr(out, "coord_multiplier") <- coord_multiplier
  attr(out, "resolution") <- resolution
  out
}

#' Plot a prediction grid on a map
#'
#' @description
#' Draws the points of a [make_prediction_grid()] grid as filled squares on a
#' [ggOceanMaps::basemap()], approximating the actual grid cells. Optionally
#' colours the squares by a column (`depth` by default, when present).
#'
#' @param x A data frame from [make_prediction_grid()] (class
#'   `sdmTMB_prediction_grid`).
#' @param value Character. Column in `x` used to colour the points, e.g.
#'   `"depth"` (the default). If `NULL`, or not a column of `x`, points are
#'   drawn in a single `color`.
#' @param crs Coordinate reference system. If `NULL` (default), taken from the
#'   `crs` attribute set by [make_prediction_grid()].
#' @param xy_cols Character vector of the coordinate columns. Default
#'   `c("X", "Y")`.
#' @param coord_multiplier Numeric factor to convert coordinates to CRS units.
#'   If `NULL` (default), taken from the `coord_multiplier` attribute set by
#'   [make_prediction_grid()] (falling back to `1000`).
#' @param point_size Numeric size of the grid-cell squares. If `NULL`
#'   (default), scaled from the `resolution` attribute set by
#'   [make_prediction_grid()] (`0.08 * resolution`, falling back to `1` if
#'   unavailable) so squares roughly approximate the actual cell size.
#' @param palette Character. `viridis` palette used when colouring by `value`,
#'   passed to `option` in [ggplot2::scale_color_viridis_c()]. Default
#'   `"turbo"`.
#' @param color Character. Point colour used when not colouring by `value`.
#'   Default `"red"`.
#' @param base_size Numeric. Base font size. Default `11`.
#' @param ... Currently ignored.
#'
#' @return A `ggplot` object.
#'
#' @author Mikko Vihtakari
#' @seealso [make_prediction_grid()], [ggOceanMaps::basemap()]
#' @import ggplot2
#' @importFrom rlang .data
#' @examples
#' \donttest{
#' data(sebastes)
#' eggan <- subset(sebastes, cruiseseries == "EggaN")
#' region <- make_survey_prediction_region(eggan, crs = 32633, concavity = 5)
#' grid <- make_prediction_grid(region, resolution = 20, max_depth = 1000)
#' plot(grid)
#' plot(grid, palette = "viridis")
#' }
#' @method plot sdmTMB_prediction_grid
#' @export
plot.sdmTMB_prediction_grid <- function(
  x,
  value = "depth",
  crs = NULL,
  xy_cols = c("X", "Y"),
  coord_multiplier = NULL,
  point_size = NULL,
  palette = "turbo",
  color = "red",
  base_size = 11,
  ...
) {
  if (is.null(crs)) crs <- attr(x, "crs")
  if (is.null(crs)) {
    stop(
      "`crs` not found on `x` and none supplied. Was `x` built by ",
      "make_prediction_grid()? Otherwise specify `crs` explicitly."
    )
  }
  if (is.null(coord_multiplier)) {
    coord_multiplier <- attr(x, "coord_multiplier")
    if (is.null(coord_multiplier)) coord_multiplier <- 1000
  }
  if (is.null(point_size)) {
    resolution <- attr(x, "resolution")
    point_size <- if (is.null(resolution)) 1 else 0.08 * resolution
  }

  d <- as.data.frame(x)
  d$.X <- d[[xy_cols[1]]] * coord_multiplier
  d$.Y <- d[[xy_cols[2]]] * coord_multiplier
  d_sf <- sf::st_as_sf(
    d, coords = c(".X", ".Y"), crs = suppressWarnings(sf::st_crs(crs)),
    remove = FALSE
  )

  p <- ggOceanMaps::basemap(d_sf, crs = crs, base_size = base_size)

  has_value <- !is.null(value) && value %in% names(d)
  if (has_value) {
    p <- p +
      ggplot2::geom_sf(
        data = d_sf, ggplot2::aes(color = .data[[value]]),
        shape = 15, size = point_size, inherit.aes = FALSE
      ) +
      ggplot2::scale_color_viridis_c(option = palette) +
      ggplot2::labs(color = value)
  } else {
    p <- p +
      ggplot2::geom_sf(
        data = d_sf, shape = 15, size = point_size, color = color,
        inherit.aes = FALSE
      )
  }

  p + ggplot2::theme(legend.position = "bottom")
}
