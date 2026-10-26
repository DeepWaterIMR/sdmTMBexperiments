# Edge cases: failed fits, model naming, non-default time/coordinate settings,
# per-row areas and barrier meshes. Skipped on CRAN.

fit_small <- function(time = "year") {
  d <- sdmTMB::pcod
  d <- d[d$year >= 2011, ]
  nd <- sdmTMB::replicate_df(sdmTMB::qcs_grid, "year", unique(d$year))
  if (time != "year") {
    d[[time]] <- d$year
    nd[[time]] <- nd$year
  }
  mesh <- sdmTMB::make_mesh(d, c("X", "Y"), cutoff = 30)
  m <- sdmTMB::sdmTMB(
    density ~ 0 + as.factor(year), data = d, mesh = mesh, time = time,
    family = sdmTMB::tweedie(), spatiotemporal = "off"
  )
  m2 <- sdmTMB::sdmTMB(
    density ~ depth_scaled, data = d, mesh = mesh, time = time,
    family = sdmTMB::tweedie(), spatiotemporal = "off"
  )
  list(m = m, m2 = m2, d = d, nd = nd)
}

test_that("sanity table keeps its shape when a fit failed", {
  skip_on_cran()
  f <- fit_small()
  failed <- try(stop("boom"), silent = TRUE)
  tab <- sdmTMBexperiments:::.sanity_table(list(ok = f$m, bad = failed))
  checks <- unlist(sdmTMB::sanity(f$m, silent = TRUE))
  expect_identical(names(tab), c("ok", "bad"))
  expect_identical(row.names(tab), names(checks))
  expect_true(all(is.na(tab$bad)))
  expect_equal(tab$ok, unname(checks))
})

test_that("reference model is black whatever the model names", {
  skip_on_cran()
  f <- fit_small()
  # names not in alphabetical order, reference not first
  cm <- compare_models(list(zz = f$m2, aa = f$m), newdata = f$nd,
                       reference_model = 1, object_crs = 32609)
  b <- ggplot2::ggplot_build(plot(cm))
  path <- b$data[[2]]
  # group 1 is the first factor level, i.e. the reference
  expect_identical(unique(path$colour[path$group == 1]), "black")
  expect_false(any(path$colour[path$group != 1] == "black"))
  expect_false(anyNA(sdmTMBexperiments:::.series_colors(10)))
})

test_that("non-integer mesh cutoffs are kept", {
  skip_on_cran()
  f <- fit_small()
  mc <- compare_meshes(f$m, mesh_cutoffs = 37.5, newdata = f$nd,
                       object_crs = 32609)
  expect_false(anyNA(mc$index$cutoff))
  expect_true("37.5" %in% levels(mc$index$cutoff))
})

test_that("compare_meshes handles a failed reference refit", {
  skip_on_cran()
  f <- fit_small()
  real_refit <- sdmTMBexperiments:::.refit
  local_mocked_bindings(.refit = function(args, data, mesh, ...) {
    if (identical(mesh, f$m$spde)) stop("boom")
    real_refit(args, data, mesh, ...)
  })
  expect_warning(
    mc <- suppressMessages(compare_meshes(
      f$m, mesh_cutoffs = 40, newdata = f$nd, object_crs = 32609
    )),
    "reference model refit failed"
  )
  expect_true(all(is.na(mc$pred_diff[[1]]$est)))
})

test_that("sdmTMB_retro accepts a numeric area vector", {
  skip_on_cran()
  f <- fit_small()
  r1 <- sdmTMB_retro(f$m, f$nd, nyears = 2, area = 4)
  r2 <- sdmTMB_retro(f$m, f$nd, nyears = 2, area = rep(4, nrow(f$nd)))
  expect_equal(r2[[2]]$index$est, r1[[2]]$index$est)
  expect_error(
    sdmTMB_retro(f$m, f$nd, nyears = 2, area = c(1, 2)),
    "one value per row"
  )
})

test_that("a time column not called `year` works", {
  skip_on_cran()
  f <- fit_small(time = "survey_year")
  rt <- sdmTMB_retro(f$m, f$nd, nyears = 2)
  expect_true("year" %in% names(rt[[1]]$index))
  expect_false("survey_year" %in% names(rt[[1]]$index))
  expect_s3_class(ggplot2::ggplot_build(plot(rt)), "ggplot_built")

  mc <- compare_meshes(f$m, mesh_cutoffs = 40, newdata = f$nd,
                       object_crs = 32609)
  expect_true("year" %in% names(mc$index))
  expect_s3_class(ggplot2::ggplot_build(plot(mc, mohn = TRUE)),
                  "ggplot_built")
})

test_that("coord_multiplier is stored and used by the spatial maps", {
  skip_on_cran()
  f <- fit_small()
  cm <- compare_models(f$m, f$m2, newdata = f$nd, object_crs = 32609)
  expect_identical(attr(cm, "coord_multiplier"), 1000)
  # a legacy object without the attribute falls back to km
  attr(cm, "coord_multiplier") <- NULL
  expect_identical(sdmTMBexperiments:::.coord_multiplier(cm), 1000)

  grid <- data.frame(X = c(400, 450), Y = c(5600, 5650), diff = 1, pr_diff = 1)
  p <- suppressWarnings(sdmTMBexperiments:::.spatial_diff_map(
    grid, crs = 32609, coord_multiplier = 1, spatial_response = "pr_mean"
  ))
  expect_equal(sort(p$layers[[length(p$layers)]]$data$X), c(400, 450))
})

test_that("sdmTMB_mesh_cv uses the model xy_cols and catches an NA CRS", {
  skip_on_cran()
  skip_if_not_installed("blockCV")
  d <- sdmTMB::pcod[sdmTMB::pcod$year >= 2013, ]
  names(d)[names(d) == "X"] <- "lon_km"
  names(d)[names(d) == "Y"] <- "lat_km"
  mesh <- sdmTMB::make_mesh(d, c("lon_km", "lat_km"), cutoff = 30)
  m <- sdmTMB::sdmTMB(
    density ~ 0 + as.factor(year), data = d, mesh = mesh, time = "year",
    family = sdmTMB::tweedie(), spatiotemporal = "off"
  )
  # NA CRS from make_mesh() is caught before blockCV, and the default xy_cols
  # come from the mesh (a "X"/"Y" default would fail the column check first)
  expect_error(sdmTMB_mesh_cv(m, mesh_cutoffs = 30), "CRS")
})

test_that("barrier meshes are kept or warned about", {
  fake <- list(spde_barrier = list(I = 1), barrier_scaling = c(1, 0.2),
               barrier_triangles = 1:3)
  expect_warning(
    sdmTMBexperiments:::.warn_barrier_dropped(fake, "the new meshes"),
    "barrier"
  )
  expect_silent(sdmTMBexperiments:::.warn_barrier_dropped(list(), "x"))
  copied <- sdmTMBexperiments:::.copy_barrier(list(mesh = 1), fake)
  expect_identical(copied[names(fake)], fake)
})

test_that("compare_surveys: numeric area vector and non-`year` time", {
  skip_on_cran()
  skip_if_not_installed("concaveman")
  f <- fit_small(time = "survey_year")
  f$d$survey <- ifelse(f$d$X < 450, "A", "B")
  idx <- suppressMessages(
    sdmTMB::get_index_split(f$m, newdata = f$nd, nsplit = 1, silent = TRUE)
  )
  run <- function(area) {
    compare_surveys(
      data = f$d, compiled_index = idx, compiled_model = f$m,
      survey_col = "survey", newdata = f$nd, object_crs = 32609,
      mesh_cutoff = 30, verbose = FALSE, area = area
    )
  }
  s1 <- run(4)
  s2 <- run(rep(4, nrow(f$nd)))
  expect_equal(s2$index$est, s1$index$est)
  expect_false(anyNA(s1$index$year))
  expect_false("survey_year" %in% names(s1$index))
  expect_s3_class(ggplot2::ggplot_build(plot(s1)), "ggplot_built")
  expect_s3_class(suppressWarnings(ggplot2::ggplot_build(plot(s1, type = "scatter"))),
                  "ggplot_built")
})

test_that("variance partitioning only uses link-scale SDs", {
  skip_on_cran()
  f <- fit_small()
  # Tweedie phi is a dispersion parameter, not a link-scale SD
  tab <- plot_variance_partitioning(f$m)$data
  expect_false("phi" %in% tab$term)
  expect_true("sigma_O" %in% tab$term)
  expect_equal(sum(tab$proportion), 1)

  d <- f$d
  d$log_density <- log(d$density + 1)
  d$g <- factor(d$year)
  mg <- sdmTMB::sdmTMB(
    log_density ~ 1 + (1 | g), data = d,
    mesh = sdmTMB::make_mesh(d, c("X", "Y"), cutoff = 30),
    family = gaussian(), spatiotemporal = "off"
  )
  tab_g <- plot_variance_partitioning(mg)$data
  expect_true(all(c("phi", "sigma_O", "sd__(Intercept)") %in% tab_g$term))
  expect_true("Random intercept (g)" %in% tab_g$component)
})

test_that("prediction histogram handles a model with an offset", {
  skip_on_cran()
  d <- sdmTMB::pcod[sdmTMB::pcod$year >= 2013, ]
  d$off <- log(2)
  m <- sdmTMB::sdmTMB(
    density ~ 1, data = d, spatial = "off", family = sdmTMB::tweedie(),
    offset = "off"
  )
  expect_equal(m$offset, rep(log(2), nrow(d)))
  expect_s3_class(plot_prediction_histogram(m, data.frame(est = 1)), "ggplot")
})

test_that("retro peels keep their order with more than ten peels", {
  idx <- data.frame(year = 1:3, est = 1:3, lwr = 1:3, upr = 1:3)
  x <- lapply(1:11, function(i) list(index = idx))
  names(x) <- paste0("peel ", 0:10, ": ", 2030 - 0:10)
  class(x) <- "sdmTMB_retro"
  p <- plot(x)
  expect_identical(levels(p$data$peel), names(x))
})
