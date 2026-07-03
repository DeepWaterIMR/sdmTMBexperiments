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
