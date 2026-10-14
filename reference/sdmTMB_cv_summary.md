# Summarise an sdmTMB cross-validation on a per-observation scale

Turns an
[`sdmTMB::sdmTMB_cv()`](https://sdmTMB.github.io/sdmTMB/reference/sdmTMB_cv.html)
object into a one-row summary whose log-likelihood is expressed **per
held-out observation**, together with the fold-level diagnostics needed
to tell a clean comparison from a fragile one.

## Usage

``` r
sdmTMB_cv_summary(x, label = NA_character_, response = NULL)
```

## Arguments

- x:

  An object of class `sdmTMB_cv` from
  [`sdmTMB::sdmTMB_cv()`](https://sdmTMB.github.io/sdmTMB/reference/sdmTMB_cv.html),
  or a `try-error`/`NULL` from a crashed run.

- label:

  Optional character label carried into the `model` column.

- response:

  Name of the response column, used for `cv_RMSE`/`cv_MAE`. If `NULL`
  (default), taken from the left-hand side of the fitted formula.

## Value

A one-row tibble with `model`, `folds`, `folds_pdhess`, `n_heldout`,
`cv_loglik` (per held-out observation; higher is better), `cv_RMSE`,
`cv_MAE` and `cv_crashed`.

## Details

A summed hold-out log-likelihood is not comparable between candidates
that held out different numbers of observations. That happens more
easily than it looks: candidates fitted to different complete-case
subsets (see
[`selection_frame()`](https://deepwaterimr.github.io/sdmTMBexperiments/reference/selection_frame.md))
hold out different numbers of rows, and a candidate that sums fewer
terms scores *higher*, which inverts the ranking exactly where the
comparison is least reliable. Dividing by the number of contributing
observations removes the artefact; `n_heldout` is reported alongside so
a row assembled from a different number of points is visible as such.

`folds_pdhess` counts the folds whose Hessian was positive definite. A
fold with a non-positive-definite Hessian still yields point
predictions, so it contributes to all three criteria while signalling
that its optimum is not trustworthy — the count has to be shown or the
reader cannot see it.

## See also

[`sdmTMB::sdmTMB_cv()`](https://sdmTMB.github.io/sdmTMB/reference/sdmTMB_cv.html),
[`sdmTMB_selection()`](https://deepwaterimr.github.io/sdmTMBexperiments/reference/sdmTMB_selection.md)

## Author

Mikko Vihtakari

## Examples

``` r
# \donttest{
mesh <- sdmTMB::make_mesh(sdmTMB::pcod, c("X", "Y"), cutoff = 25)
cv <- sdmTMB::sdmTMB_cv(
  density ~ 0 + as.factor(year), data = sdmTMB::pcod, mesh = mesh,
  family = sdmTMB::tweedie(), k_folds = 2
)
#> Running fits with `future.apply()`.
#> Set a parallel `future::plan()` to use parallel processing.
sdmTMB_cv_summary(cv, label = "Year only")
#> # A tibble: 1 × 8
#>   model     folds folds_pdhess n_heldout cv_loglik cv_RMSE cv_MAE cv_crashed
#>   <chr>     <int>        <int>     <int>     <dbl>   <dbl>  <dbl> <lgl>     
#> 1 Year only     2            2      2143     -3.20    198.   52.6 FALSE     
# }
```
