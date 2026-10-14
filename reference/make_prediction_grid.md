# Build a regular prediction grid over a region

Creates a regular grid of centre points covering an `sf` `region`, at a
given spatial resolution. Optionally filters the grid by depth using a
user-supplied depth function. Coordinates are returned in the same units
as the model (divided by `coord_multiplier`).

## Usage

``` r
make_prediction_grid(
  region,
  resolution,
  crs = NULL,
  coord_multiplier = 1000,
  max_depth = NULL,
  depth_fun = NULL,
  bathy_style = "raster_continuous"
)
```

## Arguments

- region:

  An `sf` polygon defining the prediction area (e.g. from
  [`make_survey_prediction_region()`](https://deepwaterimr.github.io/sdmTMBexperiments/reference/make_survey_prediction_region.md)).

- resolution:

  Numeric. Grid cell side length, in the model coordinate units (e.g.
  km). Internally multiplied by `coord_multiplier` to match the CRS
  units.

- crs:

  Coordinate reference system. If `NULL` (default), taken from `region`.

- coord_multiplier:

  Numeric factor to convert model units to CRS units. Default `1000`.

- max_depth:

  Optional numeric. If supplied, grid cells with depth outside
  `c(1, max_depth)` are dropped. Turns on depth extraction (see
  `depth_fun`/`bathy_style`).

- depth_fun:

  Optional function taking an `sf` points object and returning a numeric
  vector of (positive) depths. Only used when `max_depth` is set. If
  `NULL` (default) while `max_depth` is set, depth is extracted
  automatically via
  [`ggOceanMaps::get_depth()`](https://mikkovihtakari.github.io/ggOceanMaps/reference/get_depth.html)
  using `bathy_style` — supply your own `depth_fun` to use a different
  bathymetry source (e.g. a specific GEBCO file via
  `bathy.style = "raster_user"` and
  `options(ggOceanMaps.userpath = ...)`, or a local
  raster/interpolation).

- bathy_style:

  Character. `bathy.style` passed to
  [`ggOceanMaps::get_depth()`](https://mikkovihtakari.github.io/ggOceanMaps/reference/get_depth.html)
  when `depth_fun` is `NULL`. Default `"raster_continuous"` (ETOPO,
  bundled with ggOceanMaps — no extra download path needed). Ignored
  when `depth_fun` is supplied.

## Value

A data frame (class `sdmTMB_prediction_grid`, so
[`plot.sdmTMB_prediction_grid()`](https://deepwaterimr.github.io/sdmTMBexperiments/reference/plot.sdmTMB_prediction_grid.md)
can be used on it directly) with columns `X`, `Y` (in model units) and,
when depth filtering is applied, a `depth` column. Carries `crs`,
`coord_multiplier` and `resolution` attributes.

## See also

[`make_survey_prediction_region()`](https://deepwaterimr.github.io/sdmTMBexperiments/reference/make_survey_prediction_region.md),
[`plot.sdmTMB_prediction_grid()`](https://deepwaterimr.github.io/sdmTMBexperiments/reference/plot.sdmTMB_prediction_grid.md)

## Author

Mikko Vihtakari

## Examples

``` r
# \donttest{
data(sebastes)
eggan <- subset(sebastes, cruiseseries == "EggaN")
region <- make_survey_prediction_region(eggan, crs = 32633, concavity = 5)

# max_depth turns on depth extraction, via ggOceanMaps::get_depth() by
# default (bathy_style controls the bathymetry source); cells outside
# c(1, max_depth) are dropped. plot() then colours by depth automatically.
grid <- make_prediction_grid(region, resolution = 20, max_depth = 1000)
#> Cannot find files: /tmp/RtmpRRVDqh/dd_rbathy_cont.rda. Do you want
#> download them now?
range(grid$depth)
#> [1]   2.007292 975.687500
plot(grid)

# }
```
