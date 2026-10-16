# Roxygen `@examples` policy

Every exported function must have `@examples`. Almost all of them fit an
`sdmTMB::sdmTMB()` model, which is slow (seconds to tens of seconds) — too slow
to run on every `R CMD check`, but they should still execute on the pkgdown
reference pages so the docs show real output.

## The mechanism

- Wrap examples in `\donttest{}`, not `\dontrun{}`.
- pkgdown runs `\donttest{}` examples **by default** (`build_reference()`/
  `build_site()` have no separate switch for it — only a `run_dont_run`
  argument, default `FALSE`, that controls `\dontrun{}`). So plain
  `pkgdown::build_site()` (no extra arguments) renders real output for these
  examples. `\dontrun{}` was tried first, but that requires every local/CI
  pkgdown invocation to remember to pass `run_dont_run = TRUE`, and a plain
  `build_site()` silently shows `if (FALSE) { ... }` placeholders instead of
  running the code — easy to forget, so the site could go stale without
  anyone noticing.
- `R CMD check --as-cran` normally *does* execute `\donttest{}` blocks (it sets
  `_R_CHECK_DONTTEST_EXAMPLES_=TRUE`), which would defeat the purpose here:
  running model-fitting examples on every check, across 5 CI jobs
  (macOS/Windows/Ubuntu × devel/release/oldrel-1). To keep CI fast, this
  repo's `.github/workflows/R-CMD-check.yaml` explicitly sets
  `_R_CHECK_DONTTEST_EXAMPLES_: false` in the job `env:`. R only falls back to
  `--as-cran`'s default when the variable is *unset*
  (`tools:::.check_packages`: `Sys.getenv("_R_CHECK_DONTTEST_EXAMPLES_",
  "NA")`, then uses `as_cran` only if that's `"NA"`), so an explicit `false`
  wins even under `--as-cran`. This is a checked fact, not folklore — verified
  by reading `tools:::.check_packages` directly.
- Because pkgdown always runs `\donttest{}`, every block must be genuinely
  self-contained and correct — not a placeholder referencing an undefined
  variable (a prior version of `sdmTMB_mesh_cv()`'s example did exactly that
  with a bare `fit`).
- `sdmTMB` is an Imports dependency, not Depends, so `library(sdmTMBexperiments)`
  does **not** attach it. Examples must fully qualify sdmTMB symbols
  (`sdmTMB::sdmTMB()`, `sdmTMB::pcod`, `sdmTMB::make_mesh()`, ...) — bare
  `pcod`/`make_mesh()` will fail with "could not find function". (S3 generics
  like `predict()`/`plot()` dispatch fine unqualified since the S3 method table
  doesn't require the namespace to be attached.)

## The "1-2 central" exceptions

`mohns_rho()` and `plot_index()` are the two functions with plain, unwrapped
`@examples` — they're pure data-frame operations with no model fitting and no
I/O, so they cost nothing to run on every `R CMD check` and give a small amount
of real regression coverage. Everything else is `\donttest{}`.

## History

Originally used `\dontrun{}` with `run_dont_run = TRUE` passed explicitly to
every pkgdown build (locally and in `.github/workflows/pkgdown.yaml`), on the
theory that `\dontrun{}` is *never* executed by `R CMD check` regardless of
flags, which is simpler to reason about than an env-var override. Switched to
`\donttest{}` + the `_R_CHECK_DONTTEST_EXAMPLES_: false` override because a
plain `pkgdown::build_site()` (the natural thing to run locally) silently
skipped `\dontrun{}` examples — they rendered as `if (FALSE) { ... }` in
`docs/reference/*.html` with no error, which is easy to miss.
