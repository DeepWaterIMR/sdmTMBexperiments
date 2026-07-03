# Compare sdmTMB models

Compares a set of fitted sdmTMB models by calculating survey indices,
per-grid-cell prediction differences relative to a reference model, and
model sanity checks. The result can be plotted with
[`plot.sdmTMB_model_comparison()`](https://deepwaterimr.github.io/sdmTMBexperiments/reference/plot.sdmTMB_model_comparison.md).

## Usage

``` r
compare_models(
  ...,
  newdata,
  reference_model = 1,
  object_crs = NULL,
  bias_correct = FALSE,
  level = 0.95,
  area = 1,
  silent = TRUE,
  n_workers = 1,
  nsplit = 3,
  future_seed = TRUE
)
```

## Arguments

- ...:

  A set of fitted
  [`sdmTMB::sdmTMB()`](https://sdmTMB.github.io/sdmTMB/reference/sdmTMB.html)
  models to compare, either as individual arguments or as a single
  (optionally named) list. List names are used as model names; otherwise
  default names are assigned.

- newdata:

  A data frame for predictions, with the same predictor columns as the
  fitted data and a time column matching the fitted data.

- reference_model:

  Integer. Index of the model to use as the reference for comparison.
  Default `1`.

- object_crs:

  Coordinate reference system for the model data. If `NULL` (default),
  extracted from the first model's mesh when available.

- bias_correct:

  Logical. Apply bias correction via
  [`TMB::sdreport()`](https://rdrr.io/pkg/TMB/man/sdreport.html)?
  Default `FALSE`.

- level:

  Numeric. Confidence level for index intervals. Default `0.95`.

- area:

  Grid cell area for area-weighted index calculation. Passed to
  [`sdmTMB::get_index_split()`](https://sdmTMB.github.io/sdmTMB/reference/get_index.html).

- silent:

  Logical. Suppress model output? Default `TRUE`.

- n_workers:

  Integer. Number of parallel workers. Default `1`.

- nsplit:

  Integer. Number of splits for
  [`sdmTMB::get_index_split()`](https://sdmTMB.github.io/sdmTMB/reference/get_index.html).

- future_seed:

  Logical or integer. Future-compatible random seed for parallel
  processing. See
  [`future.apply::future_lapply()`](https://future.apply.futureverse.org/reference/future_lapply.html).

## Value

An object of class `sdmTMB_model_comparison`, a list with elements
`sanity`, `nll`, `index` and `grid` (a list of per-cell prediction-
difference data frames). Carries `crs`, `reference_model` and
`model_names` attributes.

## See also

[`sdmTMB::sdmTMB()`](https://sdmTMB.github.io/sdmTMB/reference/sdmTMB.html),
[`sdmTMB::get_index_split()`](https://sdmTMB.github.io/sdmTMB/reference/get_index.html),
[`plot.sdmTMB_model_comparison()`](https://deepwaterimr.github.io/sdmTMBexperiments/reference/plot.sdmTMB_model_comparison.md)

## Author

Mikko Vihtakari

## Examples

``` r
# \donttest{
mesh <- sdmTMB::make_mesh(sdmTMB::pcod, c("X", "Y"), cutoff = 20)
m1 <- sdmTMB::sdmTMB(
  data = sdmTMB::pcod, formula = density ~ 0 + as.factor(year),
  time = "year", mesh = mesh, family = sdmTMB::tweedie(link = "log")
)
m2 <- sdmTMB::sdmTMB(
  data = sdmTMB::pcod, formula = density ~ 0 + as.factor(year) + depth_scaled,
  time = "year", mesh = mesh, family = sdmTMB::tweedie(link = "log")
)
nd <- sdmTMB::replicate_df(sdmTMB::qcs_grid, "year", unique(sdmTMB::pcod$year))
x <- compare_models(m1, m2, newdata = nd, object_crs = 32609)
#> ℹ `ln_tau_O` is an internal parameter affecting `sigma_O`
#> ℹ `sigma_O` is the spatial standard deviation
#> ℹ `ln_tau_E` is an internal parameter affecting `sigma_E`
#> ℹ `sigma_E` is the spatiotemporal standard deviation
#> ℹ `ln_kappa` is an internal parameter affecting `range`
#> ℹ `range` is the distance at which data are effectively independent
plot(x)

plot(x, type = "spatial")

# }
```
