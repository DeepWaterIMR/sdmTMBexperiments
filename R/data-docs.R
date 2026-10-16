#' Beaked redfish survey stations (example data)
#'
#' A compact, public example dataset of bottom-trawl survey stations for beaked
#' redfish (\emph{Sebastes mentella}) in the Barents and Norwegian Seas, used to
#' demonstrate the survey-comparison and prediction-grid functions.
#'
#' It is a subset of the public station data accompanying Vihtakari et al.
#' (2026): beaked redfish only, years 2004-2025, and five surveys with good
#' coverage (`EcoS`, `WinterS`, `CoastalS`, `EggaN`, `EggaS`). Coordinates are
#' projected to UTM zone 33N (EPSG:32633) and stored in kilometres, following the
#' \pkg{sdmTMB} convention.
#'
#' @format A data frame with 16,699 rows and 12 columns:
#' \describe{
#'   \item{cruiseseries}{Survey series identifier (the "survey" grouping).}
#'   \item{year}{Year of the survey (integer).}
#'   \item{month}{Month of the station (integer).}
#'   \item{geartype}{Trawl gear type.}
#'   \item{lon, lat}{Station longitude and latitude (decimal degrees).}
#'   \item{X, Y}{Projected coordinates (UTM zone 33N, EPSG:32633) in kilometres.}
#'   \item{depth}{Bottom depth at the station start (m).}
#'   \item{swept_area}{Swept area (square nautical miles); usable as a
#'     log-offset for catch models.}
#'   \item{biomass}{Catch biomass (kg).}
#'   \item{density}{Swept-area biomass density (kg per square nautical mile).}
#' }
#'
#' @source Public station data from the ref-index-paper repository
#'   (\url{https://github.com/DeepWaterIMR/ref-index-paper}), a public subset of
#'   the NMDC dataset
#'   (\url{https://metadata.nmdc.no/metadata-api/landingpage/a22ab5e19ba4e81b2614170bc45e0e06}).
#'   Prepared by `data-raw/sebastes.R`.
#'
#' @references
#' Vihtakari, M., Aune, M., Assmann, K. M., Howell, D., Hallfredsson, E. H., and
#' Ward, E. J. (2026). Demersal distribution and fisheries independent trends of
#' beaked and golden redfish in the Barents and Norwegian Seas. ICES Journal of
#' Marine Science, 83(2), fsag009. \doi{10.1093/icesjms/fsag009}
#'
#' @examples
#' data(sebastes)
#' table(sebastes$cruiseseries)
"sebastes"


#' Coarse bathymetry for the example data (demonstration only)
#'
#' A small depth raster covering the area of the [sebastes] example data
#' (0-45 degrees E, 61-83 degrees N; Barents and Norwegian Seas). It lets the
#' examples, tests and vignette demonstrate depth extraction in
#' [make_prediction_grid()] without the ~85 MB bathymetry download that
#' [ggOceanMaps::get_depth()] needs on first use. It is too coarse for real
#' analyses; use [sebastes_depth()] only for demonstrations.
#'
#' Derived from ETOPO 2022 (60 arc-second global relief model, NOAA National
#' Centers for Environmental Information; public domain), averaged over 3 x 3
#' blocks (about 11 km in latitude) and rounded to the nearest 10 m.
#'
#' @format A list with three elements:
#' \describe{
#'   \item{lon}{Cell-centre longitudes (ascending, decimal degrees).}
#'   \item{lat}{Cell-centre latitudes (descending, decimal degrees).}
#'   \item{depth}{Integer matrix (`length(lon)` x `length(lat)`) of depth (m,
#'     positive down). `NA` on land.}
#' }
#'
#' @source ETOPO 2022 (\doi{10.25921/fd45-gt74}), via the continuous bathymetry
#'   file of \url{https://github.com/MikkoVihtakari/ggOceanMapsLargeData}.
#'   Prepared by `data-raw/sebastes_bathy.R`.
#'
#' @seealso [sebastes_depth()]
#' @examples
#' str(sebastes_bathy)
"sebastes_bathy"

#' Depth lookup from the bundled demonstration bathymetry
#'
#' A `depth_fun` for [make_prediction_grid()] that reads the coarse
#' [sebastes_bathy] raster instead of calling [ggOceanMaps::get_depth()]. Each
#' point receives the depth of the cell it falls in. It is intended for
#' examples and tests only.
#'
#' @param pts An `sf` object of points with a defined CRS.
#'
#' @return Numeric vector of depths (m, positive down), one per point. `NA` on
#'   land or outside the raster (0-45 degrees E, 61-83 degrees N).
#'
#' @seealso [sebastes_bathy], [make_prediction_grid()]
#' @examples
#' data(sebastes)
#' eggan <- subset(sebastes, cruiseseries == "EggaN")
#' region <- make_survey_prediction_region(eggan, crs = 32633, concavity = 5)
#' grid <- make_prediction_grid(
#'   region, resolution = 20, max_depth = 1000, depth_fun = sebastes_depth
#' )
#' range(grid$depth)
#' @export
sebastes_depth <- function(pts) {
  if (!inherits(pts, c("sf", "sfc"))) stop("`pts` must be an sf or sfc object.")
  # load explicitly: lazy data are only on the search path when attached
  utils::data("sebastes_bathy", package = "sdmTMBexperiments", envir = environment())
  b <- environment()$sebastes_bathy
  xy <- sf::st_coordinates(sf::st_transform(sf::st_geometry(pts), 4326))
  step <- b$lon[2] - b$lon[1]
  i <- round((xy[, 1] - b$lon[1]) / step) + 1
  j <- round((b$lat[1] - xy[, 2]) / step) + 1
  ok <- !is.na(i) & !is.na(j) & i >= 1 & i <= length(b$lon) &
    j >= 1 & j <= length(b$lat)
  out <- rep(NA_real_, nrow(xy))
  out[ok] <- b$depth[cbind(i[ok], j[ok])]
  out
}
