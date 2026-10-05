# Refits must reproduce the original model settings. Skipped on CRAN.

fit_complex_model <- function(offset_as_column = FALSE) {
  d <- sdmTMB::pcod
  set.seed(1)
  d$off <- log(stats::runif(nrow(d), 0.5, 2))
  w <- stats::runif(nrow(d), 0.5, 1.5)
  off <- d$off
  my_priors <- sdmTMB::sdmTMBpriors(
    matern_s = sdmTMB::pc_matern(range_gt = 10, sigma_lt = 5)
  )
  mesh <- sdmTMB::make_mesh(d, c("X", "Y"), cutoff = 25)
  fit <- if (offset_as_column) {
    sdmTMB::sdmTMB(
      density ~ 0 + as.factor(year), data = d, mesh = mesh, time = "year",
      family = sdmTMB::tweedie(), spatial_varying = ~ 0 + depth_scaled,
      weights = w, priors = my_priors, share_range = FALSE, offset = "off",
      spatiotemporal = "iid"
    )
  } else {
    sdmTMB::sdmTMB(
      density ~ 0 + as.factor(year), data = d, mesh = mesh, time = "year",
      family = sdmTMB::tweedie(), spatial_varying = ~ 0 + depth_scaled,
      weights = w, priors = my_priors, share_range = FALSE, offset = off,
      spatiotemporal = "iid"
    )
  }
  nd <- sdmTMB::replicate_df(sdmTMB::qcs_grid, "year", unique(d$year))
  list(fit = fit, nd = nd, data = d)
}

test_that("sdmTMB_retro peel 0 reproduces the original fit and index", {
  skip_on_cran()
  f <- fit_complex_model()
  rt <- sdmTMB_retro(f$fit, f$nd, nyears = 2, save_models = TRUE)
  expect_equal(as.numeric(logLik(rt[[1]]$model)), as.numeric(logLik(f$fit)),
               tolerance = 1e-6)
  expect_equal(rt[[1]]$model$model$par, f$fit$model$par, tolerance = 1e-4)
  idx <- suppressMessages(
    sdmTMB::get_index_split(f$fit, newdata = f$nd, nsplit = 3, silent = TRUE)
  )
  expect_equal(rt[[1]]$index$est, idx$est, tolerance = 1e-4)
  # the second peel drops the terminal year
  expect_equal(max(rt[[2]]$model$data$year), sort(unique(f$data$year), TRUE)[2])
})

test_that("compare_meshes reproduces the original fit and index", {
  skip_on_cran()
  f <- fit_complex_model()
  mc <- compare_meshes(f$fit, mesh_cutoffs = 25, newdata = f$nd,
                       object_crs = 32609, save_models = TRUE)
  expect_equal(as.numeric(logLik(mc$models[["Reference"]])),
               as.numeric(logLik(f$fit)), tolerance = 1e-6)
  # the same cutoff as the original mesh gives the same model
  expect_equal(as.numeric(logLik(mc$models[["25"]])),
               as.numeric(logLik(f$fit)), tolerance = 1e-6)
  idx <- suppressMessages(
    sdmTMB::get_index_split(f$fit, newdata = f$nd, nsplit = 3, silent = TRUE)
  )
  ref_idx <- mc$index[mc$index$cutoff == "Reference", ]
  expect_equal(ref_idx$est, idx$est, tolerance = 1e-4)
})

test_that("refits carry arguments to parallel workers", {
  skip_on_cran()
  # workers load the installed package, so only test against an installed copy
  skip_if_not(testthat::is_checking())
  f <- fit_complex_model()
  rt <- sdmTMB_retro(f$fit, f$nd, nyears = 2, save_models = TRUE,
                     n_workers = 2)
  expect_equal(as.numeric(logLik(rt[[1]]$model)), as.numeric(logLik(f$fit)),
               tolerance = 1e-6)
})

test_that("numeric and column-name offsets give identical refits", {
  skip_on_cran()
  f1 <- fit_complex_model(offset_as_column = FALSE)
  f2 <- fit_complex_model(offset_as_column = TRUE)
  expect_equal(as.numeric(logLik(f1$fit)), as.numeric(logLik(f2$fit)))
  rt1 <- sdmTMB_retro(f1$fit, f1$nd, nyears = 2)
  rt2 <- sdmTMB_retro(f2$fit, f2$nd, nyears = 2)
  expect_equal(rt1[[2]]$index$est, rt2[[2]]$index$est, tolerance = 1e-6)
})

test_that("sdmTMB_retro requires a cutoff when refitting meshes", {
  skip_on_cran()
  f <- fit_complex_model()
  expect_error(sdmTMB_retro(f$fit, f$nd, nyears = 2, refit_meshes = TRUE),
               "cutoff")
})

test_that("sdmTMB_mesh_cv passes the offset to sdmTMB_cv()", {
  skip_on_cran()
  skip_if_not_installed("blockCV")
  d <- sdmTMB::pcod
  set.seed(1)
  off <- log(stats::runif(nrow(d), 0.5, 2))
  mesh <- sdmTMB::make_mesh(d, c("X", "Y"), cutoff = 30)
  fit <- sdmTMB::sdmTMB(
    density ~ 1, data = d, mesh = mesh, family = sdmTMB::tweedie(),
    offset = off
  )
  cv <- suppressWarnings(
    sdmTMB_mesh_cv(fit, mesh_cutoffs = 30, k = 2, object_crs = 32609)
  )
  expect_false(cv$crashed)
  cv_fit <- attr(cv, "cv")[[1]]$models[[1]]
  expect_equal(
    cv_fit$data[[".sdmTMBexperiments_offset"]][order(cv_fit$data[["_sdm_order_"]])],
    off
  )
  expect_equal(cv_fit$offset, cv_fit$data[[".sdmTMBexperiments_offset"]])
})

test_that("functions work with coordinate columns not named X and Y", {
  skip_on_cran()
  skip_if_not_installed("concaveman")
  skip_if_no_map_data()
  d <- sdmTMB::pcod
  names(d)[names(d) == "X"] <- "lon_km"
  names(d)[names(d) == "Y"] <- "lat_km"
  d$survey <- ifelse(d$year < 2010, "A", "B")
  grid <- sdmTMB::qcs_grid
  names(grid)[names(grid) == "X"] <- "lon_km"
  names(grid)[names(grid) == "Y"] <- "lat_km"
  nd <- sdmTMB::replicate_df(grid, "year", unique(d$year))

  mesh <- sdmTMB::make_mesh(d, c("lon_km", "lat_km"), cutoff = 25)
  m1 <- sdmTMB::sdmTMB(
    density ~ 0 + as.factor(year), data = d, mesh = mesh, time = "year",
    family = sdmTMB::tweedie(), spatiotemporal = "off"
  )
  m2 <- update(m1, formula = density ~ 0 + as.factor(year) + depth_scaled)

  rt <- sdmTMB_retro(m1, nd, nyears = 2, refit_meshes = TRUE, cutoff = 25)
  expect_false(any(vapply(rt, function(p) any(p$index$type == "crashed"),
                          logical(1))))

  mc <- compare_meshes(m1, mesh_cutoffs = 40, newdata = nd, object_crs = 32609)
  expect_true(all(c("X", "Y") %in% names(mc$pred_diff[[1]])))
  expect_false(anyNA(mc$pred_diff[[1]]$est))

  cm <- compare_models(m1, m2, newdata = nd, object_crs = 32609)
  expect_false(anyNA(cm$grid[[1]]$est))
  expect_s3_class(plot(cm, type = "spatial"), "ggplot")

  idx <- suppressMessages(
    sdmTMB::get_index_split(m1, newdata = nd, nsplit = 3, silent = TRUE)
  )
  sc <- compare_surveys(
    data = d, compiled_index = idx, compiled_model = m1, survey_col = "survey",
    newdata = nd, object_crs = 32609, mesh_cutoff = 30, verbose = FALSE
  )
  expect_false(anyNA(sc$index$est))

  bad <- nd[, setdiff(names(nd), "lon_km")]
  expect_error(compare_meshes(m1, mesh_cutoffs = 40, newdata = bad), "lon_km")
})

test_that("compare_surveys errors on a numeric offset it cannot subset", {
  skip_on_cran()
  d <- sdmTMB::pcod
  d$survey <- ifelse(d$year < 2010, "A", "B")
  off <- rep(0, nrow(d))
  mesh <- sdmTMB::make_mesh(d, c("X", "Y"), cutoff = 30)
  m <- sdmTMB::sdmTMB(
    density ~ 1, data = d, mesh = mesh, time = "year",
    family = sdmTMB::tweedie(), spatiotemporal = "off", offset = off
  )
  nd <- sdmTMB::replicate_df(sdmTMB::qcs_grid, "year", unique(d$year))
  expect_error(
    compare_surveys(
      data = d, compiled_index = data.frame(), compiled_model = m,
      survey_col = "survey", newdata = nd, object_crs = 32609, verbose = FALSE
    ),
    "offset"
  )
})
