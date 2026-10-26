---
name: versioning
description: Every commit bumps Version and Date in DESCRIPTION and adds a matching NEWS.md heading
metadata:
  type: feedback
---

Every commit bumps `Version` in `DESCRIPTION` and sets `Date` to the commit date,
as in the maintainer's other packages (ggOceanMaps, ggFishPlots, RstoxUtils).
By default each commit is one patch step (`x.y.z+1`), even one that adds a new
function family; minor/major bumps only when the maintainer asks (0.1.0 -> 0.1.2
counted the model-selection commit as 0.1.1 and its fix as 0.1.2). `NEWS.md` gets a
`# sdmTMBexperiments x.y.z` heading (not "development version"), with a dated
one-line summary under it. Also update the version string in `README.md` (the
knitted citation) and [[project_overview]].

**Why:** the maintainer tracks installed versions against commits; a commit that
leaves the version unchanged makes `packageVersion()` useless for telling a
fixed install from an unfixed one.

**How to apply:** the shared `.githooks/pre-commit` updates `Version` and `Date` on
ordinary commits. Keep the matching `NEWS.md` heading and README citation in the same
commit. Enable the repository hook with `git config core.hooksPath .githooks`; never bypass
it to avoid versioning.
