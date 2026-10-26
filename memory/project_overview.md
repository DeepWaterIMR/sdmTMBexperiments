# Project overview

**sdmTMBexperiments** is a public R package (v0.1.6, GPL-3) of experimental
helper functions for fitted [sdmTMB](https://github.com/sdmTMB/sdmTMB) models.

## Purpose
A home for experimental `sdmTMB` helpers and a showcase of how to use them. The
functions may later be copied or adapted into `sdmTMB` itself (cite the
developer). They are deliberately generic.

## Scope boundary
This is **not** a redfish/assessment package. No species names, survey names,
ICES areas, file paths, or assessment assumptions belong in the package code.
Project-specific configuration stays in the downstream repositories that use the
package. The only redfish-flavoured artefact is the public `sebastes` example
dataset, which is generic demonstration data with documented provenance.

## What it provides
- Model comparison (`compare_models()`), mesh sensitivity (`compare_meshes()`),
  retrospective analysis (`sdmTMB_retro()`), survey comparison
  (`compare_surveys()`).
- Prediction-grid helpers (`make_survey_prediction_region()`,
  `make_prediction_grid()`).
- Spatial mesh cross-validation (`sdmTMB_mesh_cv()`).
- `mohns_rho()`.
- Diagnostic/result plotting (`plot_mesh()`, `plot_prediction_map()`,
  `plot_random_field()`, `plot_index()`, `plot_fixed_effects()`,
  `plot_variance_partitioning()`, `plot_prediction_histogram()`,
  `plot_residual_qq()`) and `bubble_map()`.

## Dependencies
- **Depends**: `R (>= 4.1.0)`, `ggOceanMaps` (default map tool; attached so its
  bundled land data is available).
- **Imports**: `sdmTMB`, `future`, `future.apply`, `dplyr`, `tibble`, `plyr`,
  `sf`, `scales`, `stats`, `ggplot2`, `cowplot`, `viridis`, `rlang`, `magrittr`.
- **Suggests**: `concaveman`, `blockCV`, `inlabru`, `DHARMa`, `ggspatial`,
  `cli`, `ps`, `memuse`, `RColorBrewer`, `sdmTMBextra`, `knitr`, `rmarkdown`,
  `testthat`.

## Links
- Repo: <https://github.com/DeepWaterIMR/sdmTMBexperiments>
- Site: <https://deepwaterimr.github.io/sdmTMBexperiments/>
