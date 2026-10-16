# Skip map-rendering tests if ggOceanMaps can't draw a basemap (not installed,
# or its map data are unavailable), probing through the package's own wrapper.
skip_if_no_map_data <- function() {
  skip_if_not_installed("ggOceanMaps")
  d <- sf::st_as_sf(
    data.frame(X = c(4e5, 4.5e5), Y = c(5.5e6, 5.55e6)),
    coords = c("X", "Y"), crs = 32609
  )
  ok <- tryCatch({
    suppressMessages(suppressWarnings(
      ggplot2::ggplot_build(sdmTMBexperiments:::.basemap(d, crs = 32609))
    ))
    TRUE
  }, error = function(e) FALSE)
  if (!ok) skip("ggOceanMaps map data not available")
}
