# Personal Changelog

Version numbers below belong to `signup2k/openclip`. Earlier upstream release notes are preserved
in [Historical upstream changelog](docs/upstream/historical-changelog.md).

## v1.0.0 — Unreleased personal baseline

- Start independent personal development; upstream releases are reviewed and selectively ported.
- Remove the upstream app-update feed and signing key. Personal builds use manual installation.
- Preserve the local selection, copy-input protection, and explicit preview work already in the working tree.
- Use `personal-v*` Git tags for future personal releases; historical upstream `v*` tags remain unchanged.

Selected v1.4.0 fixes have been ported: paste-probe deadline recovery, bounded AX menu traversal,
accurate build/launch paths, Show Icon persistence, and action editor row reuse. Added the AI
selection-as-data prompt without changing personal presets. Larger popup features remain deferred.
See the [port record](docs/upstream/v1.4.0-assessment.md) for sources and validation.
