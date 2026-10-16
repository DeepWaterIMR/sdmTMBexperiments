# Roadmap

## Near term
- Expand test coverage (currently `pcod` + `sebastes` smoke/behaviour tests).
- Consider a `barrier`-mesh path for `compare_meshes()` (currently plain meshes
  only; the source repo had commented-out `sdmTMBextra::add_barrier_mesh()`).

## Function ideas
- Optional depth-filtering in `make_prediction_grid()` via a pluggable
  `depth_fun` (already supported); document a ggOceanMaps-based example.
- A `print()` method for the comparison classes summarising sanity/CV ranges.
- `plot_prediction_map(type = "anomaly")` (per-year anomaly from the mean).

## Upstream adoption
Several functions are candidates for `sdmTMB` itself (e.g. `sdmTMB_retro()`,
`compare_meshes()`, `mohns_rho()`). Keep the API and argument names aligned with
`sdmTMB` so adoption is low-friction.

## CRAN readiness
- Ensure examples that fit models are wrapped in `\donttest{}` (see
  [examples-policy.md](examples-policy.md); CI overrides
  `_R_CHECK_DONTTEST_EXAMPLES_` so these stay fast in `R CMD check` while still
  rendering on the pkgdown site).
- Keep bundled data < ~1 MB.
- Target `R CMD check --as-cran` with 0 errors / 0 warnings; document acceptable
  notes.
- `ggOceanMaps` is a Depends and is on CRAN, which keeps the dependency chain
  CRAN-installable.
