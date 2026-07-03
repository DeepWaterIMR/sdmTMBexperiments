# Plot mesh comparison results

Plots survey index time series from a mesh cutoff comparison (reference
in black, alternative cutoffs in colour, with Mohn's rho annotated), or
spatial maps of prediction differences on a
[`ggOceanMaps::basemap()`](https://mikkovihtakari.github.io/ggOceanMaps/reference/basemap.html).

## Usage

``` r
# S3 method for class 'sdmTMB_mesh_comparison'
plot(
  x,
  type = "index",
  index_divisor = NULL,
  unit = NA,
  mohn = FALSE,
  cutoff_label = "Cutoff",
  viridis = FALSE,
  spatial_response = "mean_pr_diff",
  transform_color_scale = TRUE,
  limit_rounding = 10,
  break_rounding = 5,
  base_size = 11,
  ...
)
```

## Arguments

- x:

  An object of class `sdmTMB_mesh_comparison`.

- type:

  Character. `"index"` (default) or `"spatial"`.

- index_divisor:

  Optional numeric divisor applied to index values.

- unit:

  Character. Unit label. If `NA`, `"Index value"` is used.

- mohn:

  Logical. Annotate the index plot with Mohn's rho (via
  [`mohns_rho()`](https://deepwaterimr.github.io/sdmTMBexperiments/reference/mohns_rho.md))?
  Default `FALSE`. Only applies when `type = "index"`.

- cutoff_label:

  Character. Label for the cutoff colour/fill legend. Default
  `"Cutoff"`.

- viridis:

  Logical. Use the viridis palette for cutoff levels? If `FALSE`
  (default), a palette-safe Set1 is used.

- spatial_response:

  Character. Column mapped in spatial plots: one of `"mean"`,
  `"pr_mean"` or `"mean_pr_diff"`. Default `"mean_pr_diff"`. See
  Details.

- transform_color_scale:

  Logical. Apply a signed square-root colour scale for spatial plots?
  Default `TRUE`.

- limit_rounding, break_rounding:

  Numeric rounding for map fill limits and breaks. Defaults `10` and
  `5`.

- base_size:

  Numeric. Base font size. Default `11`.

- ...:

  Currently ignored.

## Value

A `ggplot` object (`type = "index"`) or a `cowplot` grid
(`type = "spatial"`).

## Details

For `type = "spatial"`, each grid cell is compared between a model
fitted with an alternative mesh cutoff and the model fitted with the
reference cutoff, for every year they share, on the response scale (i.e.
`predict(..., type = "response")`, e.g. density rather than log
density): `diff = est - ref_est` and `pr_diff = 100 * diff / ref_est`
(percent). `spatial_response` selects how these per-year values are
summarised across years into the single value mapped for each cell:

- `"mean"`: `mean(diff)` — the average absolute difference, in response
  units. Useful for the raw magnitude of disagreement, but not
  comparable across cells with very different baseline abundance.

- `"pr_mean"`: `mean(pr_diff)` — the average of the yearly percent
  differences. Because each year is divided by that year's own (possibly
  small) reference value, a handful of low-abundance years/cells can
  dominate this average with large percentage swings even when the
  absolute difference is small.

- `"mean_pr_diff"` (default): `100 * mean(diff) / mean(ref_est)` — the
  percent difference between the across-year mean predictions (a ratio
  of means, not a mean of ratios). This is usually the more robust
  percent-based summary, since a cell's overall multi-year baseline is
  used in the denominator instead of each individual year's value.

## See also

[`compare_meshes()`](https://deepwaterimr.github.io/sdmTMBexperiments/reference/compare_meshes.md)

## Author

Mikko Vihtakari

## Examples

``` r
# \donttest{
mesh <- sdmTMB::make_mesh(sdmTMB::pcod, c("X", "Y"), cutoff = 20)
m <- sdmTMB::sdmTMB(
  data = sdmTMB::pcod, formula = density ~ 0 + as.factor(year),
  time = "year", mesh = mesh, family = sdmTMB::tweedie(link = "log")
)
nd <- sdmTMB::replicate_df(sdmTMB::qcs_grid, "year", unique(sdmTMB::pcod$year))
mesh_indices <- compare_meshes(
  object = m, mesh_cutoffs = c(10, 30), newdata = nd, object_crs = 32609,
  reference_name = "20 km"
)
plot(mesh_indices, cutoff_label = "Cutoff (km)")

plot(mesh_indices, type = "spatial")

# }
```
