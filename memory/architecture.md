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
- `R/model-selection.R` — `sdmTMB_selection()` + `print`/`plot` methods,
  `selection_frame()`, `sdmTMB_cv_summary()`, `best_candidate()`,
  `add_aic_weights()`, and the internals `.resolve_candidate()`,
  `.selection_table()`, `.selection_slug()`, `.selection_status()`,
  `.all_sane()`, `.min_or_na()`, `.modal()`, `.is_true()`
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
- `.safe_index()` — `sdmTMB::get_index_split()` with a `cv` column and a fallback
  for **both** a crashed model and a crashed *extraction* (an overlapping-grid or
  empty-split failure from a model that fitted fine): warns, naming the model when
  a `label` is given, and returns a `type = "crashed"` row rather than aborting a
  figure that summarises many models at the end of a long render. Used by all the
  comparison/retro functions and by `plot.sdmTMB_selection(type = "index")`.
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
`sdmTMB_retro`, `sdmTMB_mesh_cv`, `sdmTMB_selection` — each with a `plot()`
method (`sdmTMB_selection` also has `print()`).

## The model-selection contract (`R/model-selection.R`)
The design decisions behind the selection table, all of them fixes for ways a
selection table can lie:

- **Identical records.** `selection_frame()` drops rows incomplete for *any*
  candidate before fitting, so AIC and hold-out log-likelihoods compare the same
  quantity. Without it, a candidate carrying `s(depth)` is silently fitted to a
  different subset than one that is not. Select on that frame; fit the *chosen*
  specification to the full data afterwards.
- **A `spec` column.** Every row carries the full specification (formula,
  family, spatial, spatiotemporal) built when the candidate is resolved, so the
  table states what was fitted instead of relying on a row label.
- **Per-observation hold-out log-likelihood.** A summed one is not comparable
  across candidates that scored different numbers of points, and rewards the
  candidate that scored fewest. `n_heldout` and `folds_pdhess` are reported so a
  fragile row is visible.
- **`comparable` gates on convergence and record count, NOT on `sanity()`.**
  `sanity()` fails routinely on perfectly usable fits (`se_magnitude_ok`,
  `sigmas_ok` on `pcod`, for instance), so gating on it would drop the
  best-fitting candidate from every comparison. It is reported in its own column
  and colours the `type = "selection"` dot plot instead.
- **Never read the winner off row 1.** `best_candidate()` looks it up in the
  metric column among comparable rows; the table's sort key changes with whether
  CV ran.
- **Cache one file per candidate**, keyed by a slug plus a hash of the exact
  name (`"+ depth"` and `"depth"` normalise identically, and a collision would
  serve one candidate's fit as another's). `only` restricts a call to named
  candidates so a long ladder can be spread over several R sessions, which
  matters when a large spatiotemporal fit exhausts memory after a dozen
  accumulate in one process.
- **`fit_full = FALSE`** skips the whole-frame fit and reads the status columns
  off the cross-validation instead, with `AIC` as the median across fold models.

## Parallelism
All heavy loops use `future.apply::future_lapply(..., future.seed = future_seed)`
under a plan installed by `.setup_parallel()`. `multisession` was chosen over the
source repo's `multicore` for cross-platform (Windows) portability; users can set
their own plan and pass `n_workers = 1` to leave it untouched.

## Map rendering
All map helpers render onto `ggOceanMaps::basemap()`. Because ggOceanMaps' bundled
`dd_land` is only visible when the package is attached, `ggOceanMaps` is a
**Depends** (attached with `library(sdmTMBexperiments)`), not an Import.
