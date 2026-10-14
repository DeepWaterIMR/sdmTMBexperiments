# Model-selection helpers. The pure data-frame parts run everywhere; the
# model-fitting parts are kept small and skipped on CRAN.

test_that("add_aic_weights adds deltas and weights, sorted best first", {
  tab <- data.frame(model = c("a", "b", "c"), AIC = c(1002, 1000, 1010))
  out <- add_aic_weights(tab)

  expect_equal(out$model, c("b", "a", "c"))
  expect_equal(out$deltaAIC, c(0, 2, 10))
  expect_equal(sum(out$AICweight), 1)
  expect_true(out$AICweight[1] > out$AICweight[2])
})

test_that("add_aic_weights keeps incomparable groups apart", {
  tab <- data.frame(
    model = c("a", "b", "c"),
    family = c("tweedie", "tweedie", "Gamma"),
    AIC = c(1002, 1000, 10)
  )
  out <- add_aic_weights(tab, group = "family")

  # The Gamma row has a far lower AIC, but it is fitted to different response
  # data: it must not steal the weight from the tweedie group, and as the only
  # member of its own group it gets no weight at all.
  expect_equal(out$deltaAIC[out$model == "c"], 0)
  expect_true(is.na(out$AICweight[out$model == "c"]))
  expect_equal(sum(out$AICweight[out$family == "tweedie"]), 1)
})

test_that("add_aic_weights returns NA rather than Inf for an all-NA column", {
  tab <- data.frame(model = c("a", "b"), AIC = c(NA_real_, NA_real_))
  out <- add_aic_weights(tab)
  expect_true(all(is.na(out$deltaAIC)))
})

test_that("selection_frame drops rows incomplete for any candidate", {
  d <- data.frame(
    y = 1:5, a = c(1, 2, NA, 4, 5), b = c(1, NA, 3, 4, 5), X = 1:5, Y = 1:5
  )
  cands <- list("with a" = y ~ a, "with b" = y ~ b)
  out <- selection_frame(d, cands, extra = c("X", "Y"))

  expect_equal(nrow(out), 3)
  expect_equal(attr(out, "dropped"), 2)
  expect_setequal(attr(out, "columns"), c("y", "a", "b", "X", "Y"))
})

test_that("selection_frame accepts a bare formula and a default formula", {
  d <- data.frame(y = 1:3, a = c(1, NA, 3))
  expect_equal(nrow(selection_frame(d, y ~ a)), 2)
  expect_equal(
    nrow(selection_frame(d, list("default" = list()), formula = y ~ a)), 2
  )
})

test_that("best_candidate reads the metric column, not the row order", {
  tab <- data.frame(
    model = c("worst", "best", "crashed"),
    AIC = c(1010, 1000, NA),
    comparable = c(TRUE, TRUE, FALSE)
  )
  expect_equal(best_candidate(tab, by = "aic"), "best")
  expect_equal(best_candidate(tab, n = 2, by = "aic"), c("best", "worst"))
  # asking for more than exist returns what there is, not NAs
  expect_length(best_candidate(tab, n = 10, by = "aic"), 2)
})

test_that("best_candidate skips incomparable rows", {
  tab <- data.frame(
    model = c("did not converge", "clean"),
    AIC = c(1, 1000),
    comparable = c(FALSE, TRUE)
  )
  expect_equal(best_candidate(tab, by = "aic"), "clean")
  expect_equal(best_candidate(tab, by = "aic", comparable_only = FALSE),
               "did not converge")
  expect_warning(
    best_candidate(tab[tab$model == "did not converge", ], by = "aic"),
    "comparable"
  )
})

test_that("sdmTMB_cv_summary handles a crashed run", {
  out <- sdmTMB_cv_summary(NULL, label = "boom")
  expect_equal(out$model, "boom")
  expect_true(out$cv_crashed)
  expect_true(is.na(out$cv_loglik))
})

test_that("candidate slugs are collision-safe", {
  # "+ depth" and "depth" normalise to the same string; the hash keeps their
  # cache files apart.
  expect_false(
    sdmTMBexperiments:::.selection_slug("+ depth") ==
      sdmTMBexperiments:::.selection_slug("depth")
  )
  expect_equal(
    sdmTMBexperiments:::.selection_slug("+ depth"),
    sdmTMBexperiments:::.selection_slug("+ depth")
  )
})

test_that("sdmTMB_selection compares candidates on identical records", {
  skip_on_cran()
  d <- sdmTMB::pcod
  set.seed(42)
  d$depth_scaled[sample(nrow(d), 40)] <- NA

  cands <- list(
    "Year only" = density ~ 0 + as.factor(year),
    "+ depth" = density ~ 0 + as.factor(year) + depth_scaled
  )
  sel <- sdmTMB_selection(
    cands, data = d, cutoff = 30, family = sdmTMB::tweedie(), time = "year",
    spatial = "on", spatiotemporal = "off", verbose = FALSE
  )

  expect_s3_class(sel, "sdmTMB_selection")
  # Both candidates lose the 40 rows, including the one that never uses depth.
  expect_equal(unique(sel$table$n), nrow(d) - 40)
  expect_true(all(c("spec", "comparable", "deltaAIC", "AICweight") %in%
                    names(sel$table)))
  # The spec column states what was fitted rather than relying on the label.
  expect_match(sel$table$spec[1], "family = tweedie")
  expect_s3_class(plot(sel), "ggplot")
  expect_equal(best_candidate(sel, by = "aic"), sel$table$model[1])
})

test_that("sdmTMB_selection requires a deliberate family and formula", {
  expect_error(
    sdmTMB_selection(list("a" = y ~ x), data = data.frame(y = 1, x = 1),
                     cutoff = 10),
    "family"
  )
  expect_error(
    sdmTMB_selection(list("a" = list(spatial = "off")),
                     data = data.frame(y = 1, x = 1), cutoff = 10,
                     family = sdmTMB::tweedie()),
    "formula"
  )
})

test_that("sdmTMB_selection caches per candidate and honours `only`", {
  skip_on_cran()
  dir <- withr::local_tempdir()
  cands <- list(
    "Year only" = density ~ 0 + as.factor(year),
    "+ depth" = density ~ 0 + as.factor(year) + depth_scaled
  )
  args <- list(
    cands, data = sdmTMB::pcod, cutoff = 30, family = sdmTMB::tweedie(),
    time = "year", spatial = "on", spatiotemporal = "off",
    cache_dir = dir, verbose = FALSE
  )

  s1 <- do.call(sdmTMB_selection, c(args, list(only = "Year only")))
  expect_length(dir(dir), 1)
  # The un-run candidate is reported as crashed rather than silently dropped.
  expect_true(s1$table$crashed[s1$table$model == "+ depth"])

  s2 <- do.call(sdmTMB_selection, args)
  expect_length(dir(dir), 2)
  expect_false(any(s2$table$crashed))
  # The cached candidate is identical, not refitted to a new value.
  expect_equal(
    s2$table$AIC[s2$table$model == "Year only"],
    s1$table$AIC[s1$table$model == "Year only"]
  )
})

test_that("cross-validated selection reports per-observation log-likelihood", {
  skip_on_cran()
  cands <- list(
    "Year only" = density ~ 0 + as.factor(year),
    "+ depth" = density ~ 0 + as.factor(year) + depth_scaled
  )
  sel <- sdmTMB_selection(
    cands, data = sdmTMB::pcod, cutoff = 30, family = sdmTMB::tweedie(),
    time = "year", spatial = "on", spatiotemporal = "off", cv = 2,
    verbose = FALSE
  )

  expect_true(all(c("folds", "folds_pdhess", "n_heldout", "cv_loglik",
                    "cv_deltaNLL", "cv_RMSE", "cv_MAE") %in% names(sel$table)))
  # Per observation, not summed: the k-fold hold-out covers every row once.
  cvo <- sel$cv[["Year only"]]
  expect_equal(
    sel$table$cv_loglik[sel$table$model == "Year only"],
    cvo$sum_loglik / nrow(sdmTMB::pcod)
  )
  expect_equal(min(sel$table$cv_deltaNLL, na.rm = TRUE), 0)
  # Sorted by the cross-validated metric once CV is present.
  expect_equal(sel$table$cv_deltaNLL, sort(sel$table$cv_deltaNLL))
})

test_that("a CV run reuses the whole-frame fits an AIC ladder already cached", {
  skip_on_cran()
  dir <- withr::local_tempdir()
  cands <- list("Year only" = density ~ 0 + as.factor(year))
  args <- list(
    cands, data = sdmTMB::pcod, cutoff = 30, family = sdmTMB::tweedie(),
    time = "year", spatial = "on", spatiotemporal = "off",
    cache_dir = dir, cache_prefix = "stage", verbose = FALSE
  )

  s1 <- do.call(sdmTMB_selection, args)
  expect_setequal(basename(dir(dir)), paste0("stage-year-only-", substr(rlang::hash("Year only"), 1, 6), ".rds"))

  s2 <- do.call(sdmTMB_selection, c(args, list(cv = 2)))
  # A second file appeared for the folds, and the fit was not recomputed.
  expect_length(dir(dir), 2)
  expect_equal(s2$table$AIC, s1$table$AIC)
  expect_false(is.na(s2$table$cv_loglik))
})

test_that("a call that would compute nothing is refused", {
  expect_error(
    sdmTMB_selection(list("a" = y ~ x), data = data.frame(y = 1, x = 1),
                     cutoff = 10, family = sdmTMB::tweedie(), fit_full = FALSE),
    "computes nothing"
  )
})
