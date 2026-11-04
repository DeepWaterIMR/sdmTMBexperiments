# Influence screens, regional split and data-filter scenarios.

test_that("density_share sums to one per year and screens candidates", {
  d <- data.frame(
    year = rep(2000:2001, each = 4),
    cruise = c("a", "a", "b", "c", "a", "b", "b", "b"),
    biomass = c(10, 0, 30, 60, 5, 5, 5, 85),
    swept_area = 1
  )
  hs <- density_share(d, "biomass", top_n = 1, min_share = 0.3)
  expect_equal(as.vector(tapply(hs$share, hs$year, sum)), c(1, 1))
  expect_equal(hs$haul_share, rep(0.25, 8))
  expect_equal(sum(hs$candidate), 3) # 60 (rank 1, >= 0.3), 30 (>= 0.3), 85
  cs <- density_share(d, "biomass", group_col = "cruise")
  expect_equal(nrow(cs), 5)
  b01 <- cs[cs$cruise == "b" & cs$year == 2001, ]
  expect_equal(b01$share, 0.95)
  expect_equal(b01$haul_share, 0.75)
  expect_equal(b01$n_positive, 3L)
  expect_error(density_share(d, "nope"), "no column")
})

test_that("peak_ratio works on a data frame", {
  idx <- data.frame(year = 2000:2004, est = c(10, 11, 20, 12, 10))
  pr <- peak_ratio(idx, year = 2002)
  expect_equal(pr$peak_ratio, 20 / 11.5)
})

fit_small <- function() {
  d <- sdmTMB::pcod
  d$haul <- as.character(seq_len(nrow(d)))
  mesh <- sdmTMB::make_mesh(d, c("X", "Y"), cutoff = 30)
  fit <- sdmTMB::sdmTMB(
    density ~ 1, data = d, mesh = mesh, time = "year",
    family = sdmTMB::tweedie(), spatiotemporal = "iid", spatial = "on"
  )
  nd <- sdmTMB::replicate_df(sdmTMB::qcs_grid, "year", unique(d$year))
  nd$region <- ifelse(nd$Y > stats::median(nd$Y), "North", "South")
  list(fit = fit, nd = nd, data = d)
}

test_that("index_by_region adds up to the plug-in index", {
  skip_on_cran()
  f <- fit_small()
  ri <- index_by_region(f$fit, f$nd, region_col = "region", area = 4)
  expect_s3_class(ri, "sdmTMB_region_index")
  p <- suppressMessages(stats::predict(f$fit, newdata = f$nd, type = "response"))
  total <- tapply(p$est * 4, p$year, sum)
  expect_equal(as.vector(tapply(ri$est, ri$year, sum)), as.vector(total),
               tolerance = 1e-8)
  expect_equal(as.vector(tapply(ri$share, ri$year, sum)), rep(1, length(total)))
  expect_s3_class(plot(ri, type = "share"), "ggplot")
  # data frame of predictions gives the same result
  ri2 <- index_by_region(transform(p, area = 4), region_col = "region",
                         area = "area")
  expect_equal(ri2$est, ri$est)
})

test_that("sdmTMB_leave_out reports haul share and leverage", {
  skip_on_cran()
  f <- fit_small()
  ids <- f$data$haul[order(-f$data$density)][1:2]
  lo <- sdmTMB_leave_out(f$fit, ids = ids, id_col = "haul", newdata = f$nd,
                         area = 4, verbose = FALSE)
  n_year <- table(f$data$year)
  yr <- f$data$year[match(lo$influence$id, f$data$haul)]
  expect_equal(lo$influence$haul_share, as.vector(1 / n_year[as.character(yr)]))
  expect_equal(lo$influence$leverage,
               lo$influence$influence / lo$influence$haul_share)
  expect_s3_class(plot(lo, type = "leverage"), "ggplot")
})

test_that("sdmTMB_data_scenarios baseline reproduces the fit", {
  skip_on_cran()
  f <- fit_small()
  sc <- sdmTMB_data_scenarios(
    f$fit,
    scenarios = list(
      "No 2017" = function(d) d$year != 2017,
      "Capped" = function(d) {
        d$density <- pmin(d$density, stats::quantile(d$density, 0.99))
        d
      },
      "North" = list(newdata = f$nd[f$nd$region == "North", ])
    ),
    newdata = f$nd, area = 4, verbose = FALSE
  )
  expect_s3_class(sc, "sdmTMB_data_scenarios")
  p <- suppressMessages(stats::predict(f$fit, newdata = f$nd, type = "response"))
  base <- sc$index[sc$index$scenario == "Baseline", ]
  expect_equal(base$est, as.vector(tapply(p$est * 4, p$year, sum)),
               tolerance = 1e-4)
  no17 <- sc$index[sc$index$scenario == "No 2017", ]
  expect_true(all(is.na(no17$est[no17$year == 2017])))
  expect_true(no17$removed[no17$year == 2017])
  s <- sc$summary
  expect_equal(s$n_rows[s$scenario == "No 2017"],
               sum(f$data$year != 2017))
  expect_gt(s$n_modified[s$scenario == "Capped"], 0)
  expect_equal(s$grid[s$scenario == "North"], "own")
  pr <- peak_ratio(sc, year = 2011, neighbours = c(2009, 2013))
  expect_equal(nrow(pr), 4)
  expect_s3_class(plot(sc, type = "scaled"), "ggplot")
  expect_error(sdmTMB_data_scenarios(f$fit, list(function(d) TRUE), f$nd),
               "named list")
})

test_that("auto nsplit keeps chunks near 75 000 rows", {
  expect_equal(.auto_nsplit(1000), 1L)
  expect_equal(.auto_nsplit(910e3), 13L)
})
