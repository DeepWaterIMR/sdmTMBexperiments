# Conditional-effects tests. Skipped on CRAN (fit small models on `sebastes`).

ce_data <- function() {
  d <- subset(sebastes, year >= 2021 & cruiseseries %in% c("EcoS", "EggaN"))
  d$geartype <- factor(d$geartype)
  d$fyear <- factor(d$year)
  d
}

test_that("conditional_effects handles a delta model with a smooth and factors", {
  skip_on_cran()
  d <- ce_data()
  mesh <- sdmTMB::make_mesh(d, c("X", "Y"), cutoff = 80)
  m <- sdmTMB::sdmTMB(
    density ~ s(depth, k = 5) + geartype + as.factor(year),
    data = d, mesh = mesh, time = "year", spatiotemporal = "off",
    family = sdmTMB::delta_gamma()
  )
  eff <- conditional_effects(m, labels = c(depth = "Depth (m)"), n = 30)
  expect_s3_class(eff, "sdmTMB_conditional_effects")
  expect_setequal(unique(eff$term), c("depth", "geartype", "year"))
  # Peak term first, then formula order
  expect_identical(unique(eff$term)[1], "depth")
  expect_identical(eff$label[eff$term == "depth"][1], "Depth (m)")
  expect_identical(unique(eff$type[eff$term == "year"]), "factor")
  expect_identical(sum(eff$term == "year"), length(unique(d$year)))
  expect_identical(sum(eff$term == "depth"), 30L)
  expect_true(all(eff$lwr <= eff$est & eff$est <= eff$upr))
  expect_true(all(eff$est > 0))

  refs <- attr(eff, "ref")
  expect_identical(refs$source[refs$term == "depth"], "peak")
  expect_identical(refs$source[refs$term == "year"], "last")
  expect_identical(refs$value[refs$term == "year"], "2025")
  expect_identical(refs$value[refs$term == "geartype"], .mode_value(d$geartype))
  # The depth reference is the peak of the depth effect
  dep <- eff[eff$term == "depth", ]
  expect_equal(as.numeric(refs$value[refs$term == "depth"]),
               dep$xnum[which.max(dep$est)])

  # The estimate at the reference levels is the same in every panel
  at_ref <- vapply(c("geartype", "year"), function(v) {
    eff$est[eff$term == v & eff$x == refs$value[refs$term == v]]
  }, numeric(1))
  expect_equal(unname(at_ref), rep(max(dep$est), 2), tolerance = 1e-6)

  # User references override the defaults, including the peak search
  e2 <- conditional_effects(m, ref = list(depth = 500, year = 2022, geartype = "Cod"),
                            se_fit = FALSE, n = 10)
  r2 <- attr(e2, "ref")
  expect_true(all(r2$source == "user"))
  expect_true(all(is.na(e2$lwr)))
  expect_match(effects_reference_text(e2), "geartype Cod")

  txt <- effects_reference_text(eff)
  expect_match(txt, "Depth \\(m\\) [0-9]+ \\(at the peak of its effect\\)")
  expect_match(txt, "year 2025 \\(the last level\\)")
  expect_match(txt, "the most common level")

  # Several models: rows, model column and per-model references in the text
  both <- conditional_effects(list(A = m, B = m), se_fit = FALSE, n = 10)
  expect_identical(levels(both$model), c("A", "B"))
  expect_s3_class(plot(both, fit = m), "ggplot")
  expect_s3_class(plot(eff, fit = m, y_lab = "Density"), "ggplot")
  expect_output(print(eff), "References")
})

test_that("conditional_effects handles a non-delta model, a time factor and discrete numerics", {
  skip_on_cran()
  d <- ce_data()
  mesh <- sdmTMB::make_mesh(d, c("X", "Y"), cutoff = 80)
  m <- sdmTMB::sdmTMB(
    density ~ log(depth) + I(log(depth)^2) + fyear + month,
    data = d, mesh = mesh, family = sdmTMB::tweedie()
  )
  eff <- conditional_effects(m, se_fit = TRUE, n = 20, peak = character(0))
  expect_setequal(unique(eff$term), c("depth", "fyear", "month"))
  refs <- attr(eff, "ref")
  expect_identical(refs$source[refs$term == "depth"], "median")
  # Month is discrete: the most sampled month
  expect_identical(refs$value[refs$term == "month"], .mode_value(d$month))
  expect_identical(refs$source[refs$term == "month"], "mode")
  expect_true(all(eff$lwr <= eff$est & eff$est <= eff$upr))

  # Tweedie (log link): exp() of the link prediction
  nd <- data.frame(depth = 400, fyear = factor("2024", levels(d$fyear)),
                   month = as.integer(.mode_value(d$month)))
  p <- predict(m, newdata = nd, re_form = NA, offset = 0)
  e400 <- conditional_effects(m, ref = list(depth = 400, fyear = "2024"),
                              se_fit = FALSE, n = 5)
  expect_equal(e400$est[e400$term == "fyear" & e400$x == "2024"], exp(p$est),
               tolerance = 1e-8)
  expect_s3_class(plot(eff, data = d, response = "density"), "ggplot")
})

test_that("conditional_effects validates its input", {
  expect_error(conditional_effects(lm(1 ~ 1)), "fitted sdmTMB")
  expect_error(effects_reference_text(data.frame()), "sdmTMB_conditional_effects")
})
