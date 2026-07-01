# Naming conventions

Aligned with [sdmTMB](https://github.com/sdmTMB/sdmTMB): snake_case functions,
thematic kebab-case source files, `sdmTMB_`-prefixed names for model-level
operations, and argument names reused from `sdmTMB` where an equivalent exists.

## Functions
- `compare_models()`, `compare_meshes()`, `compare_surveys()` — snake_case verbs.
- `sdmTMB_retro()`, `sdmTMB_mesh_cv()` — `sdmTMB_` prefix, mirroring
  `sdmTMB::sdmTMB_cv()` (model-level operations).
- `make_survey_prediction_region()`, `make_prediction_grid()`, `mohns_rho()`,
  `bubble_map()`, and the `plot_*()` helpers.

## Arguments (reuse sdmTMB names)
`bias_correct`, `level`, `area`, `newdata`, `mesh`, `time`, `offset`, `nsplit`,
`silent`, `predict_args`. The parallel seed argument is **`future_seed`
everywhere** (the source repo had a `future.seed` in `compare_models()` — unified
during the port). Mesh cutoffs use `mesh_cutoff` / `cutoff`, matching
`make_mesh(cutoff=)`.

## S3 classes
`sdmTMB_*` family, consistent with `sdmTMB_cv`: `sdmTMB_model_comparison`,
`sdmTMB_mesh_comparison`, `sdmTMB_survey_comparison`, `sdmTMB_retro`,
`sdmTMB_mesh_cv`.

## Name map (source repo → package)
- `compare_models(future.seed=)` → `compare_models(future_seed=)`
- `mesh_cutoff_cv()` (proposed) → `sdmTMB_mesh_cv()` (parallels `sdmTMB_cv`)
- inline Mohn's-rho blocks in plot methods → exported `mohns_rho()`
- concave-hull grid code inside `compare_surveys()` → exported
  `make_survey_prediction_region()` + internal `.clip_points_to_region()`
- source file names `sdmTMB_compare_functions.R` etc. → kebab-case
  `compare-models.R`, `compare-meshes.R`, `compare-surveys.R`, `retro.R`.
