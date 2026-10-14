# AGENTS.md — using sdmTMBexperiments with an AI assistant

This file is written for AI assistants helping a user *use*
sdmTMBexperiments to run experiments on fitted
[sdmTMB](https://github.com/sdmTMB/sdmTMB) models. For working on the
package source itself, see
[CLAUDE.md](https://deepwaterimr.github.io/sdmTMBexperiments/CLAUDE.md).

## What this package does

sdmTMBexperiments is a collection of experimental helper functions built
around fitted `sdmTMB` models: model comparison, mesh-resolution
sensitivity, retrospective analysis, survey-specific index comparison,
prediction-grid construction, and diagnostic/result plotting. Functions
are generic (nothing is hard-coded to a species or region) and may later
be adopted into `sdmTMB` itself. Cite the developer when you reuse them.

Maps are drawn on
[ggOceanMaps](https://mikkovihtakari.github.io/ggOceanMaps/) basemaps,
which is the package’s default map-plotting tool.

## Core conventions

- **Coordinates**: model `X`/`Y` are expected in **kilometres** (the
  `sdmTMB` convention). Helpers multiply by `coord_multiplier` (default
  `1000`) to get CRS metres for `sf`/mapping.
- **Attach the package** with
  [`library(sdmTMBexperiments)`](https://github.com/DeepWaterIMR/sdmTMBexperiments)
  — this attaches `ggOceanMaps` (a `Depends`) so basemaps find their
  bundled land data.
- **Suggested packages** some functions need: `concaveman` (survey
  regions), `blockCV`
  ([`sdmTMB_mesh_cv()`](https://deepwaterimr.github.io/sdmTMBexperiments/reference/sdmTMB_mesh_cv.md)),
  `inlabru`
  ([`plot_mesh()`](https://deepwaterimr.github.io/sdmTMBexperiments/reference/plot_mesh.md)),
  `DHARMa`, `ggspatial`
  ([`bubble_map()`](https://deepwaterimr.github.io/sdmTMBexperiments/reference/bubble_map.md)),
  `cli` (progress messages).

## Minimal working examples

``` r

library(sdmTMBexperiments)
library(sdmTMB)

mesh <- make_mesh(pcod, c("X", "Y"), cutoff = 20)
m1 <- sdmTMB(density ~ 0 + as.factor(year), data = pcod,
             time = "year", mesh = mesh, family = tweedie())
m2 <- sdmTMB(density ~ 0 + as.factor(year) + depth_scaled, data = pcod,
             time = "year", mesh = mesh, family = tweedie())
nd <- replicate_df(qcs_grid, "year", unique(pcod$year))

# Compare models (indices + spatial prediction differences + Mohn's rho)
cmp <- compare_models(m1, m2, newdata = nd, object_crs = 32609)
plot(cmp)                     # index time series
plot(cmp, type = "spatial")   # per-cell prediction-difference maps

# Mesh-resolution sensitivity
mc <- compare_meshes(m1, mesh_cutoffs = c(10, 30), newdata = nd,
                     reference_name = "20 km")
plot(mc)

# Retrospective analysis
retr <- sdmTMB_retro(m1, nd, nyears = 5)
plot(retr)

# Diagnostics and result maps
plot_mesh(mesh, crs = 32609, data = pcod, value = "density")
pred <- predict(m1, newdata = nd)
plot_prediction_map(pred, crs = 32609)          # averaged density
plot_random_field(pred, crs = 32609, field = "omega")
plot_residual_qq(m1)
plot_variance_partitioning(m1)
```

### Model selection

[`sdmTMB_selection()`](https://deepwaterimr.github.io/sdmTMBexperiments/reference/sdmTMB_selection.md)
fits a named list of candidates to identical records and returns a tidy,
defensible selection table. The same function covers every selection
stage — component ranking, dropping fixed effects, family,
spatiotemporal structure, mesh resolution — because each is the same
operation with a different thing varied.

``` r

cands <- list(
  "Full model"        = density ~ 0 + as.factor(year) + depth_scaled,
  "No depth"          = density ~ 0 + as.factor(year),
  "No spatiotemporal" = list(spatiotemporal = "off"),
  "Tweedie"           = list(family = tweedie()),
  "Coarser mesh"      = list(cutoff = 40)
)

sel <- sdmTMB_selection(
  cands, data = pcod,
  formula = density ~ 0 + as.factor(year) + depth_scaled,
  cutoff = 25, family = tweedie(), time = "year",
  spatial = "on", spatiotemporal = "iid",
  cache_dir = "data/output/selection"      # one file per candidate, resumable
)

sel                                  # print method: the table + comparability
plot(sel)                            # status-coded ranking dot plot
plot(sel, type = "index", newdata = nd)   # does the choice move the index?
best_candidate(sel)                  # by the metric column, never by row order
```

Cross-validate a **shortlist**, not the whole ladder — CV costs `k` fits
per candidate:

``` r

short <- best_candidate(sel, n = 3, by = "aic")
cv <- sdmTMB_selection(cands[short], data = pcod, ..., cv = 10,
                       cache_dir = "data/output/selection")
```

Rules that make the table mean something (all enforced or reported by
the function; see
[`?sdmTMB_selection`](https://deepwaterimr.github.io/sdmTMBexperiments/reference/sdmTMB_selection.md)):

- Candidates are fitted to **identical records**
  (`complete_cases = TRUE`, via
  [`selection_frame()`](https://deepwaterimr.github.io/sdmTMBexperiments/reference/selection_frame.md)).
  Fit the *selected* specification to the full data afterwards.
- Compare only rows with `comparable == TRUE`, and never quote a delta
  between two candidates unless both are.
- Hold-out log-likelihood is reported **per observation**, with
  `n_heldout` and `folds_pdhess` beside it.
- `fold_ids` from
  [`blockCV::cv_spatial()`](https://rdrr.io/pkg/blockCV/man/cv_spatial.html)
  gives spatially clustered folds (extrapolation into unsampled ground);
  the default random folds measure interpolation. `lfo = TRUE` scores
  prediction of unseen *years*, which is what an assessment update
  actually asks.

### Survey comparison (uses the bundled `sebastes` data)

[`compare_surveys()`](https://deepwaterimr.github.io/sdmTMBexperiments/reference/compare_surveys.md)
fits a separate model per survey series, builds a survey-specific
prediction grid from each survey’s spatial footprint, and compares to a
compiled reference index.

``` r

data(sebastes)
region <- make_survey_prediction_region(subset(sebastes, cruiseseries == "EggaN"),
                                        crs = 32633)
grid <- make_prediction_grid(region, resolution = 20)
```

## Common pitfalls

1.  **`X`/`Y` are in km.** Passing metres will place data in the wrong
    location.
2.  **Attach, don’t just `::`.** Map functions rely on `ggOceanMaps`
    being attached (it is, via
    [`library(sdmTMBexperiments)`](https://github.com/DeepWaterIMR/sdmTMBexperiments)).
    Using `::` on a bare namespace can fail with
    `object 'dd_land' not found`.
3.  **Bias correction is slow.** `bias_correct = FALSE` is the default;
    turn it on only for final runs.
4.  **`compare_surveys(type = "spatial")`** needs a `compiled_model`;
    without one, spatial differences are skipped.
5.  **Do not read the selected model off the first table row.** Use
    [`best_candidate()`](https://deepwaterimr.github.io/sdmTMBexperiments/reference/best_candidate.md);
    the sort key changes with whether cross-validation ran.
6.  **A `sanity = FALSE` winner is not disqualified.**
    [`sanity()`](https://sdmTMB.github.io/sdmTMB/reference/sanity.html)
    fails routinely on usable fits, so it does not gate `comparable` —
    read it as a reason to consider simplifying, not as a row to skip.

## Where to find more

- Function reference:
  <https://deepwaterimr.github.io/sdmTMBexperiments/reference/>
- Issues: <https://github.com/DeepWaterIMR/sdmTMBexperiments/issues>

## For agents developing the package

If you are helping work on the package source (not just using it), start
with
[CLAUDE.md](https://deepwaterimr.github.io/sdmTMBexperiments/CLAUDE.md)
and the
[`memory/`](https://deepwaterimr.github.io/sdmTMBexperiments/memory/)
folder. `memory/` is the project’s persistent memory;
[`memory/MEMORY.md`](https://deepwaterimr.github.io/sdmTMBexperiments/memory/MEMORY.md)
is the index.

**Bump the version with every commit.** Increase `Version` in
`DESCRIPTION` (by default one patch step per commit; minor/major only
when the maintainer asks), set `Date` to the commit date, and give
`NEWS.md` a matching `# sdmTMBexperiments x.y.z` heading. See
[`memory/versioning.md`](https://deepwaterimr.github.io/sdmTMBexperiments/memory/versioning.md).

**Do not put personal information into `memory/`, `AGENTS.md`, or
`CLAUDE.md`.** The whole repository is public on GitHub. Never commit
absolute local paths (e.g. `/Users/<name>/...`), machine-specific
filenames, or contact details beyond the maintainer’s public package
metadata; use placeholders such as `~/...` or `path/to/your/file`.
