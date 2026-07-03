# Build a concave-hull prediction region from survey positions

Creates an `sf` polygon describing the spatial footprint of a set of
sampling positions, using a concave hull
([`concaveman::concaveman()`](https://joelgombin.github.io/concaveman/reference/concaveman.html)).
This is used to restrict a prediction grid to the area a survey actually
covers, rather than the full model domain.

## Usage

``` r
make_survey_prediction_region(
  data,
  crs,
  xy_cols = c("X", "Y"),
  coord_multiplier = 1000,
  concavity = 5,
  buffer = 1
)
```

## Arguments

- data:

  A data frame with coordinate columns (see `xy_cols`) in the same units
  as the model (typically km).

- crs:

  Coordinate reference system of the projected coordinates.

- xy_cols:

  Character vector of length two naming the coordinate columns. Default
  `c("X", "Y")`.

- coord_multiplier:

  Numeric factor to convert `xy_cols` to the CRS units (e.g. `1000` to
  convert km to m). Default `1000`.

- concavity:

  Numeric. Concavity parameter passed to
  [`concaveman::concaveman()`](https://joelgombin.github.io/concaveman/reference/concaveman.html).
  Larger values give looser (more convex) hulls. Default `5`.

- buffer:

  Numeric. Buffer (in CRS units) applied to the hull to avoid clipping
  the outermost stations. Default `1`.

## Value

An `sf` polygon (single feature) in the given `crs`.

## See also

[`make_prediction_grid()`](https://deepwaterimr.github.io/sdmTMBexperiments/reference/make_prediction_grid.md),
[`compare_surveys()`](https://deepwaterimr.github.io/sdmTMBexperiments/reference/compare_surveys.md)

## Author

Mikko Vihtakari

## Examples

``` r
# \donttest{
data(sebastes)
eggan <- subset(sebastes, cruiseseries == "EggaN")
region <- make_survey_prediction_region(eggan, crs = 32633, concavity = 5)
ggOceanMaps::qmap(region, fill = I(NA))

# }
```
