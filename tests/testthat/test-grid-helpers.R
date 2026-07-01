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
