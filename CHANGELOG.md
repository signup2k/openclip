# Personal Changelog

Version numbers below belong to `signup2k/openclip`. Earlier upstream release notes are preserved
in [Historical upstream changelog](docs/upstream/historical-changelog.md).

## v1.0.1 — Build 10

- Shrink the radial menu to 144pt and stabilize its first frame and shared-display edge placement.
- Show enabled AI presets in both popup layouts from the first selection. Actions preferences save
  their order and open the prompt editor directly. Older orders reuse the saved AI Tools position.
- Update Explain to request search/analysis followed by a concise Chinese ELI25 explanation.
- Add a cursor-centered radial popup menu with eight sectors per page, search in the center,
  and a Horizontal / Radial switch in Appearance preferences.
- Detect single-click auto-selection in native address/search fields without simulating Copy.
- Keep browser native editors separate from page selection and rich-text clipboard enrichment.
- Do not restore archived clipboard content after a retrieval task is cancelled.
- Resolve `browser-script` selection rules through AX web selection and keyboard copy; the
  legacy browser AppleScript path is removed.
- Trim defensive code and cut the test suite from 1,140 to 577 behavior-level tests.
- Bind saved cloud API keys to their provider and endpoint origin for model discovery and inference.
- Keep Copy available on AI result cards when Paste can no longer target the original selection.
- Run AI presets from the action-search hotkey.
- Hide AI presets in search and block invocation when AI Tools is off.
- Require a radial right-click to start and end on the same sector.
- Keep group sub-bars outside the radial menu when they flip at a screen edge.
- Capture the complete stdout and stderr from finished shell actions.
- Stop delayed menu-copy lookups from pressing Copy after clipboard capture ends.
- Keep the current loading action’s cancel control available when an older run finishes.
- Ignore Return and Shift+Return on result error cards.
- Reset model discovery when the cloud or Ollama configuration changes.
- Preserve the saved API key and show an error when deletion fails.
- Update saved Explain presets that still use the old default prompt.
- Localize the error shown when an AI provider returns no response.

## v1.0.0 — Personal baseline (build 9)

- Start independent personal development; upstream releases are reviewed and selectively ported.
- Remove the upstream app-update feed and signing key. Personal builds use manual installation.
- Preserve the local selection, copy-input protection, and explicit preview work already in the working tree.
- Use `personal-v*` Git tags for future personal releases; historical upstream `v*` tags remain unchanged.

Selected v1.4.0 fixes have been ported: paste-probe deadline recovery, bounded AX menu traversal,
accurate build/launch paths, Show Icon persistence, and action editor row reuse. Added the AI
selection-as-data prompt without changing personal presets. Larger popup features remain deferred.
See the [port record](docs/upstream/v1.4.0-assessment.md) for sources and validation.
