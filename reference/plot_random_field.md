# Map spatial or spatiotemporal random fields

Maps the spatial (`omega`) or spatiotemporal (`epsilon`) random field
columns returned by `predict(fit, newdata = ...)` on a
[`ggOceanMaps::basemap()`](https://mikkovihtakari.github.io/ggOceanMaps/reference/basemap.html),
using a diverging colour scale. Handles delta models (multiple field
columns) by faceting.

## Usage

``` r
plot_random_field(
  pred,
  crs,
  field = c("omega", "epsilon"),
  time_col = "year",
  xy_cols = c("X", "Y"),
  coord_multiplier = 1000,
  base_size = 11
)
```

## Arguments

- pred:

  A prediction data frame from `predict(fit, newdata = ...)`.

- crs:

  Coordinate reference system (projected, in metres).

- field:

  Character. `"omega"` (spatial, default) or `"epsilon"`
  (spatiotemporal).

- time_col:

  Character. Time column for spatiotemporal fields. Default `"year"`.

- xy_cols:

  Character vector of the coordinate columns. Default `c("X", "Y")`.

- coord_multiplier:

  Numeric factor to convert coordinates to CRS units. Default `1000`.

- base_size:

  Numeric. Base font size. Default `11`.

## Value

A `ggplot` object.

## See also

[`ggOceanMaps::basemap()`](https://mikkovihtakari.github.io/ggOceanMaps/reference/basemap.html)

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
nd <- sdmTMB::replicate_df(sdmTMB::qcs_grid, "year", unique(sdmTMB::pcod$year))
pred <- predict(m, newdata = nd)
plot_random_field(pred, crs = 32609, field = "omega")

plot_random_field(pred, crs = 32609, field = "epsilon")

# }
```
