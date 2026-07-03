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
  sizes.

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
