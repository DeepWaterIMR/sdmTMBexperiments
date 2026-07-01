## Prepare the bundled `sebastes` example dataset.
##
## Source: public beaked/golden redfish survey station data from the
## ref-index-paper repository (a public subset of the NMDC dataset):
##   https://github.com/DeepWaterIMR/ref-index-paper
##   https://metadata.nmdc.no/metadata-api/landingpage/a22ab5e19ba4e81b2614170bc45e0e06
##
## This script downloads the public station data, restricts it to beaked
## redfish (Sebastes mentella, "snabeluer"), the years 2004-2025, and five
## surveys with good coverage, projects the coordinates to UTM zone 33N
## (EPSG:32633, in km), and saves a compact demonstration dataset.

library(dplyr)

url <- "https://github.com/DeepWaterIMR/ref-index-paper/raw/main/data/public/redfish_station_data.rds"
tmp <- tempfile(fileext = ".rds")
utils::download.file(url, tmp, mode = "wb", quiet = TRUE)
raw <- readRDS(tmp)

surveys_keep <- c("EcoS", "WinterS", "CoastalS", "EggaN", "EggaS")

sebastes <- raw |>
  filter(
    .data$commonname == "snabeluer",
    .data$startyear >= 2004,
    .data$startyear <= 2025,
    .data$cruiseseries %in% surveys_keep,
    !is.na(.data$longitudestart),
    !is.na(.data$latitudestart)
  ) |>
  transmute(
    cruiseseries = .data$cruiseseries,
    year = as.integer(.data$startyear),
    month = as.integer(.data$month),
    geartype = .data$geartype,
    lon = .data$longitudestart,
    lat = .data$latitudestart,
    depth = .data$bottomdepthstart,
    # swept area in square nautical miles (gear width in m / 1852) * distance
    swept_area = (.data$gear_width / 1852) * .data$distance,
    biomass = .data$biomass,
    density = .data$rho_biomass
  ) |>
  # drop rows without the essentials for modelling
  filter(!is.na(.data$depth), !is.na(.data$swept_area), .data$swept_area > 0)

# Project to UTM zone 33N (EPSG:32633); X and Y are returned in km.
sebastes <- sdmTMB::add_utm_columns(
  as.data.frame(sebastes),
  ll_names = c("lon", "lat"),
  utm_crs = 32633
)

sebastes <- sebastes |>
  select(
    cruiseseries, year, month, geartype, lon, lat, X, Y,
    depth, swept_area, biomass, density
  ) |>
  as.data.frame()

usethis::use_data(sebastes, overwrite = TRUE, compress = "xz")
