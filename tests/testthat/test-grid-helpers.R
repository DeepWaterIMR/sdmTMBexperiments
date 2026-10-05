test_that("make_survey_prediction_region builds a valid hull", {
  skip_if_not_installed("concaveman")
  data(sebastes)
  d <- subset(sebastes, cruiseseries == "EggaN")
  region <- make_survey_prediction_region(d, crs = 32633, concavity = 5)
  expect_s3_class(region, "sf")
  expect_true(as.numeric(sf::st_area(region)) > 0)
})

test_that("make_prediction_grid returns points inside the region", {
  skip_if_not_installed("concaveman")
  data(sebastes)
  d <- subset(sebastes, cruiseseries == "EggaN")
  region <- make_survey_prediction_region(d, crs = 32633)
  grid <- make_prediction_grid(region, resolution = 20)
  expect_true(is.data.frame(grid))
  expect_true(all(c("X", "Y") %in% names(grid)))
  expect_gt(nrow(grid), 0)
  # X/Y are returned in km (model units), so within the survey footprint range
  expect_true(all(grid$X > 0 & grid$X < 2000))
})

test_that("make_prediction_grid errors on non-sf region", {
  expect_error(make_prediction_grid(data.frame(X = 1, Y = 1), resolution = 10))
})

test_that("make_prediction_grid extracts depth automatically via ggOceanMaps", {
  skip_on_cran()
  skip_if_not_installed("concaveman")
  skip_if_not_installed("ggOceanMaps")
  data(sebastes)
  d <- subset(sebastes, cruiseseries == "EggaN")
  region <- make_survey_prediction_region(d, crs = 32633)

  grid <- make_prediction_grid(region, resolution = 20, max_depth = 1000)
  expect_true("depth" %in% names(grid))
  expect_true(all(grid$depth >= 1 & grid$depth <= 1000))

  # a custom depth_fun overrides the automatic ggOceanMaps::get_depth() lookup
  grid2 <- make_prediction_grid(
    region, resolution = 20, max_depth = 1000,
    depth_fun = function(pts) rep(500, nrow(pts))
  )
  expect_true(all(grid2$depth == 500))
})

test_that("plot.sdmTMB_prediction_grid works with and without a value column", {
  skip_if_not_installed("concaveman")
  skip_if_no_map_data()
  data(sebastes)
  d <- subset(sebastes, cruiseseries == "EggaN")
  region <- make_survey_prediction_region(d, crs = 32633)
  grid <- make_prediction_grid(region, resolution = 20)

  expect_s3_class(grid, "sdmTMB_prediction_grid")
  expect_equal(attr(grid, "crs"), sf::st_crs(32633))
  expect_equal(attr(grid, "resolution"), 20)

  # no "depth" column present: falls back to a plain point layer
  expect_s3_class(plot(grid), "ggplot")

  grid$depth <- seq_len(nrow(grid))
  expect_s3_class(plot(grid), "ggplot")
})

test_that("plot.sdmTMB_prediction_grid errors without a CRS", {
  d <- data.frame(X = 1:3, Y = 1:3)
  class(d) <- c("sdmTMB_prediction_grid", class(d))
  expect_error(plot(d), "crs")
})
