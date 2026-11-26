test_that("absolute influence does not cancel and uses all years", {
  info <- tibble::tibble(
    id = c("long", "short"),
    id_years = list(2001:2004, 2001:2002),
    haul_share = c(0.5, 0.5),
    haul_share_all = c(0.5, 0.1)
  )
  # "long" moves the index up and down by the same factor; "short" lowers two years.
  index_out <- tibble::tibble(
    id = rep(c("long", "short"), each = 4),
    year = rep(2001:2004, 2),
    ratio = c(1.5, 1 / 1.5, 1.5, 1 / 1.5, 0.8, 0.8, 1, 1)
  )
  signed <- .leave_out_influence(info, index_out, "signed")
  expect_equal(signed$influence[signed$id == "long"], 0, tolerance = 1e-12)
  expect_equal(signed$influence[signed$id == "short"], 0.2)
  expect_identical(signed$id[1], "short")

  abs_inf <- .leave_out_influence(info, index_out, "absolute")
  expect_equal(abs_inf$influence[abs_inf$id == "long"], 0.5)
  expect_equal(abs_inf$influence[abs_inf$id == "short"], exp(log(1.25) / 2) - 1)
  expect_identical(abs_inf$id[1], "long")
  expect_equal(abs_inf$leverage[abs_inf$id == "long"], 0.5 / 0.5)
  expect_equal(abs_inf$leverage[abs_inf$id == "short"], (exp(log(1.25) / 2) - 1) / 0.1)
})
