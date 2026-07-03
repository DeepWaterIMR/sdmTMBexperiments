# Quantile-quantile plot of sdmTMB randomized quantile residuals

Computes randomized quantile residuals for each family component of a
fitted sdmTMB model and draws a Q-Q plot. Delta models are faceted by
component.

## Usage

``` r
plot_residual_qq(fit, type = "mle-mvn", base_size = 11)
```

## Arguments

- fit:

  A fitted
  [`sdmTMB::sdmTMB()`](https://sdmTMB.github.io/sdmTMB/reference/sdmTMB.html)
  model.

- type:

  Character. Residual type passed to
  [`stats::residuals()`](https://rdrr.io/r/stats/residuals.html) (falls
  back to `"mle-eb"` if the requested type fails). Default `"mle-mvn"`.

- base_size:

  Numeric. Base font size. Default `11`.

## Value

A `ggplot` object.

## See also

[`stats::residuals()`](https://rdrr.io/r/stats/residuals.html),
[`sdmTMB::residuals.sdmTMB()`](https://sdmTMB.github.io/sdmTMB/reference/residuals.sdmTMB.html)

## Author

Mikko Vihtakari

## Examples

``` r
# \donttest{
mesh <- sdmTMB::make_mesh(sdmTMB::pcod, c("X", "Y"), cutoff = 20)
m1 <- sdmTMB::sdmTMB(
  density ~ 0 + as.factor(year),
  data = sdmTMB::pcod,
  time = "year",
  mesh = mesh,
  family = sdmTMB::delta_lognormal()
)
# Automatically plots all components of the delta model
plot_residual_qq(m1)

# }
```
