#' Mohn's rho for a set of index series
#'
#' @description
#' Computes Mohn's rho, the mean relative bias between the terminal-year
#' estimate of each non-reference series (e.g. a retrospective peel or an
#' alternative model) and the reference series estimate in that same year.
#'
#' This is the shared engine used by the plotting methods of
#' [sdmTMB_retro()], [compare_models()] and [compare_meshes()], exposed so it
#' can be used directly on any long-format table of index series.
#'
#' @param data A long-format data frame containing at least the grouping
#'   column, a year column, and an estimate column.
#' @param group_col Character. Name of the column identifying the series (e.g.
#'   `"peel"`, `"model"`, `"cutoff"`).
#' @param reference The value of `group_col` that identifies the reference
#'   series to compare against.
#' @param year_col Character. Name of the year column. Default `"year"`.
#' @param est_col Character. Name of the estimate column. Default `"est"`.
#' @param exclude_crashed Logical. Drop rows whose `type` column equals
#'   `"crashed"` before computing? Default `TRUE`.
#'
#' @details
#' For each non-reference series \eqn{p} the terminal (maximum) year
#' \eqn{T_p} is found, and the relative bias is
#' \deqn{b_p = \frac{\hat{I}_p^{(T_p)} - \hat{I}_{ref}^{(T_p)}}{\hat{I}_{ref}^{(T_p)}}.}
#' Mohn's rho is the mean of these relative biases:
#' \deqn{\rho = \frac{1}{P} \sum_{p=1}^{P} b_p.}
#'
#' @return A single numeric value (the mean relative bias). Returns `NA` if no
#'   valid comparisons can be made.
#'
#' @author Mikko Vihtakari
#' @examples
#' idx <- data.frame(
#'   peel = rep(c("peel 0", "peel 1", "peel 2"), each = 5),
#'   year = rep(2016:2020, 3),
#'   est = c(
#'     10, 11, 12, 13, 14,
#'     10, 11, 12, 13.5, NA,
#'     10, 11, 12.5, NA, NA
#'   )
#' )
#' # peel 1 terminal year is 2019, peel 2 terminal year is 2018:
#' mohns_rho(idx, group_col = "peel", reference = "peel 0")
#' @export
mohns_rho <- function(data, group_col, reference, year_col = "year",
                      est_col = "est", exclude_crashed = TRUE) {
  stopifnot(is.data.frame(data))
  if (!all(c(group_col, year_col, est_col) %in% names(data))) {
    stop("`data` must contain the columns named by `group_col`, `year_col` and `est_col`.")
  }

  if (exclude_crashed && "type" %in% names(data)) {
    data <- data[!data[["type"]] %in% "crashed", , drop = FALSE]
  }

  ref <- data[data[[group_col]] == reference, c(year_col, est_col), drop = FALSE]
  if (nrow(ref) == 0) {
    stop("No rows found for the reference series '", reference, "'.")
  }
  names(ref) <- c(year_col, "ref_est")

  peels <- setdiff(unique(data[[group_col]]), reference)
  if (length(peels) == 0) {
    return(NA_real_)
  }

  rel_bias <- vapply(peels, function(g) {
    sub <- data[data[[group_col]] == g, , drop = FALSE]
    sub <- sub[!is.na(sub[[est_col]]), , drop = FALSE]
    if (nrow(sub) == 0) {
      return(NA_real_)
    }
    ty <- max(sub[[year_col]], na.rm = TRUE)
    est_ty <- sub[[est_col]][sub[[year_col]] == ty]
    ref_ty <- ref[["ref_est"]][ref[[year_col]] == ty]
    if (length(est_ty) == 0 || length(ref_ty) == 0 ||
        is.na(ref_ty[1]) || ref_ty[1] == 0) {
      return(NA_real_)
    }
    (est_ty[1] - ref_ty[1]) / ref_ty[1]
  }, numeric(1))

  mean(rel_bias, na.rm = TRUE)
}
