## Prepare the bundled `sebastes_bathy` demonstration bathymetry.
##
## Source: ETOPO 2022 (60 arc-second global relief, NOAA NCEI, public domain;
## https://doi.org/10.25921/fd45-gt74) as distributed in the 'dd_rbathy_cont'
## file of the ggOceanMapsLargeData repository
## (https://github.com/MikkoVihtakari/ggOceanMapsLargeData), which is the
## continuous bathymetry ggOceanMaps::get_depth() uses.
##
## The global 2 arc-minute grid is cropped to lon 0-45E, lat 61-83N (covering
## all `sebastes` stations), averaged over 3 x 3 blocks (~11 km in latitude),
## and rounded to the nearest 10 m. Land is NA. This keeps the package small
## (~45 KB) so examples, tests and the vignette need no 85 MB download.

cache <- path.expand("~/ggOceanMapsLargeData/dd_rbathy_cont.rda")
if (!file.exists(cache)) {
  cache <- tempfile(fileext = ".rda")
  options(timeout = 600)
  utils::download.file(
    "https://github.com/MikkoVihtakari/ggOceanMapsLargeData/raw/master/data/dd_rbathy_cont.rda",
    cache, mode = "wb"
  )
}
env <- new.env()
load(cache, envir = env)
m <- get(ls(env)[1], env)$raster[[1]] # [lon, lat]; lon from -180, lat from 90N

res <- 30  # cells per degree
fac <- 3   # aggregation factor
cols <- 180 * res + seq_len(45 * res)       # lon 0..45
rows <- (90 - 83) * res + seq_len(22 * res) # lat 83..61
sub <- m[cols, rows]

nlon <- nrow(sub) %/% fac
nlat <- ncol(sub) %/% fac
depth <- matrix(NA_real_, nlon, nlat)
for (j in seq_len(nlat)) {
  for (i in seq_len(nlon)) {
    blk <- sub[(i - 1) * fac + seq_len(fac), (j - 1) * fac + seq_len(fac)]
    if (any(!is.na(blk))) depth[i, j] <- mean(blk, na.rm = TRUE)
  }
}
depth <- round(depth / 10) * 10
storage.mode(depth) <- "integer"

step <- fac / res # degrees
lon <- 0 + step * (seq_len(nlon) - 0.5)        # cell centres, ascending
lat <- 83 - step * (seq_len(nlat) - 0.5)       # cell centres, descending

sebastes_bathy <- list(lon = lon, lat = lat, depth = depth)
usethis::use_data(sebastes_bathy, overwrite = TRUE, compress = "xz")
