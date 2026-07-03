# Plot mesh cross-validation results

Plot mesh cross-validation results

## Usage

``` r
# S3 method for class 'sdmTMB_mesh_cv'
plot(x, metric = "deltaNLL", base_size = 11, ...)
```

## Arguments

- x:

  An object of class `sdmTMB_mesh_cv` from
  [`sdmTMB_mesh_cv()`](https://deepwaterimr.github.io/sdmTMBexperiments/reference/sdmTMB_mesh_cv.md).

- metric:

  Character. Which metric to plot: `"deltaNLL"` (default),
  `"sum_loglik"`, or `"deltaAIC"`.

- base_size:

  Numeric. Base font size. Default `11`.

- ...:

  Currently ignored.

## Value

A `ggplot` object.

## See also

[`sdmTMB_mesh_cv()`](https://deepwaterimr.github.io/sdmTMBexperiments/reference/sdmTMB_mesh_cv.md)

## Author

Mikko Vihtakari

## Examples

``` r
# \donttest{
# Requires the 'blockCV' package.
mesh <- sdmTMB::make_mesh(sdmTMB::pcod, c("X", "Y"), cutoff = 20)
fit <- sdmTMB::sdmTMB(
  data = sdmTMB::pcod, formula = density ~ 0 + as.factor(year),
  time = "year", mesh = mesh, family = sdmTMB::tweedie(link = "log")
)
cv <- sdmTMB_mesh_cv(fit, mesh_cutoffs = c(15, 30), k = 3)
#> Running fits with `future.apply()`.
#> Set a parallel `future::plan()` to use parallel processing.
#> Running fits with `future.apply()`.
#> Set a parallel `future::plan()` to use parallel processing.
#> ℹ `ln_tau_O` is an internal parameter affecting `sigma_O`
#> ℹ `sigma_O` is the spatial standard deviation
#> ℹ `ln_tau_E` is an internal parameter affecting `sigma_E`
#> ℹ `sigma_E` is the spatiotemporal standard deviation
#> ℹ `ln_kappa` is an internal parameter affecting `range`
#> ℹ `range` is the distance at which data are effectively independent
#> ℹ `ln_tau_O` is an internal parameter affecting `sigma_O`
#> ℹ `sigma_O` is the spatial standard deviation
#> ℹ `ln_tau_E` is an internal parameter affecting `sigma_E`
#> ℹ `sigma_E` is the spatiotemporal standard deviation
#> ℹ `ln_kappa` is an internal parameter affecting `range`
#> ℹ `range` is the distance at which data are effectively independent
plot(cv)

plot(cv, metric = "deltaAIC")

# }
```
