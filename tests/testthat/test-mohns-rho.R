test_that("mohns_rho computes terminal-year relative bias", {
  idx <- data.frame(
    peel = rep(c("peel 0", "peel 1", "peel 2"), each = 5),
    year = rep(2016:2020, 3),
    est = c(
      10, 11, 12, 13, 14,       # reference
      10, 11, 12, 13.5, NA,     # peel 1 terminal year 2019: (13.5 - 13)/13
      10, 11, 12.5, NA, NA      # peel 2 terminal year 2018: (12.5 - 12)/12
    )
  )
  expected <- mean(c((13.5 - 13) / 13, (12.5 - 12) / 12))
  expect_equal(mohns_rho(idx, "peel", "peel 0"), expected)
})

test_that("mohns_rho drops crashed rows and handles missing reference", {
  idx <- data.frame(
    model = c("ref", "ref", "a", "a"),
    year = c(2019, 2020, 2019, 2020),
    est = c(10, 12, 11, 13),
    type = c("index", "index", "index", "crashed")
  )
  # 'a' terminal usable year is 2019 after dropping the crashed 2020 row
  expect_equal(mohns_rho(idx, "model", "ref"), (11 - 10) / 10)
  expect_error(mohns_rho(idx, "model", "does-not-exist"))
})

test_that("mohns_rho returns NA when there are no non-reference series", {
  idx <- data.frame(model = "ref", year = 2020, est = 10)
  expect_true(is.na(mohns_rho(idx, "model", "ref")))
})
