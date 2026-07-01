# Known fixes (applied while porting)

These functions were ported from project-local helpers in a redfish assessment
repository. The following bugs/fragilities were fixed during extraction; each is
also noted in `NEWS.md`.

1. **Unassigned future memory option** — the low-RAM branch computed a value for
   `future.globals.maxSize` but never assigned it. Centralised and fixed in
   `.set_future_memory()` (`R/utils.R`).
2. **`mean_pr_diff` formula** — was
   `100 * (diff / mean(ref_est) - 1)` (per-row, dimensionally wrong; `diff` is
   already `pred - ref`). Corrected to a proper grouped percent difference:
   `100 * mean(diff) / mean(ref_est)` per grid cell. Applied in
   `compare_models()` and `compare_surveys()`.
3. **Seed argument naming** — `compare_models()` used `future.seed`; unified to
   `future_seed` across all functions.
4. **Column checks** — `compare_meshes()` now validates that `newdata` and the
   model data contain `X`/`Y` and fails with a clear message.
5. **RColorBrewer palette overflow** — `plot.sdmTMB_mesh_comparison()` used
   `brewer.pal(n, "Set1")`, which errors outside `n ∈ [3, 9]`. Replaced with the
   palette-safe `.safe_brewer()` (clamps small `n`, interpolates large `n`).
6. **Retro mesh mutation** — `sdmTMB_retro(refit_meshes = FALSE)` mutated
   `mesh$loc_xy` by data rows, which is invalid for an SPDE mesh. Now reuses the
   original mesh unchanged.
7. **Retro `nyears` overflow** — `nyears` is clamped to the number of fitted
   years so `years` can no longer contain `NA`.
8. **Fixed-effects plotting** — the source repo's conditional-effects figure had
   a 4-panel branch that duplicated a panel. Not reproduced: `plot_fixed_effects()`
   is a generic tidy coefficient plot (via `sdmTMB::tidy()`), which avoids that
   layout entirely.

## Portability change
The source repo used `future::multicore`; the package uses the portable
`future::multisession` so it works on Windows and in R CMD check.
