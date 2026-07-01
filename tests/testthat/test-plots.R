# Plotting-helper tests. Skipped on CRAN (fit a small model).

test_that("plotting helpers return ggplot objects", {
  skip_on_cran()
  mesh <- sdmTMB::make_mesh(sdmTMB::pcod, c("X", "Y"), cutoff = 25)
  m <- sdmTMB::sdmTMB(
    data = sdmTMB::pcod, formula = density ~ 0 + as.factor(year),
    time = "year", mesh = mesh, family = sdmTMB::tweedie(link = "log")
  )
  nd <- sdmTMB::replicate_df(sdmTMB::qcs_grid, "year", unique(sdmTMB::pcod$year))
  pred <- predict(m, newdata = nd)

  expect_s3_class(plot_prediction_map(pred, crs = 32609), "ggplot")
  expect_s3_class(plot_random_field(pred, crs = 32609, field = "omega"), "ggplot")
  expect_s3_class(plot_random_field(pred, crs = 32609, field = "epsilon"), "ggplot")
  expect_s3_class(plot_fixed_effects(m), "ggplot")
  expect_s3_class(plot_variance_partitioning(m), "ggplot")
  expect_s3_class(plot_residual_qq(m), "ggplot")

  if (requireNamespace("inlabru", quietly = TRUE)) {
    expect_s3_class(
      plot_mesh(mesh, crs = 32609, data = sdmTMB::pcod, value = "density"),
      "ggplot"
    )
  }
})

test_that("plot_index handles a single index and a list", {
  idx <- data.frame(year = 2000:2010, est = seq(5, 9, length.out = 11))
  idx$lwr <- idx$est * 0.8
  idx$upr <- idx$est * 1.2
  expect_s3_class(plot_index(idx), "ggplot")
  expect_s3_class(plot_index(list(A = idx, B = idx)), "ggplot")
})

test_that("plot_random_field errors when the field is absent", {
  pred <- data.frame(X = 1:3, Y = 1:3, est = 1:3)
  expect_error(plot_random_field(pred, crs = 32609, field = "omega"))
})
