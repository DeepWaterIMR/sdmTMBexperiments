# AGENTS.md — using sdmTMBexperiments with an AI assistant

This file is written for AI assistants helping a user *use* sdmTMBexperiments to
run experiments on fitted [sdmTMB](https://github.com/sdmTMB/sdmTMB) models. For
working on the package source itself, see [CLAUDE.md](CLAUDE.md).

## What this package does

sdmTMBexperiments is a collection of experimental helper functions built around
fitted `sdmTMB` models: model comparison, mesh-resolution sensitivity,
retrospective analysis, survey-specific index comparison, prediction-grid
construction, and diagnostic/result plotting. Functions are generic (nothing is
hard-coded to a species or region) and may later be adopted into `sdmTMB`
itself. Cite the developer when you reuse them.

Maps are drawn on [ggOceanMaps](https://mikkovihtakari.github.io/ggOceanMaps/)
basemaps, which is the package's default map-plotting tool.

## Core conventions

- **Coordinates**: model `X`/`Y` are expected in **kilometres** (the `sdmTMB`
  convention). Helpers multiply by `coord_multiplier` (default `1000`) to get
  CRS metres for `sf`/mapping.
- **Attach the package** with `library(sdmTMBexperiments)` — this attaches
  `ggOceanMaps` (a `Depends`) so basemaps find their bundled land data.
- **Suggested packages** some functions need: `concaveman` (survey regions),
  `blockCV` (`sdmTMB_mesh_cv()`), `inlabru` (`plot_mesh()`), `DHARMa`,
  `ggspatial` (`bubble_map()`), `cli` (progress messages).

## Minimal working examples

```r
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

### Survey comparison (uses the bundled `sebastes` data)

`compare_surveys()` fits a separate model per survey series, builds a
survey-specific prediction grid from each survey's spatial footprint, and
compares to a compiled reference index.

```r
data(sebastes)
region <- make_survey_prediction_region(subset(sebastes, cruiseseries == "EggaN"),
                                        crs = 32633)
grid <- make_prediction_grid(region, resolution = 20)
```

## Common pitfalls

1. **`X`/`Y` are in km.** Passing metres will place data in the wrong location.
2. **Attach, don't just `::`.** Map functions rely on `ggOceanMaps` being
   attached (it is, via `library(sdmTMBexperiments)`). Using `::` on a bare
   namespace can fail with `object 'dd_land' not found`.
3. **Bias correction is slow.** `bias_correct = FALSE` is the default; turn it on
   only for final runs.
4. **`compare_surveys(type = "spatial")`** needs a `compiled_model`; without one,
   spatial differences are skipped.

## Where to find more

- Function reference: <https://deepwaterimr.github.io/sdmTMBexperiments/reference/>
- Issues: <https://github.com/DeepWaterIMR/sdmTMBexperiments/issues>

## For agents developing the package

If you are helping work on the package source (not just using it), start with
[CLAUDE.md](CLAUDE.md) and the [`memory/`](memory/) folder. `memory/` is the
project's persistent memory; [`memory/MEMORY.md`](memory/MEMORY.md) is the index.

**Do not put personal information into `memory/`, `AGENTS.md`, or `CLAUDE.md`.**
The whole repository is public on GitHub. Never commit absolute local paths
(e.g. `/Users/<name>/...`), machine-specific filenames, or contact details
beyond the maintainer's public package metadata; use placeholders such as
`~/...` or `path/to/your/file`.
