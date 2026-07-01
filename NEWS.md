# sdmTMBexperiments 0.1.0

First release. Experimental helper functions for fitted
[sdmTMB](https://github.com/sdmTMB/sdmTMB) models, ported and generalised from
project-local helpers.

## Functions

- Model comparison: `compare_models()` (+ `plot()` method).
- Mesh-resolution sensitivity: `compare_meshes()` (+ `plot()` method).
- Retrospective analysis: `sdmTMB_retro()` (+ `plot()` method).
- Survey-specific index comparison: `compare_surveys()` (+ `plot()` method:
  index, scatter, spatial).
- Spatial mesh cross-validation: `sdmTMB_mesh_cv()` (+ `plot()` method).
- Prediction grids: `make_survey_prediction_region()`, `make_prediction_grid()`.
- `mohns_rho()` — Mohn's rho for any set of index series.
- Plotting helpers: `plot_mesh()`, `plot_prediction_map()`,
  `plot_random_field()`, `plot_index()`, `plot_fixed_effects()`,
  `plot_variance_partitioning()`, `plot_prediction_histogram()`,
  `plot_residual_qq()`, and `bubble_map()`.
- Bundled public example data: `sebastes`.

## Fixes applied during extraction

- Assign `future.globals.maxSize` in the low-memory branch (previously computed
  but never applied).
- Correct the per-cell `mean_pr_diff` percent-difference formula in
  `compare_models()` and `compare_surveys()`.
- Unify the parallel seed argument to `future_seed` everywhere.
- Validate `X`/`Y` columns in `compare_meshes()`.
- Palette-safe colours in `plot.sdmTMB_mesh_comparison()` for any number of
  cutoffs.
- `sdmTMB_retro()` reuses the original mesh unchanged when `refit_meshes = FALSE`
  (no longer mutates `mesh$loc_xy`) and clamps `nyears` to the available years.
- Use portable `future::multisession` parallelism (works on Windows).
