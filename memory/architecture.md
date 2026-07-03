# Architecture

## Source layout (kebab-case, sdmTMB-style)
- `R/compare-models.R` — `compare_models()` + `plot.sdmTMB_model_comparison()`
- `R/compare-meshes.R` — `compare_meshes()` + `plot.sdmTMB_mesh_comparison()`
- `R/compare-surveys.R` — `compare_surveys()` + `plot.sdmTMB_survey_comparison()`
- `R/retro.R` — `sdmTMB_retro()` + `plot.sdmTMB_retro()`
- `R/mesh-cv.R` — `sdmTMB_mesh_cv()` + `plot.sdmTMB_mesh_cv()`
- `R/prediction-grid.R` — `make_survey_prediction_region()`,
  `make_prediction_grid()`, internal `.clip_points_to_region()`
- `R/mohns-rho.R` — `mohns_rho()`
- `R/plot.R` — diagnostic/result plotting helpers
- `R/bubble-map.R` — `bubble_map()`
- `R/utils.R` — internal shared helpers
- `R/data-docs.R` — `sebastes` dataset docs

## Shared internals (`R/utils.R`)
- `.setup_parallel(n_workers)` — captures the old future plan, installs a
  portable `multisession` plan (or `sequential`), sets `future.globals.maxSize`;
  returns the old plan. Callers do `on.exit(future::plan(old_plan), add = TRUE)`.
- `.set_future_memory()` — sizes `future.globals.maxSize` from free RAM via `ps`
  (guarded); this is where the old "computed but never assigned" memory bug was
  fixed.
- `.safe_index()` — `sdmTMB::get_index_split()` with a crashed-model fallback and
  a `cv` column. Used by all four comparison/retro functions.
- `.pred_diff_base()` — predicts a model and a reference model onto the shared
  years and returns per-cell `est`, `ref_est`, `diff`, `pr_diff` (+ `depth`).
- `.spatial_diff_map()` — builds one ggOceanMaps spatial-difference map;
  aggregates over years, converts to `sf`, applies the signed-sqrt colour scale.
  Shared by the three comparison `plot()` methods. Takes a `fill_prefix`
  argument (its own percent-vs-absolute label logic, shared via
  `.pct_spatial_responses`) so callers no longer need to override the fill
  legend label after the fact.
- `.safe_brewer(n, palette)` — RColorBrewer wrapper valid for any `n`.
- `.negsqrt_trans()` — signed square-root scales transformation.
- `.diverging_breaks(limits, rounding, n)` — break points for
  `.spatial_diff_map()`'s diverging fill scale: always includes the exact
  limits and `0` (when spanned), then de-crowds additional breaks (minimum
  gap in the same signed-sqrt space the scale uses) rather than forcing a
  fixed count. Paired with `scales::label_number(scale_cut =
  scales::cut_short_scale())` for abbreviated labels (`"-9.2K"`).
- `.pct_spatial_responses` — the `spatial_response` values that are
  percentages (`pr_anomaly`, `total_pr_anomaly`, `max_pr_anomaly`, `pr_mean`,
  `mean_pr_diff`), vs. absolute response-unit differences (e.g. `"mean"`).
  Shared between `.spatial_diff_map()`'s fill-label logic and the two
  comparison `plot()` methods that build a `fill_prefix` on top of it.
- `.index_axis_layers()` — shared `coord_cartesian(expand = FALSE, clip =
  "off")` + x-axis breaks (`.year_breaks()`) + wider `plot.margin` for every
  yearly index plot (`plot_index()` and the `type = "index"` methods of the
  three comparison functions and `sdmTMB_retro()`). Must be added *after* the
  complete theme (`theme_classic()`/`theme_bw()`) in each caller — a complete
  theme replaces the whole theme when added with `+`, so adding it earlier
  silently discards the margin override.
- `.year_breaks(n)` — x-axis breaks for `.index_axis_layers()`: whole-year
  ranges get whole-year `pretty()` breaks (never `2020.0`/`2020.5`), falling
  back to `scales::extended_breaks()` only when the axis range itself isn't
  whole numbers.
- `.index_color_vector` — fixed palette (reference series drawn black).

## S3 classes
`sdmTMB_model_comparison`, `sdmTMB_mesh_comparison`, `sdmTMB_survey_comparison`,
`sdmTMB_retro`, `sdmTMB_mesh_cv` — each with a `plot()` method.

## Parallelism
All heavy loops use `future.apply::future_lapply(..., future.seed = future_seed)`
under a plan installed by `.setup_parallel()`. `multisession` was chosen over the
source repo's `multicore` for cross-platform (Windows) portability; users can set
their own plan and pass `n_workers = 1` to leave it untouched.

## Map rendering
All map helpers render onto `ggOceanMaps::basemap()`. Because ggOceanMaps' bundled
`dd_land` is only visible when the package is attached, `ggOceanMaps` is a
**Depends** (attached with `library(sdmTMBexperiments)`), not an Import.
