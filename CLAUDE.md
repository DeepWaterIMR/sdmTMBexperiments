# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) and other AI agents
when working with code in this repository.

For AI assistants helping users *use* sdmTMBexperiments (not work on its source),
see [AGENTS.md](AGENTS.md).

## Package overview

sdmTMBexperiments is an R package of experimental helper functions for fitted
[sdmTMB](https://github.com/sdmTMB/sdmTMB) models: model/mesh/survey comparison,
retrospective analysis, prediction-grid construction, and diagnostic plotting.
It is generic (no species/region assumptions) and doubles as a showcase and a
staging ground for methods that may later be adopted into `sdmTMB`.
Documentation: <https://deepwaterimr.github.io/sdmTMBexperiments/>

## Project memory

The [`memory/`](memory/) folder is this project's persistent memory: purpose,
architecture, naming conventions, example-data provenance, the audit trail of
bug fixes, and the roadmap. **Read it before starting work** and **keep it up to
date**. [`memory/MEMORY.md`](memory/MEMORY.md) is the one-line-per-entry index —
start there.

**Do not put personal information into the memory files, this file, or
`AGENTS.md`.** The whole repository (including `memory/`) is public on GitHub.
Never commit absolute local paths (`/Users/<name>/...`), machine-specific
filenames, dataset versions tied to one computer, or contact details beyond the
maintainer's public package metadata. Use placeholders: `~/...`,
`path/to/your/file`, `<your-data-folder>`.

## Common commands

```r
devtools::load_all()      # load for interactive development
devtools::document()      # regenerate NAMESPACE + man/ (roxygen2)
devtools::test()          # run testthat tests
devtools::check()         # R CMD check
pkgdown::build_site()      # build the website (see Examples policy)
```

```bash
R CMD build .
R CMD check sdmTMBexperiments_*.tar.gz --as-cran
```

CI runs R CMD check (macOS/Windows/Ubuntu; devel/release/oldrel-1) and deploys
the pkgdown site via `.github/workflows/`.

## Architecture

### Naming conventions (align with sdmTMB)
snake_case functions; thematic kebab-case source files; `sdmTMB_`-prefixed names
for model-level operations (`sdmTMB_retro()`, `sdmTMB_mesh_cv()` mirror
`sdmTMB::sdmTMB_cv()`); argument names reused from `sdmTMB` (`bias_correct`,
`level`, `area`, `newdata`, `mesh`, `time`, `offset`); the parallel seed argument
is `future_seed` everywhere. See [memory/naming-conventions.md](memory/naming-conventions.md).

### Shared internals ([R/utils.R](R/utils.R))
- `.setup_parallel()` / `.set_future_memory()` — install a portable
  `multisession` plan and size `future.globals.maxSize`; callers restore the old
  plan with `on.exit()`.
- `.safe_index()` — `get_index_split()` with a crashed-model fallback + `cv`.
- `.pred_diff_base()` — per-cell prediction difference between a model and a
  reference (carries `depth` when present).
- `.spatial_diff_map()` — the shared ggOceanMaps spatial-difference map used by
  all three comparison `plot()` methods.
- `.safe_brewer()` — palette-safe wrapper around RColorBrewer for any `n`.

### Function families and S3 classes
- Model selection ([R/model-selection.R](R/model-selection.R)):
  `sdmTMB_selection()` → `sdmTMB_selection` (+ `print`/`plot`), built on
  `selection_frame()` (identical records), `sdmTMB_cv_summary()`
  (per-observation hold-out log-likelihood), `add_aic_weights()` and
  `best_candidate()` (look the winner up in the column, never by row position).
- Comparisons return `sdmTMB_model_comparison`, `sdmTMB_mesh_comparison`,
  `sdmTMB_survey_comparison`, each with a `plot()` method (index / spatial, and
  scatter for surveys).
- `sdmTMB_retro()` → `sdmTMB_retro` (+ `plot`); `sdmTMB_mesh_cv()` →
  `sdmTMB_mesh_cv` (+ `plot`).
- `mohns_rho()` is the shared engine for the Mohn's-rho annotations.
- Grid helpers: `make_survey_prediction_region()` (concave hull),
  `make_prediction_grid()` (regular grid over a region), and the internal
  `.clip_points_to_region()` used by `compare_surveys()`.
- Plotting helpers ([R/plot.R](R/plot.R)): `plot_mesh()`,
  `plot_prediction_map()`, `plot_random_field()`, `plot_index()`,
  `plot_fixed_effects()`, `plot_variance_partitioning()`,
  `plot_prediction_histogram()`, `plot_residual_qq()`; plus `bubble_map()`.

### Dependency policy
`ggOceanMaps` is a **Depends** (the default map tool; its bundled `dd_land` is
only visible when attached). Heavy/optional packages are `Suggests`, guarded with
`requireNamespace()`: `concaveman`, `blockCV`, `inlabru`, `DHARMa`, `ggspatial`,
`cli`, `ps`, `memuse`, `RColorBrewer`, `sdmTMBextra`.

### Example data
`data/sebastes.rda` is a public beaked-redfish subset built by
[data-raw/sebastes.R](data-raw/sebastes.R). See
[memory/example-data.md](memory/example-data.md).

## Provenance
Ported from project-local helpers in a redfish assessment repository, with bug
fixes applied during extraction — see [memory/known-fixes.md](memory/known-fixes.md).
