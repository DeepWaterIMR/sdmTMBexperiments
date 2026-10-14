# Known fixes

These functions were originally ported from project-local helpers in a
redfish assessment repository (fixes #1-12 below were found during that
extraction); later fixes (#13+) were found afterwards, e.g. while writing
examples/vignettes or from user review. Each is also noted in `NEWS.md`.

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
   `mesh$loc_xy` by data rows, which is invalid for an SPDE mesh. An earlier fix
   reused the original `sdmTMBmesh` unchanged, but that object still stores one
   row per *fitted observation* (`loc_xy`, `A_st`, `sdm_spatial_id`), so passing
   it through verbatim broke as soon as peeling dropped rows: `sdmTMB()` errored
   with "Number of x-y coordinates in `mesh` does not match `nrow(data)`" for
   any peel beyond the terminal one (this was silently swallowed by the
   crashed-model fallback, so peels 1+ always returned `NA`/`"crashed"` index
   rows). Fixed by rebuilding the `sdmTMBmesh` wrapper for the peeled data via
   `make_mesh(peel_data, xy_cols = object$spde$xy_cols, mesh = object$spde$mesh)`,
   which reuses the original INLA mesh geometry/triangulation but remaps it to
   the smaller peeled dataset.
7. **Retro `nyears` overflow** — `nyears` is clamped to the number of fitted
   years so `years` can no longer contain `NA`.
8. **Fixed-effects plotting** — the source repo's conditional-effects figure had
   a 4-panel branch that duplicated a panel. Not reproduced: `plot_fixed_effects()`
   is a generic tidy coefficient plot (via `sdmTMB::tidy()`), which avoids that
   layout entirely.
9. **`compare_surveys()` CRS inheritance** — when `object_crs = NULL`, the CRS
   was inherited from `compiled_model$spde$mesh$crs` guarded only by
   `is.null()`. But `sdmTMB::make_mesh()` has no `crs` argument, so a normally
   built mesh carries `crs = NA` (an `sf::st_crs(NA)` object), not `NULL` — the
   guard never fired, an `NA` CRS silently propagated through `plot(...,
   type = "spatial")`, and `ggOceanMaps::basemap()` errored deep in its call
   stack with `"missing value where TRUE/FALSE needed"` (from
   `sf::st_is_longlat()` on `NA`-CRS data). Fixed by also checking
   `is.na(sf::st_crs(mesh_crs))`. In practice this means CRS auto-inheritance
   from `compiled_model` essentially never worked for meshes built the normal
   way — always pass `object_crs` explicitly.
10. **`plot_prediction_map()` silently grey-ing out cells** — the fill scale
    was hardcoded to `limits = c(0, NA)` (density is non-negative), but the
    function accepts whatever `predict(fit, newdata = ...)` output it's given.
    `predict.sdmTMB()` defaults to the *link* scale (e.g. log density for a
    log-link family), which is frequently negative; any cell whose value fell
    outside `[0, NA]` was rendered blank/grey by ggplot with no error or
    indication why. An intermediate fix added a warning for negative input
    values, but that still assumed response-scale semantics. Properly fixed by
    removing the hardcoded limit: a new `fill_limits` argument (default
    `NULL`) lets the scale range come from the data by default, with a warning
    only if the caller explicitly sets `fill_limits` in a way that clips data.
    Also renamed `trans` to `transform` (default `"identity"`, was `"sqrt"`),
    matching ggplot2's `continuous_scale()` (`trans` is deprecated there).
11. **`compare_meshes()` missing `mean_pr_diff`** — `compare_models()` and
    `compare_surveys()` both group `.pred_diff_base()`'s per-cell/per-year
    output and add `mean_pr_diff = 100 * mean(diff) / mean(ref_est)`, a
    ratio-of-means percent difference that's far less sensitive to individual
    low-abundance years than `pr_mean` (a mean-of-ratios: `mean(pr_diff)`,
    each year divided by *that year's own* reference value). `compare_meshes()`
    never computed this column, so `plot.sdmTMB_mesh_comparison(type =
    "spatial", spatial_response = "mean_pr_diff")` silently mapped `NA`
    everywhere (documented as unsupported, but easy to trip over since the
    other two comparison functions do support it). Fixed by adding the same
    grouped `mean_pr_diff` computation to `compare_meshes()`.
12. **`compare_models()`/`compare_meshes()` had the same CRS-inheritance bug as
    #9** — only `compare_surveys()` had been fixed. `compare_models()` silently
    fell back to `object_crs = NULL` (its `!is.null(mesh$crs)` guard never
    fired since `mesh$crs` is `NA`, not `NULL`); `compare_meshes()` had the
    same silent-`NA`-CRS problem #9 describes. Caught by actually running
    `plot.sdmTMB_mesh_comparison()`'s roxygen example end-to-end (added while
    writing the package's `@examples`/`\dontrun{}` coverage, see
    [examples-policy.md](examples-policy.md)) — every prior example for these
    two functions happened to pass `object_crs` explicitly, so this had never
    surfaced. Fixed with the same `is.null() || is.na(sf::st_crs(...))` guard
    as #9.
13. **`sdmTMB_mesh_cv()` `deltaNLL`/`deltaNLL_pr` had the wrong sign** —
    `sum_loglik` (from `sdmTMB::sdmTMB_cv()`) is a log-likelihood (log
    predictive density), where *higher* (more positive) is better. The
    `deltaNLL` columns were computed straight from `sum_loglik` without
    flipping the sign, so despite the "NLL" name they were really a
    delta-log-likelihood: `<= 0`, with `0` (max) as the best cutoff — backwards
    from the AIC-like convention (`deltaAIC`: `>= 0`, `0`/min = best) used
    elsewhere in the same table. Fixed by negating `sum_loglik` first, so
    `deltaNLL`/`deltaNLL_pr` are now `>= 0` with `0` (min) indicating the
    best-fitting mesh, consistent with `deltaAIC`.
14. **Vignette's `compare_surveys()` example fit `density` as the response
    while also passing a `swept_area` offset** — `sebastes$density` is already
    `biomass / swept_area` (see `?sebastes`), so adding a `swept_area` log-offset
    on top double-corrects for effort: the model compensates by fitting
    intercepts near `mean(density) / mean(swept_area)` (~8,000-12,000, vs. an
    observed median density of ~90), and predicting onto the grid (offset = 0,
    i.e. "at 1 unit of swept area") then inflated the index by roughly
    `1 / mean(swept_area)` (~90x) on top of that. Separately, the vignette's
    `area` argument (`20^2`, i.e. plain km²) didn't convert to
    `swept_area`'s units (square nautical miles; `1 km² ≈ 0.2916 nmi²`), a
    second, smaller unit mismatch. Combined, the compiled index came out
    ~1000x too high (tens of billions of kg instead of hundreds of kt). Fixed
    by fitting `biomass` (raw catch) as the response instead of `density`, and
    computing `area` as `(resolution_km / 1.852)^2` (nmi²). Not a bug in
    `compare_surveys()` itself — it's generic and correctly offsets whatever
    formula/response it's given — this was purely an example/vignette
    modelling mistake, but an easy one to repeat with real swept-area survey
    data, so it's recorded here too.
15. **`.spatial_diff_map()`'s diverging fill-scale breaks could be
    crowded/illegible, or mislabelled "Percent anomaly" for an absolute
    response** — Two related issues. (a) Break points were 6 values evenly
    spaced in signed-sqrt space between the limits, independently rounded to
    `break_rounding`; nothing guaranteed the true limits or `0` were exactly
    among them, and for skewed/extreme ranges (see #14 before its fix) the
    interior breaks could round to near-duplicate, visually overlapping
    values. Fixed with `.diverging_breaks()`: limits and `0` (when spanned)
    are always kept exact, additional breaks are added only if at least
    `span/n` apart (de-crowding), and labels use
    `scales::label_number(scale_cut = scales::cut_short_scale())` (e.g.
    `"-9.2K"` not `"-9200"`) since short labels need less spacing to avoid
    collision. (b) `compare_models()`/`compare_surveys()`'s `plot()` methods
    unconditionally relabelled the fill legend `"Percent anomaly"` (or
    `"{fill_prefix}\npercent anomaly"`), even when `spatial_response = "mean"`
    (an absolute density difference, not a percent) — `compare_meshes()` never
    had this override and was already correct. Fixed by giving
    `.spatial_diff_map()` its own `fill_prefix` argument (reusing its existing
    percent-vs-absolute conditional) and only applying the "percent anomaly"
    override in the two callers when `spatial_response` is actually one of the
    percent-based options.
16. **Index-plot `plot.margin` fix was silently undone by theme ordering** —
    while fixing the cropped rightmost-year x-axis label (`coord_cartesian(expand
    = FALSE)` puts the last data point exactly on the panel edge), the shared
    `.index_axis_layers()` helper's `theme(plot.margin = ...)` was added
    *before* the subsequent `theme_classic()`/`theme_bw()` call in all five
    index-plot functions. `theme_classic()`/`theme_bw()` are *complete* themes
    that replace the whole theme when added with `+`, silently discarding any
    partial `theme()` set earlier — only a `theme()` call *after* the complete
    theme survives. Fixed by moving `.index_axis_layers()` after the complete
    theme call in `compare_models()`, `compare_meshes()`, `compare_surveys()`,
    `sdmTMB_retro()` and `plot_index()`.
17. **Index-plot x-axis could show decimal year breaks** — `.index_axis_layers()`
    used `scales::pretty_breaks(n = 10)` for the x-axis, which wraps
    `base::pretty()`; for a short year range (e.g. 2020-2025), `pretty()` picks
    a sub-1 step (`0.5`) to hit closer to the target break count, showing
    `2020.0`, `2020.5`, etc. for what is always whole-number year data. Fixed
    with `.year_breaks()`: when the axis range itself is whole numbers, it
    searches for the largest `n_try <= n` whose `pretty()` breaks are all whole
    numbers (falling back to `scales::extended_breaks()` only if the range
    itself isn't whole numbers, e.g. a model using fractional years).
18. **`R CMD check`/CI failed entirely on dependency resolution** — `sdmTMBextra`
    was listed in `Suggests` (only referenced in one roxygen `[sdmTMBextra::
    add_barrier_mesh()]` doc link, never actually used in code), but it's a
    GitHub-only package (`pbs-assess/sdmTMBextra`), not on CRAN/Bioconductor.
    `pak` (used by both `.github/workflows/R-CMD-check.yaml` and
    `pkgdown.yaml` via `setup-r-dependencies`) can only resolve `Suggests`
    from public repos, so both workflows failed at the dependency-resolution
    step before running any actual check — "Can't find package called
    sdmTMBextra." Fixed by removing it from `Suggests` and changing the
    roxygen link to a plain code-font mention (`sdmTMBextra::
    add_barrier_mesh()`, no `[...]` link) so it doesn't need to resolve.
    While investigating, `devtools::check()` also surfaced three unrelated,
    pre-existing issues, now fixed: a non-ASCII `R²` character in a `sprintf()`
    string in `compare-surveys.R` (replaced with a `\u00B2` escape — CRAN
    requires ASCII-only source outside comments); an undocumented `...`
    argument in `plot.sdmTMB_prediction_grid()`; and a stray `Rplots.pdf` that
    had been accidentally committed at the repo top level (added to
    `.gitignore`/`.Rbuildignore`).

19. **`.safe_index()` only survived a crashed *model*, not a crashed
    *extraction*.** `sdmTMB::get_index_split()` can throw for a model that
    fitted perfectly well — a `newdata` grid that does not overlap the fitted
    coordinates, a year present in the grid but not in the model, an `nsplit`
    that lands on an empty subset. Because every comparison function summarises
    many models in one figure, and those figures are drawn at the end of renders
    measured in hours, a single unlucky model aborted the whole plot with an
    opaque tibble recycling error from deep inside `predict.sdmTMB()`. Found by
    smoke-testing the new selection index plot against a deliberately mismatched
    grid. Now wrapped in `try()`: warns (naming the model when the caller passes
    a `label`) and returns a `type = "crashed"` row, the same fallback a crashed
    model already got.

## Portability change
The source repo used `future::multicore`; the package uses the portable
`future::multisession` so it works on Windows and in R CMD check.
