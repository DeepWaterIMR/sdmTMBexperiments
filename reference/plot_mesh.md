# Plot an sdmTMB mesh on a map

Draws a
[`sdmTMB::make_mesh()`](https://sdmTMB.github.io/sdmTMB/reference/make_mesh.html)
mesh over a
[`ggOceanMaps::basemap()`](https://mikkovihtakari.github.io/ggOceanMaps/reference/basemap.html),
optionally overlaying the sampling positions as red points. When a
barrier mesh is present (e.g. from `sdmTMBextra::add_barrier_mesh()`,
from the GitHub-only
[sdmTMBextra](https://github.com/pbs-assess/sdmTMBextra) package), the
barrier ("land") triangles are marked with an `X`.

## Usage

``` r
plot_mesh(
  mesh,
  crs,
  data = NULL,
  value = NULL,
  zero_col = NULL,
  zero_size = 0.25,
  zero_alpha = 0.1,
  land_col = NULL,
  lon_interval = NULL,
  lat_interval = NULL,
  utm_axes = FALSE,
  xy_cols = c("X", "Y"),
  coord_multiplier = 1000,
  base_size = 11
)
```

## Arguments

- mesh:

  An sdmTMB mesh object (from
  [`sdmTMB::make_mesh()`](https://sdmTMB.github.io/sdmTMB/reference/make_mesh.html),
  optionally with a barrier mesh added).

- crs:

  Coordinate reference system (projected, in metres) used for the
  basemap.

- data:

  Optional data frame of sampling positions with coordinate columns (see
  `xy_cols`), plotted as red points.

- value:

  Optional character naming a column in `data` used to scale the point
  sizes. Note that
  [`ggplot2::scale_size_area()`](https://ggplot2.tidyverse.org/reference/scale_size.html)
  maps a zero to zero area, so stations with no catch become invisible;
  see `zero_col`.

- zero_col:

  Optional colour for stations where `value` is zero, drawn as small
  crosses beneath the sized points. `NULL` (default) omits them, which
  preserves the behaviour of earlier versions. Zeros usually outnumber
  the positive stations by an order of magnitude, so they are drawn
  small and faint (see `zero_size` and `zero_alpha`) to avoid burying
  the response.

- zero_size, zero_alpha:

  Size and alpha of the `zero_col` crosses.

- land_col:

  Optional land fill passed to
  [`ggOceanMaps::basemap()`](https://mikkovihtakari.github.io/ggOceanMaps/reference/basemap.html).
  `NULL` (default) uses the basemap default.

- lon_interval, lat_interval:

  Optional graticule intervals in degrees, passed to
  [`ggOceanMaps::basemap()`](https://mikkovihtakari.github.io/ggOceanMaps/reference/basemap.html).
  `NULL` (default) lets basemap decide.

- utm_axes:

  Logical. If `TRUE`, label the axes in projected kilometres (the units
  the model actually uses) rather than in degrees. Default `FALSE`,
  which preserves the behaviour of earlier versions.

- xy_cols:

  Character vector of the coordinate columns in `data`. Default
  `c("X", "Y")`.

- coord_multiplier:

  Numeric factor to convert model coordinates to CRS units. Default
  `1000`.

- base_size:

  Numeric. Base font size. Default `11`.

## Value

A `ggplot` object.

## See also

[`sdmTMB::make_mesh()`](https://sdmTMB.github.io/sdmTMB/reference/make_mesh.html),
[`ggOceanMaps::basemap()`](https://mikkovihtakari.github.io/ggOceanMaps/reference/basemap.html)

## Author

Mikko Vihtakari

## Examples

``` r
# \donttest{
mesh <- sdmTMB::make_mesh(sdmTMB::pcod, c("X", "Y"), cutoff = 15)
plot_mesh(mesh, crs = 32609, data = sdmTMB::pcod, value = "density")

# }
```
