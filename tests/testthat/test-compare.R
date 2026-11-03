# Model-fitting tests. Kept small and skipped on CRAN.

fit_pcod_models <- function() {
  mesh <- sdmTMB::make_mesh(sdmTMB::pcod, c("X", "Y"), cutoff = 25)
  m1 <- sdmTMB::sdmTMB(
    data = sdmTMB::pcod, formula = density ~ 0 + as.factor(year),
    time = "year", mesh = mesh, family = sdmTMB::tweedie(link = "log")
  )
  m2 <- sdmTMB::sdmTMB(
    data = sdmTMB::pcod,
    formula = density ~ 0 + as.factor(year) + depth_scaled,
    time = "year", mesh = mesh, family = sdmTMB::tweedie(link = "log")
  )
  nd <- sdmTMB::replicate_df(sdmTMB::qcs_grid, "year", unique(sdmTMB::pcod$year))
  list(m1 = m1, m2 = m2, nd = nd, mesh = mesh)
}

test_that("compare_models returns the expected structure", {
  skip_on_cran()
  f <- fit_pcod_models()
  cm <- compare_models(f$m1, f$m2, newdata = f$nd, object_crs = 32609,
                       n_workers = 1)
  expect_s3_class(cm, "sdmTMB_model_comparison")
  expect_true(all(c("sanity", "nll", "index", "grid") %in% names(cm)))
  expect_true(all(c("model", "year", "est", "cv") %in% names(cm$index)))
  expect_true("mean_pr_diff" %in% names(cm$grid[[1]]))
  expect_s3_class(plot(cm), "ggplot")
})

test_that("compare_meshes returns the expected structure", {
  skip_on_cran()
  f <- fit_pcod_models()
  mc <- compare_meshes(f$m1, mesh_cutoffs = c(15, 40), newdata = f$nd,
                       object_crs = 32609, reference_name = "25 km",
                       n_workers = 1)
  expect_s3_class(mc, "sdmTMB_mesh_comparison")
  # reference level comes first in the cutoff factor
  expect_equal(levels(mc$index$cutoff)[1], "25 km")
  expect_s3_class(plot(mc), "ggplot")
})

test_that("compare_meshes validates newdata columns", {
  skip_on_cran()
  f <- fit_pcod_models()
  bad <- f$nd[, setdiff(names(f$nd), "X")]
  expect_error(
    compare_meshes(f$m1, mesh_cutoffs = 40, newdata = bad),
    "X"
  )
})

test_that("sdmTMB_retro clamps nyears and returns peels", {
  skip_on_cran()
  f <- fit_pcod_models()
  n_years <- length(unique(sdmTMB::pcod$year))
  rt <- sdmTMB_retro(f$m1, f$nd, nyears = 999, n_workers = 1)
  expect_s3_class(rt, "sdmTMB_retro")
  expect_equal(length(rt), n_years)
  expect_s3_class(plot(rt), "ggplot")
})

test_that("compare_meshes errors clearly (not an NA-CRS crash) when object_crs is omitted", {
  # Regression test: make_mesh() has no `crs` argument, so a normally built
  # mesh carries crs = NA (not NULL). An `is.null()`-only guard let that NA
  # CRS through silently, surfacing later as a cryptic
  # "missing value where TRUE/FALSE needed" from ggOceanMaps::basemap().
  skip_on_cran()
  f <- fit_pcod_models()
  expect_error(
    compare_meshes(f$m1, mesh_cutoffs = 40, newdata = f$nd, n_workers = 1),
    "CRS"
  )
})

test_that("compare_models does not silently adopt an NA CRS when object_crs is omitted", {
  skip_on_cran()
  f <- fit_pcod_models()
  cm <- compare_models(f$m1, f$m2, newdata = f$nd, n_workers = 1)
  crs <- attributes(cm)$crs
  expect_true(is.null(crs) || !is.na(crs))
})

test_that("sdmTMB_retro converges on non-terminal peels (refit_meshes = FALSE)", {
  # Regression test: reusing the fitted sdmTMBmesh unchanged for peeled data
  # (fewer rows than the mesh's stored loc_xy/A_st) made sdmTMB() error, so
  # every peel but the terminal one silently fell back to a crashed/NA index.
  skip_on_cran()
  f <- fit_pcod_models()
  rt <- sdmTMB_retro(f$m1, f$nd, nyears = 3, n_workers = 1)
  crashed <- vapply(rt, function(p) any(p$index$type == "crashed"), logical(1))
  expect_false(any(crashed))
})

fit_sebastes_surveys <- function() {
  sub <- subset(sebastes, cruiseseries %in% c("EcoS", "WinterS") & year >= 2021)
  mesh <- sdmTMB::make_mesh(sub, c("X", "Y"), cutoff = 80)
  mod <- sdmTMB::sdmTMB(
    biomass ~ 1, data = sub, time = "year", mesh = mesh,
    family = sdmTMB::tweedie(), spatiotemporal = "off",
    offset = log(sub$swept_area)
  )
  region <- make_survey_prediction_region(sub, crs = 32633)
  grid <- sdmTMB::replicate_df(
    make_prediction_grid(region, resolution = 40), "year", unique(sub$year)
  )
  grid$depth <- seq(100, 600, length.out = nrow(grid))
  idx <- sdmTMB::get_index_split(mod, newdata = grid, nsplit = 1, silent = TRUE)
  list(sub = sub, mod = mod, grid = grid, idx = idx)
}

test_that("survey_spec validates its arguments", {
  expect_s3_class(survey_spec("A"), "sdmTMB_survey_spec")
  expect_error(survey_spec(1), "series")
  expect_error(survey_spec("A", filter = "x"), "filter")
  expect_error(survey_spec("A", depth_range = 100), "depth_range")
  expect_error(survey_spec("A", predict_values = list("x")), "predict_values")
})

test_that("compare_surveys handles survey specs and the same-area comparison", {
  skip_on_cran()
  skip_if_not_installed("concaveman")
  f <- fit_sebastes_surveys()
  sc <- compare_surveys(
    data = f$sub, compiled_index = f$idx, compiled_model = f$mod,
    surveys = list(
      EcoS = "EcoS",
      "Both deep" = survey_spec(
        c("EcoS", "WinterS"), mesh_cutoff = 100, depth_range = c(300, 600)
      )
    ),
    newdata = f$grid, object_crs = 32633, mesh_cutoff = 80,
    offset_col = "swept_area", nsplit = 1, verbose = FALSE
  )
  expect_s3_class(sc, "sdmTMB_survey_comparison")
  expect_setequal(unique(sc$index$domain), c("full", "survey", "shared"))
  expect_equal(sc$settings$mesh_cutoff, c(80, 100))
  expect_equal(sc$settings$min_depth, c(NA, 300))
  # survey grids are limited to the depth band
  expect_true(all(sc$grid[["Both deep"]]$depth >= 300))
  # same-area indices exist for the survey and the compiled model
  shared <- subset(sc$index, domain == "shared")
  expect_setequal(unique(shared$model), c("EcoS", "Both deep", "Compiled"))
  expect_s3_class(plot(sc), "ggplot")
  expect_s3_class(plot(sc, type = "same_area"), "ggplot")
  expect_s3_class(plot(sc, type = "scatter"), "ggplot")
})

test_that("sdmTMB_leave_out reports NA for years without data", {
  skip_on_cran()
  skip_if_not_installed("concaveman")
  f <- fit_sebastes_surveys()
  # WinterS only in the first year: leaving it out removes that year
  sub <- subset(f$sub, cruiseseries == "EcoS" | year == min(year))
  mesh <- sdmTMB::make_mesh(sub, c("X", "Y"), mesh = f$mod$spde$mesh)
  mod <- sdmTMB::sdmTMB(
    biomass ~ 1, data = sub, time = "year", mesh = mesh,
    family = sdmTMB::tweedie(), spatiotemporal = "iid",
    offset = log(sub$swept_area)
  )
  lo <- sdmTMB_leave_out(mod, id_col = "cruiseseries", newdata = f$grid,
                         verbose = FALSE)
  expect_s3_class(lo, "sdmTMB_leave_out")
  expect_setequal(lo$influence$id, c("EcoS", "WinterS"))
  removed <- subset(lo$index, removed)
  expect_true(all(is.na(removed$est)))
  expect_s3_class(plot(lo), "ggplot")
  expect_s3_class(plot(lo, type = "ratio"), "ggplot")
})

test_that("compare_surveys handles custom grids, predict_values and extra_time", {
  skip_on_cran()
  skip_if_not_installed("concaveman")
  f <- fit_sebastes_surveys()
  # Two series sampled in alternate years, with one year missing
  sub <- subset(f$sub, (cruiseseries == "EcoS" & year %% 2 == 1) |
                  (cruiseseries == "WinterS" & year == 2022))
  region <- make_survey_prediction_region(sub, crs = 32633, buffer = 20000)
  custom <- make_prediction_grid(
    region, resolution = 40, min_depth = 50, max_depth = 1000,
    depth_fun = function(pts) seq(50, 1000, length.out = nrow(pts))
  )
  sc <- compare_surveys(
    data = f$sub, compiled_index = f$idx, compiled_model = f$mod,
    surveys = list(
      Alternating = survey_spec(
        c("EcoS", "WinterS"),
        formula = biomass ~ 0 + cruiseseries,
        filter = function(x) subset(x, (cruiseseries == "EcoS" & year %% 2 == 1) |
                                      (cruiseseries == "WinterS" & year == 2022)),
        extra_time = 2024,
        newdata = as.data.frame(custom),
        predict_values = list(cruiseseries = "EcoS")
      )
    ),
    newdata = f$grid, object_crs = 32633, mesh_cutoff = 80,
    offset_col = "swept_area", nsplit = 1, verbose = FALSE
  )
  survey_idx <- subset(sc$index, domain == "survey")
  # indices only for years with data, not for extra_time
  expect_setequal(survey_idx$year, unique(sub$year))
  expect_false(anyNA(survey_idx$est))
  shared <- subset(sc$index, domain == "shared")
  expect_false(anyNA(shared$est))
  expect_equal(sc$settings$extra_time, "2024")
})
