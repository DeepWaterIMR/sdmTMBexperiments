# Plot a prediction grid on a map

Draws the points of a
[`make_prediction_grid()`](https://deepwaterimr.github.io/sdmTMBexperiments/reference/make_prediction_grid.md)
grid as filled squares on a
[`ggOceanMaps::basemap()`](https://mikkovihtakari.github.io/ggOceanMaps/reference/basemap.html),
approximating the actual grid cells. Optionally colours the squares by a
column (`depth` by default, when present).

## Usage

``` r
# S3 method for class 'sdmTMB_prediction_grid'
plot(
  x,
  value = "depth",
  crs = NULL,
  xy_cols = c("X", "Y"),
  coord_multiplier = NULL,
  point_size = NULL,
  palette = "turbo",
  color = "red",
  base_size = 11,
  ...
)
```

## Arguments

- x:

  A data frame from
  [`make_prediction_grid()`](https://deepwaterimr.github.io/sdmTMBexperiments/reference/make_prediction_grid.md)
  (class `sdmTMB_prediction_grid`).

- value:

  Character. Column in `x` used to colour the points, e.g. `"depth"`
  (the default). If `NULL`, or not a column of `x`, points are drawn in
  a single `color`.

- crs:

  Coordinate reference system. If `NULL` (default), taken from the `crs`
  attribute set by
  [`make_prediction_grid()`](https://deepwaterimr.github.io/sdmTMBexperiments/reference/make_prediction_grid.md).

- xy_cols:

  Character vector of the coordinate columns. Default `c("X", "Y")`.

- coord_multiplier:

  Numeric factor to convert coordinates to CRS units. If `NULL`
  (default), taken from the `coord_multiplier` attribute set by
  [`make_prediction_grid()`](https://deepwaterimr.github.io/sdmTMBexperiments/reference/make_prediction_grid.md)
  (falling back to `1000`).

- point_size:

  Numeric size of the grid-cell squares. If `NULL` (default), scaled
  from the `resolution` attribute set by
  [`make_prediction_grid()`](https://deepwaterimr.github.io/sdmTMBexperiments/reference/make_prediction_grid.md)
  (`0.08 * resolution`, falling back to `1` if unavailable) so squares
  roughly approximate the actual cell size.

- palette:

  Character. `viridis` palette used when colouring by `value`, passed to
  `option` in
  [`ggplot2::scale_color_viridis_c()`](https://ggplot2.tidyverse.org/reference/scale_viridis.html).
  Default `"turbo"`.

- color:

  Character. Point colour used when not colouring by `value`. Default
  `"red"`.

- base_size:

  Numeric. Base font size. Default `11`.

- ...:

  Currently ignored.

## Value

A `ggplot` object.

## See also

[`make_prediction_grid()`](https://deepwaterimr.github.io/sdmTMBexperiments/reference/make_prediction_grid.md),
[`ggOceanMaps::basemap()`](https://mikkovihtakari.github.io/ggOceanMaps/reference/basemap.html)

## Author

Mikko Vihtakari

## Examples

``` r
# \donttest{
data(sebastes)
eggan <- subset(sebastes, cruiseseries == "EggaN")
region <- make_survey_prediction_region(eggan, crs = 32633, concavity = 5)
grid <- make_prediction_grid(region, resolution = 20, max_depth = 1000)
plot(grid)

plot(grid, palette = "viridis")

# }
```
