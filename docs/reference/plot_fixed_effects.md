# Coefficient plot of sdmTMB fixed effects

A tidy coefficient plot of the fixed-effect estimates and confidence
intervals from
[`sdmTMB::tidy()`](https://generics.r-lib.org/reference/tidy.html). This
is the generic equivalent of a conditional-effects figure: it summarises
the fitted parameters rather than predicting over covariate ranges.

## Usage

``` r
plot_fixed_effects(fit, base_size = 11)
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
  density ~ 0 + as.factor(year) + depth_scaled, data = sdmTMB::pcod,
  time = "year", mesh = mesh, family = sdmTMB::tweedie()
)
plot_fixed_effects(m)

# }
```
