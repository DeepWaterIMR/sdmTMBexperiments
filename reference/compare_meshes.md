# Compare survey indices across different mesh cutoff values

Refits an sdmTMB model using a range of mesh cutoff values and compares
the resulting survey indices and predictions to the original (reference)
model. Useful for assessing the sensitivity of an index to mesh
resolution.

## Usage

``` r
compare_meshes(
  object,
  mesh_cutoffs,
  newdata,
  object_crs = NULL,
  bias_correct = FALSE,
  level = 0.95,
  area = 1,
  save_models = FALSE,
  silent = TRUE,
  n_workers = 1,
  nsplit = 3,
  future_seed = TRUE,
  reference_name = "Reference"
)
```

## Arguments

- object:

  A fitted model from
  [`sdmTMB::sdmTMB()`](https://sdmTMB.github.io/sdmTMB/reference/sdmTMB.html).

- mesh_cutoffs:

  Numeric vector of mesh cutoff values (in the units of the model
  coordinates, typically km) to compare.

- newdata:

  A data frame for predictions, with the same predictor columns as the
  fitted data and a time column matching the fitted data. Must contain
  `X` and `Y` columns.

- object_crs:

  Coordinate reference system for the model data. If `NULL` (default),
  extracted from the model's mesh.

- bias_correct:

  Logical. Apply bias correction via
  [`TMB::sdreport()`](https://rdrr.io/pkg/TMB/man/sdreport.html)?
  Default `FALSE`.

- level:

  Numeric. Confidence level for index intervals. Default `0.95`.

- area:

  Grid cell area for area-weighted index calculation. Passed to
  [`sdmTMB::get_index_split()`](https://sdmTMB.github.io/sdmTMB/reference/get_index.html).

- save_models:

  Logical. Retain fitted model objects in the output? Default `FALSE`.

- silent:

  Logical. Suppress model output? Default `TRUE`.

- n_workers:

  Integer. Number of parallel workers. Default `1`.

- nsplit:

  Integer. Number of splits for
  [`sdmTMB::get_index_split()`](https://sdmTMB.github.io/sdmTMB/reference/get_index.html).
  Default `3`.

- future_seed:

  Logical or integer. Future-compatible random seed for parallel
  processing.

- reference_name:

  Character. Label for the reference (original) model. Default
  `"Reference"`.

## Value

An object of class `sdmTMB_mesh_comparison`, a list with `index`,
`pred_diff` (and optionally `models`). Carries `crs` and
`reference_name` attributes.

## See also

[`sdmTMB::sdmTMB()`](https://sdmTMB.github.io/sdmTMB/reference/sdmTMB.html),
[`sdmTMB::get_index_split()`](https://sdmTMB.github.io/sdmTMB/reference/get_index.html),
[`plot.sdmTMB_mesh_comparison()`](https://deepwaterimr.github.io/sdmTMBexperiments/reference/plot.sdmTMB_mesh_comparison.md)

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
plot(mesh_indices)

# }
```
