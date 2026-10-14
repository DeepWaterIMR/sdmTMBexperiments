# Memory index

This folder is the project's persistent memory. Each file holds one topic; this
index is the one-line-per-entry table of contents — skim it, then open what you
need.

**Do not put personal information in these files.** This folder is public on
GitHub. No absolute local paths (`/Users/<name>/...`), machine-specific
filenames, dataset versions tied to one computer, or contact details beyond the
maintainer's public package metadata. Use placeholders: `~/...`,
`path/to/your/file`. See [no-personal-info.md](no-personal-info.md).

## Project

- [Project overview](project_overview.md) — purpose, scope boundary, version, dependencies
- [Architecture](architecture.md) — shared internals, function families, S3 classes
- [Naming conventions](naming-conventions.md) — sdmTMB alignment decisions + name map
- [Example data](example-data.md) — `sebastes` provenance and regeneration
- [Known fixes](known-fixes.md) — audit trail of bugs found and fixed (porting-era and later)
- [Roadmap](roadmap.md) — future work and CRAN readiness
- [Versioning](versioning.md) — bump Version + Date in DESCRIPTION and a NEWS heading with every commit
- [Examples policy](examples-policy.md) — `\donttest{}` (pkgdown runs it by default) + `_R_CHECK_DONTTEST_EXAMPLES_: false` in CI to keep `R CMD check` fast

## Who I work with

- [User profile](user_profile.md) — the package author/maintainer
- [No personal info in docs](no-personal-info.md) — keep local paths/private data out of public files
