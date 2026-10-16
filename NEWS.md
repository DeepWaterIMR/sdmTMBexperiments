# sdmTMBexperiments 0.1.4

2026-10-16 Merge the refit, `xy_cols` and dependency fixes with the model-selection functions.

## New features

- New `sebastes_bathy` dataset (a ~45 KB coarse ETOPO 2022 depth raster of the
  `sebastes` study area) and `sebastes_depth()`, a `depth_fun` for
  `make_prediction_grid()`. The examples, vignette and tests use them so they
  no longer need the ~85 MB bathymetry download `ggOceanMaps::get_depth()`
  makes on first use. For demonstration only.

## Bug fixes

- Map helpers no longer fail with `object 'dd_land' not found` when
  ggOceanMaps is loaded but not attached (as in vignettes, tests and CI);
  ggOceanMaps is now attached for the duration of the call. The depth
  download in `make_prediction_grid()` also uses a longer timeout (600 s).

- `sdmTMB_retro()`, `compare_meshes()`, `sdmTMB_mesh_cv()` and
  `compare_surveys()` (with `compiled_model`) now refit models from the
  original `sdmTMB()` call, as `sdmTMB::update.sdmTMB()` does, instead of
  rebuilding the call from a handful of fields. Previously settings such as
  `spatial_varying`, `time_varying`, `extra_time`, `weights`, `priors`,
  `share_range`, `anisotropy` and `reml` were silently dropped, and
  `sdmTMB_mesh_cv()` also dropped the offset. The call's arguments are
  evaluated on the main process so they also reach parallel workers.
  `compare_surveys()` errors on a numeric `offset`/`weights` vector it cannot
  subset to the survey data.
- Coordinate columns are no longer assumed to be `X`/`Y`: fitted models use
  `object$spde$xy_cols`, and `compare_surveys()` gains an `xy_cols` argument
  for `compiled_model = NULL`.
- `compare_surveys()` no longer returns a garbled `sanity` table when one
  survey model fails to fit; failed fits get a column of `NA`s with the same
  checks as the others.
- `plot.sdmTMB_model_comparison()` now always draws the reference model in
  black, whatever the model names or `reference_model`. Index plots no longer
  give `NA` colours with more than seven series.
- Non-integer mesh cutoffs (e.g. `7.5`) are no longer truncated or turned into
  `NA` by `compare_meshes()` and `sdmTMB_mesh_cv()`.
- `compare_meshes()` no longer errors when the reference refit fails; it warns
  and returns `NA` prediction differences.
- `sdmTMB_retro()` and `compare_surveys()` now accept a numeric `area` vector
  with one value per row of `newdata`, subsetting it along with the
  prediction grid.
- Models with a time column not named `year` now work: index outputs always
  name their time column `year`, so plots, `mohns_rho()` and failed-fit rows
  line up.
- `compare_surveys()`, `compare_models()` and `compare_meshes()` gain a
  `coord_multiplier` argument (default `1000`, km to m), used for survey
  footprint clipping and the spatial maps, which previously assumed km.
- `sdmTMB_mesh_cv()` now takes its default `xy_cols` from the model mesh and
  errors clearly on the `NA` CRS that `make_mesh()` produces.
- `sdmTMB_retro(refit_meshes = FALSE)` now keeps a barrier mesh's barrier.
  `compare_meshes()`, `compare_surveys()`, `sdmTMB_mesh_cv()` and
  `sdmTMB_retro(refit_meshes = TRUE)` warn that the meshes they build have no
  barrier.
- `plot_variance_partitioning()` now only uses components whose SD is a
  link-scale SD: `sigma_O`, `sigma_E`, random intercepts, and `phi` only for
  `gaussian()` (identity link) and `lognormal()`. Previously it added `phi`
  for any family (a dispersion or shape parameter for e.g. Tweedie, Gamma
  and NB2) and smooth-term SDs, which are not link-scale variances.
- The index-plot annotation of `plot.sdmTMB_model_comparison()` and
  `plot.sdmTMB_mesh_comparison()` (`mohn = TRUE`) is now labelled
  "Terminal-year rel. diff.": all series there end in the same year, so it is
  not a retrospective Mohn's rho.
- `plot_prediction_histogram()` divides the observed response by
  `exp(offset)` for models with an offset, so it is on the same scale as the
  offset-free grid predictions.
- `sdmTMB_retro()`'s `predict_args` is now passed on to
  `sdmTMB::get_index_split()`; it previously had no effect.
- `plot.sdmTMB_retro()` keeps peels in order with more than ten peels.
- `plot.sdmTMB_survey_comparison(type = "scatter")` no longer errors for a
  survey with a flat index, and no longer warns about `.data` in tidyselect.
- The deprecated `trans` argument of ggplot2 scales is replaced with
  `transform`; ggplot2 >= 3.5.0 is now required.
- Failed fits now report the actual error instead of "did not converge", and
  fits that ran but fail `sdmTMB::sanity()` are flagged.

## Breaking changes

- `sdmTMB_retro(refit_meshes = TRUE)` now requires a `cutoff` argument
  instead of approximating it from the minimum mesh vertex distance.
- `sdmTMB_retro()`'s `n_workers` defaults to `1` (was `nyears`). With
  `n_workers = 1` all functions now use the user's current `future::plan()`
  instead of forcing a sequential one, and `future.globals.maxSize` is
  restored on exit.
- The `%>%` re-export is removed.

## Other changes

- `ggOceanMaps` moves from Depends to Suggests. Spatial plots fall back to a
  plain map without it; `bubble_map()` and automatic depth extraction in
  `make_prediction_grid()` require it.
- `plyr`, `magrittr` and `viridis` are no longer dependencies.
- `sdmTMB_mesh_cv()` documents AIC across meshes as a rough guide only.
- `tests/` and `vignettes/` are no longer build-ignored, so `R CMD check` on
  CI now runs the tests and builds the vignette. New tests check that refits
  reproduce the original fit.

# sdmTMBexperiments 0.1.3

2026-10-14 Regenerate `plot_mesh.Rd` so its usage lists the new `plot_mesh()` arguments (fixes the R CMD check codoc WARNING).

# sdmTMBexperiments 0.1.2

2026-10-14 Adds the model-selection functions and fixes delta-family labelling in `sdmTMB_selection()`.

## Model selection

A set of functions for building defensible model-selection tables, ported from
two survey- and CPUE-index workflows:

- `sdmTMB_selection()` fits a named list of candidate specifications to
  identical records and returns a tidy table: the full specification of each
  candidate, its crash/convergence/sanity status, in-sample NLL and AIC with
  delta-AIC and Akaike weights, and — with `cv` — cross-validated predictive
  skill. One function covers component ranking, dropping fixed effects, family
  selection, spatiotemporal-structure selection and mesh resolution, since each
  is the same operation with a different thing varied. Caches one file per
  candidate (resumable, and `only` lets a long ladder be spread over several R
  sessions).
- `selection_frame()` builds the complete-case frame that makes those columns
  comparable in the first place: candidates that use different covariates
  otherwise get silently fitted to different subsets of the data.
- `sdmTMB_cv_summary()` summarises an `sdmTMB::sdmTMB_cv()` run **per held-out
  observation** rather than summed over folds, and reports `folds_pdhess` and
  `n_heldout` so a fragile row is visible as such. A summed hold-out
  log-likelihood rewards whichever candidate scored fewest points.
- `best_candidate()` looks the winner up in the metric column rather than by row
  position, skipping rows the table marks as not comparable. Also builds a
  cross-validation shortlist from an AIC ladder (`n`).
- `add_aic_weights()` adds `deltaAIC`/`AICweight` to any table with an `AIC`
  column, with a `group` argument for tables that mix models fitted to
  different response data (where a common weight would be meaningless).
- `plot()` methods: `type = "selection"` is a status-coded dot plot of the
  ranking; `type = "index"` overlays the survey index each candidate produces,
  which answers the question a selection table cannot — whether the choice
  actually moves the index.

## Plotting

- `plot_mesh()` gains `land_col`, `lon_interval`/`lat_interval`, `utm_axes` and
  `zero_col`/`zero_size`/`zero_alpha`. **All default to the previous behaviour**, so existing
  figures are unchanged.
  - `utm_axes = TRUE` labels the axes in projected kilometres — the units the model actually
    fits in — instead of degrees. The breaks are explicit numeric values derived from the mesh
    extent; a breaks *function* is evaluated against the panel range rather than the `coord_sf()`
    graticule and bunches every label into one corner.
  - `zero_col` draws stations whose `value` is zero as small faint crosses beneath the sized
    points. Without it they are invisible, because `scale_size_area()` maps zero to zero area —
    yet in a survey dataset the zeros are usually the majority of the stations and carry the
    absence information. They are drawn small and faint by default for the same reason.

## Fixes

- `.safe_index()` (used by `compare_models()`, `compare_meshes()`,
  `compare_surveys()`, `sdmTMB_retro()` and the new selection index plot) now
  survives a *failed index extraction*, not only a failed fit. `get_index_split()`
  can throw for a model that fitted perfectly well — a `newdata` grid that does
  not overlap the fitted coordinates, a year in the grid but not in the model, a
  split landing on an empty subset — and because these functions summarise many
  models in one figure at the end of a multi-hour render, one unlucky model used
  to take the whole plot with it. It is now warned about (naming the model where
  the caller supplies a label) and returned as a `type = "crashed"` row.
- `sdmTMB_selection()` handles delta families: the table has exactly one row per
  candidate (a delta family's two-element `family$family` no longer recycles the
  row), and the `family` column and `spec` string use sdmTMB's `clean_name`
  (e.g. `delta_gamma(link1 = 'log', link2 = 'log', type = 'poisson-link')`)
  instead of the first component's family, which labelled a Poisson-link delta
  fit as "binomial". Non-delta families are unchanged (e.g. "tweedie").

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
- `sdmTMB_retro()` rebuilds the mesh's data mapping for each peel when
  `refit_meshes = FALSE` (previously reusing the fitted `sdmTMBmesh` unchanged
  meant every peel but the terminal one failed to converge and silently
  returned `NA` index rows), and clamps `nyears` to the available years.
- Use portable `future::multisession` parallelism (works on Windows).
- `compare_surveys()` no longer silently inherits an `NA` CRS from
  `compiled_model` when `object_crs` is left `NULL` (a normally built
  `sdmTMB::make_mesh()` mesh has `crs = NA`, not `NULL`); it now errors with a
  clear message asking for `object_crs` instead of failing deep inside
  `plot(..., type = "spatial")`.
- `plot_prediction_map()` no longer hardcodes a `limits = c(0, NA)` fill
  scale, which silently rendered any out-of-range cell (e.g. negative
  link-scale predictions) as blank/grey with no indication why. The scale
  range is now taken from the data by default; a new `fill_limits` argument
  (default `NULL`) lets you opt into an explicit floor/ceiling, and a warning
  fires only if that explicit choice actually clips data.
- `sdmTMB_mesh_cv()`'s `deltaNLL`/`deltaNLL_pr` had the wrong sign: they were
  computed straight from `sum_loglik` (a log-likelihood, where higher is
  better) without negating it, so despite the name they were a
  delta-log-likelihood (`<= 0`, max = best) rather than a proper delta-NLL.
  Now `>= 0` with `0` (min) indicating the best-fitting mesh cutoff,
  consistent with `deltaAIC`.
- The vignette's `compare_surveys()` example fit `density` as the response
  while also passing a `swept_area` log-offset; since `density` is already
  `biomass / swept_area`, this double-corrected for effort and, combined with
  an `area` argument left in km² instead of `swept_area`'s square nautical
  miles, inflated the resulting index by roughly 1000x. Fixed by fitting
  `biomass` as the response and converting `area` to square nautical miles.
- `.spatial_diff_map()`'s (the shared spatial-difference map used by all
  three comparison `plot()` methods) fill-scale breaks could be crowded/
  illegible for skewed or extreme ranges, and didn't guarantee the scale's
  actual limits or `0` were shown. Breaks are now guaranteed to include the
  limits and `0` (when spanned), de-crowded so adjacent breaks are never too
  close together, and labelled with abbreviated numbers (e.g. `"-9.2K"`) via
  `scales::label_number(scale_cut = scales::cut_short_scale())`.
- `compare_models()`/`compare_surveys()`'s spatial `plot()` methods
  unconditionally labelled the fill legend "Percent anomaly" even when
  `spatial_response = "mean"` (an absolute density difference, not a
  percent); `compare_meshes()` didn't have this bug. Fixed by only applying
  the percent label when `spatial_response` is actually one of the
  percent-based options.
- The rightmost year's x-axis label was cropped in every index plot
  (`plot_index()`, and the `type = "index"` `plot()` methods of the three
  comparison functions and `sdmTMB_retro()`): `coord_cartesian(expand =
  FALSE)` puts the last data point exactly on the panel edge, and the
  default plot margin didn't leave room for its tick label. Fixed with a
  shared, wider plot margin.
- Those same index plots' x-axis could show decimal year breaks (`2020.0`,
  `2020.5`, ...) for short year ranges, since `scales::pretty_breaks()` picks
  sub-1 steps when that gives a better fit to the target break count. Whole
  year ranges now always get whole-year breaks (falling back to the regular
  algorithm only if the range itself isn't whole numbers).
- `R CMD check` and CI (`R-CMD-check.yaml`, `pkgdown.yaml`) failed entirely at
  dependency resolution: `sdmTMBextra` was listed in `Suggests` but is a
  GitHub-only package (not on CRAN/Bioconductor), which `pak` can't resolve.
  Removed it from `Suggests` (it was only referenced in one roxygen doc link,
  never used in code). Also fixed, found while investigating: a non-ASCII
  character in a `sprintf()` string in `compare-surveys.R`, an undocumented
  `...` argument in `plot.sdmTMB_prediction_grid()`, and a stray `Rplots.pdf`
  accidentally committed at the repo top level.

## Other changes

- `plot.sdmTMB_model_comparison(type = "index")` gains a `mohn` argument
  (default `FALSE`) controlling whether the Mohn's rho annotation is added;
  previously it was always shown.
- `plot.sdmTMB_model_comparison(type = "spatial")` gains a `fill_prefix`
  argument for the fill legend title (e.g. `"Biomass density"`, `"CPUE"`).
  Previously the legend was hardcoded to "Biomass density\npercent anomaly",
  which doesn't hold for models with other response variables. Default `NULL`
  now gives a generic "Percent anomaly" title.
- `plot_prediction_map()`'s `trans` argument is renamed `transform` (default
  `"identity"`, was `"sqrt"`), matching ggplot2's `continuous_scale()` API
  (`trans` is deprecated there in favour of `transform`).
- `plot.sdmTMB_mesh_comparison(type = "index")` gains the same `mohn`
  argument (default `FALSE`) as `plot.sdmTMB_model_comparison()`, and a
  `cutoff_label` argument (default `"Cutoff"`) for the colour/fill legend
  title, e.g. `cutoff_label = "Cutoff (km)"`.
- `compare_meshes()` now also computes `mean_pr_diff`, so
  `spatial_response = "mean_pr_diff"` is available for
  `plot.sdmTMB_mesh_comparison(type = "spatial")` — previously only
  `compare_models()`/`compare_surveys()` computed it, so mesh comparisons
  silently had one fewer (and arguably the most useful) spatial-plot option.
- Documented what the `spatial_response` options (`"mean"`, `"pr_mean"`,
  `"mean_pr_diff"`) actually compute and when to prefer each, in the `plot()`
  methods of all three comparison functions (`?plot.sdmTMB_model_comparison`
  etc.) and in the vignette.
- `make_prediction_grid()` output now carries class `sdmTMB_prediction_grid`
  and `crs`/`coord_multiplier`/`resolution` attributes, and gains a
  `plot.sdmTMB_prediction_grid()` method: draws the grid points as squares on
  a [ggOceanMaps::basemap()], optionally coloured by a column (`depth` by
  default, when present).
- `make_prediction_grid()` now extracts depth automatically when `max_depth`
  is set and no `depth_fun` is supplied, via
  `ggOceanMaps::get_depth(bathy.style = bathy_style)` (new `bathy_style`
  argument, default `"raster_continuous"`, ggOceanMaps' bundled ETOPO grid —
  no extra download path needed). A custom `depth_fun` still overrides this
  for other bathymetry sources.
- `compare_models()`, `compare_meshes()` and `compare_surveys()` no longer
  leak `sdmTMB`'s informational "assuming the offset vector is 0" message
  (from `predict.sdmTMB()`) when comparing models fit with an offset. This is
  expected/correct — prediction grids aren't real hauls, so the offset is
  deliberately zero and area-weighting is done via the `area` argument
  instead — but it was showing on every spatial-difference calculation
  (`.pred_diff_base()`, shared by all three comparison functions) with no way
  to turn it off; `.safe_index()`'s `get_index_split()` call already
  suppressed it.
- Default `spatial_response` for all three comparison `plot()` methods changes
  from `"pr_mean"` to `"mean_pr_diff"` — the more robust of the two percent
  summaries (see the `spatial_response` docs/vignette for why).
- Default `metric` for `plot.sdmTMB_mesh_cv()` changes from `"sum_loglik"` to
  `"deltaNLL"` (now that its sign is fixed — see above), which is easier to
  read at a glance than the raw summed log-likelihood.
- `plot.sdmTMB_survey_comparison(type = "spatial")` gains the same
  `fill_prefix` argument as `plot.sdmTMB_model_comparison()`.
- `plot.sdmTMB_survey_comparison(type = "scatter")` gains an `annotate_fit`
  argument (default `TRUE`): annotates each survey's regression line with its
  fitted equation and R², coloured to match that survey.
- `compare_models()` and `compare_meshes()` had the same silent-`NA`-CRS bug
  as the `compare_surveys()` fix above; fixed the same way. Found by actually
  running every function's roxygen example end-to-end (see below) — prior
  examples happened to always pass `object_crs` explicitly, so this had never
  surfaced.
- `bubble_map()`'s legend was rendering as two separate, mismatched legends
  (one binned colour swatch legend, one continuous size legend), and printed
  an "Ignoring unknown labels: colour" warning. Fixed: the `fill`/`colour` and
  `size` scales now use matching `guide = "bins"` so ggplot2 merges them into
  one combined size+colour legend, and a redundant `shape` aesthetic mapping
  (constant within each already-split zero/non-zero data subset, but was
  breaking the guide merge even with `guide = "none"`) is now a fixed value
  per layer instead of a mapped-but-hidden aesthetic.
- Every exported function now has a working `@examples` block. Since `sdmTMB`
  is an Imports (not Depends) dependency, unqualified calls like `pcod` or
  `make_mesh()` fail outside a session with `library(sdmTMB)` attached — one
  existing example (`plot_residual_qq()`) had this bug. Slow (model-fitting)
  examples are wrapped in `\dontrun{}`, which — unlike `\donttest{}` — is
  never run by this package's `R CMD check` (even under `--as-cran`) but does
  run on the pkgdown site (`run_dont_run = TRUE` is now passed in
  `.github/workflows/pkgdown.yaml`). See `memory/examples-policy.md`.
- `sdmTMB_mesh_cv()` (spatial block cross-validation across mesh cutoffs,
  via `blockCV::cv_spatial()` + `sdmTMB::sdmTMB_cv()`) is confirmed working
  end-to-end and now has a real, runnable example (was previously untested,
  with a placeholder example referencing an undefined `fit`).
