# Workspace Agents Guidance

This file is the shared workspace guidance for tools and contributors working in this repository.
It captures repo-specific rules that should stay consistent across GitHub Copilot, Claude Code, and manual development.

## Release Versioning

Use semantic versioning for release labels in this repository.

- Major (`X.0.0`): breaking changes
- Minor (`1.X.0`): new backward-compatible features
- Patch (`1.0.X`, `1.1.X`, etc.): bug fixes, small corrections, and non-breaking maintenance

### Established Release Milestones

- April 9, 2026 Asphalt Core Locator milestone = `1.0.0`
- April 23, 2026 lab test forms milestone = `1.1.0`
- Next bug-fix release after April 23, 2026 = `1.1.1`

Maintain this section as a rolling record of the last 3 successful pushes.
After each successful push, replace the oldest entry so this list always reflects the newest 3 pushed versions.

### Practical Rule

- Do not increment the version for every commit or push.
- Increment the version only for release-worthy milestones.
- If a change adds a new backward-compatible feature, bump the minor version.
- If a change only fixes bugs or polishes existing behavior, bump the patch version.
- If a change breaks compatibility, bump the major version.
- Do not use shorthand like `1.3` when you mean `1.0.3`; `1.3` conventionally means `1.3.0`.

## Production Python Dependency Parity

If Python dependencies are required for application behavior, keep every production build path aligned.

- Install Python dependencies from `python/requirements.txt` in every production Docker path.
- Do not assume one Dockerfile or deploy script represents all production environments.
- If local works but production fails for Python-backed features, verify dependency parity before debugging higher layers.

## Parent-Page Data Loading Rule

When surfacing linked child records on a parent page, use real associations and preload the data in controllers or query objects.

- Do not query child records per row or per partial in the view.
- Prefer a single parent-scoped query plus grouping in memory when rendering nested sections.
- If a relationship is important to the UI, add or verify the association in the model layer.

## Report Show Page Section Rule

For substantial additions to report show pages, follow the existing lazy section pattern instead of embedding large new sections inline.

- Extend the `show_section` pipeline in `ReportsController` when adding a new report card.
- Add preload coverage through `section_includes` for the new section.
- Keep heavy or data-rich report sections lazy-loaded to avoid bloating initial page render.
