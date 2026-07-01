# No personal information in public files

This repository — including `memory/`, `AGENTS.md`, and `CLAUDE.md` — is public
on GitHub. Any agent editing these files must keep them free of personal or
machine-specific information.

**Never commit:**
- Absolute local paths (`/Users/<name>/...`, `C:\Users\...`, cloud-sync paths).
- Machine-specific filenames or dataset versions tied to one computer.
- Contact details beyond the maintainer's public package metadata (the
  `Authors@R` block in `DESCRIPTION`).
- Private or embargoed data. The bundled `sebastes` data is a public subset with
  documented provenance; do not add non-public data.

**Use placeholders instead:** `~/...`, `path/to/your/file`, `<your-data-folder>`.

When porting code from a private/project repository, strip project-specific
paths, species/survey names, and assumptions before committing (see
[project_overview.md](project_overview.md) on the scope boundary).
