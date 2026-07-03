# Variance partitioning of an sdmTMB model

Partitions the link-scale variance of a fitted sdmTMB model among its
random components (spatial field `sigma_O`, spatiotemporal field
`sigma_E`, smooth terms, and observation error `phi`) using
[`sdmTMB::tidy()`](https://generics.r-lib.org/reference/tidy.html), and
plots the proportion of variance explained by each.

## Usage

``` r
plot_variance_partitioning(fit, base_size = 11)
```

## Arguments

- fit:

  A fitted
  [`sdmTMB::sdmTMB()`](https://sdmTMB.github.io/sdmTMB/reference/sdmTMB.html)
  model.

- base_size:

  Numeric. Base font size. Default `11`.

## Value

A `ggplot` object.

## See also

[`sdmTMB::tidy()`](https://generics.r-lib.org/reference/tidy.html)

## Author

Mikko Vihtakari

## Examples

``` r
# \donttest{
mesh <- sdmTMB::make_mesh(sdmTMB::pcod, c("X", "Y"), cutoff = 20)
m <- sdmTMB::sdmTMB(
  density ~ 0 + as.factor(year), data = sdmTMB::pcod, time = "year",
  mesh = mesh, family = sdmTMB::tweedie()
)
plot_variance_partitioning(m)

# }
```
