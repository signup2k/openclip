# Known Debt & Current-State Realities

This file holds OpenClip's **current-state notes** — the places where the code has not yet
reached the target architecture. These change more often than the hard rules, so they are
tracked here rather than in `AGENTS.md`. Keep this file current when you touch any of these
areas; stale debt notes are worse than none.

---

## Settings Migration (UserDefaults → SettingsStore)

- The typed settings abstraction is `SettingsStore` + `SettingKey<T>` (see `Sources/Core/Settings/`).
  New settings code must route through it.
- **AI-config `@AppStorage` surface remains** (`AIServiceManager` keys), and `completionCopyToClipboard`
  / popup theme still read via `@AppStorage`, but the theme keys (`popupTheme`,
  `popupThemeColor`) now reference `SettingKey` definitions instead of raw literals. Migrating to
  `SettingsStore` is ongoing — **don't add new direct call sites.** (`startAtLogin` was consolidated
  onto `SettingKey.startAtLogin` — `LaunchAtLoginManager` persists through `DefaultSettingsStore`.)
- **Secrets live in SecretStore, not UserDefaults or macOS Keychain.** Sensitive credentials
  (the cloud AI API key and action secret options) use `SecretStore` (`~/.openclip/secrets.json`
  with 0600 POSIX permissions), replacing macOS Keychain to avoid code-signing ACL prompts.
  `AIServiceManager` looks up cloud keys by service and HTTP origin (scheme, host, and port).
  Model discovery and inference share that scope and follow same-origin redirects only. Migration
  binds the old SecretStore or UserDefaults key to the configured cloud service and origin.
  Preferences reports a failed save or deletion and keeps the persisted key displayed.
- **`isAppEnabled` is consolidated** onto `SettingKey.isAppEnabled` — status bar, hotkey gate, and
  the Preferences toggle all read/write through `DefaultSettingsStore`. Builtin store-backed actions
  (`CalculateAction`, `CalendarAction`, `SearchAction`) accept an injected `SettingsStore` via
  `BuiltinRegistry.makeCoreBuiltins(settingsStore:)`.
- **Menu bar visibility is store-backed and reversible.** `SettingKey.showMenuBarIcon` defaults to
  true. `StatusBarController` removes/recreates its `NSStatusItem` immediately when the General-tab
  toggle changes, while reopening the running app presents Preferences so a hidden icon can be
  restored without terminating OpenClip.
- **`ActionConfigSheet` is gone** (dead code — zero presenting call sites; its `useText` keys were
  write-only). Removing it also dropped the only UI that wrote `SettingKey.searchURL` /
  `SettingKey.calculateMode`; the actions still read those keys (defaults apply). Search-engine
  configurability is **restored** via the built-in Search action's preset picker in the Preferences
  edit sheet (`DynamicActionConfigView` — Google / DuckDuckGo / Kagi / Brave / Bing / Ecosia /
  Custom), which writes the option-store key `action.builtin.search.option.url`
  (`SearchEnginePreset` in Core holds the curated catalog); calculate-result-mode still has no
  Preferences surface.
  `ConfigurableAction` keeps only `preferenceIconName` (used by `tableIcon`/`rowIcon` icon fallback).
- **Dynamic action option keys** (`JavaScriptAction`, `AppleScriptAction`): the target pattern is
  `SettingKey<String>("action.<id>.option.<identifier>", defaultValue:)` via `SettingsStore`. The JS
  path already reads through the injected `optionStore` (`OpenClipJSHost` reads options read-only via
  `ActionOptionReading`); `AppleScriptAction` does not consume options today.

## Action Seams Already Implemented

- **Coordinator composition is done.** `ActionCoordinator.loadInitialState()` wires `ExtensionManager`
  to the registry via `onRegister`/`onUnregister`; the manager never calls `ActionRegistry.shared`
  directly. GUI-authored actions persist as manifest packages (via `CustomActionManifestWriter`);
  `custom_actions.json`/`CustomActionManager` are retired.
- **Shell runtimes share one executor.** `ScriptAction` script files and `CustomAction.shellScript`
  both run through `ShellProcessRunner` (one watchdog; `TimeoutFlag`/`OnceGate` live in
  `ShellProcessRunner.swift`) and translate stdout JSON via `ShellResultMapper`; `NSUserNotification`
  is gone (`.notify` is handled by the effect door via `UNUserNotificationCenter`). AppleScript
  joins the same executor via `AppleScriptRunner` (osascript subprocess), so no code runs
  `NSAppleScript` in-process anymore. Since the hang fix, the watchdog is a **GCD timer** (immune
  to Swift-concurrency-pool starvation) and pipe output is read via GCD `readabilityHandler` (never
  a blocking `readToEnd()`, so a stuck child can't permanently consume a cooperative thread), with
  stdin seeded and closed synchronously so a script reading stdin always sees EOF.
- **Delivery is resolved by `ActionResultDelivery`, not per-runtime translation.** Runtimes
  (`OpenClipJSHost.run`, `ShellResultMapper`, kind actions) return only raw results; implicitly
  returned text (JS string return, AppleScript output, shell stdout, text snippets) is emitted as
  `.text` and the paste-vs-copy/preview delivery decision (Select → Probe → Toast) is applied
  downstream from the user's per-click preference (General-tab `primaryClickBehavior`/
  `secondaryClickBehavior`) plus the action's declared `Action.delivery` (snapshotted per perform),
  the click intent, and the unified paste
  availability. The old `after` translator (the pre-refactor `after` orchestration step and its
  adapter) is **fully removed**. Async JS runs are guarded by the
  `TimeoutFlag` watchdog (60 s, same pattern as `ShellProcessRunner`) and cooperative Swift task cancellation.
- **Custom Action Groups use canonical IDs with dynamic materialization and strict $\ge 2$ member invariant.**
  User-defined action groups are defined via `ActionGroupDef` (`Sources/Core/Actions/ActionGroupDef.swift`),
  stored as JSON in `SettingKey.actionGroups`. Rather than rewriting action identifiers with virtual ID
  prefixes (e.g. `vgroup.<id>.<actionID>`), grouped actions retain their exact canonical IDs
  (`builtin.copy`, `com.user.ext.action`). `ActionRegistry` dynamically materializes `CustomGroupAction`
  (`Sources/Core/Actions/CustomGroupAction.swift`, conforming to `Action` and `SubActionProviding`)
  group rows, injecting them contiguously before their member actions in `actions`, while `SettingKey.actionOrder`
  strictly stores real, canonical IDs (including flat AI presets, excluding synthetic group headers). `ActionCoordinator`
  manages the full group lifecycle (`createGroup`, `updateGroup`, `ungroup`, `removeFromGroup`, `loadGroupDefs`,
  `pruneOrphans`), automatically enforcing the strict $\ge 2$ member invariant: when members are uninstalled
  or removed, any group dropping below 2 members is immediately dissolved. Availability resolution in
  `ActionRegistry.availableActions(for:)` maps canonical IDs to owning custom groups to hide member actions
  when their parent group is disabled or filtered out.

## Extension JS Module Runtime

- **Explicit JS previews use `openclip.preview(text)` → `.preview`.** They bypass the global text-delivery
  preference and render the native card in both normal and loading delivery paths, including sequences.
- **JS file scripts run in module mode (CommonJS).** A `javascript` action with `"script"` gets
  `require`/`module`/`exports`/`__dirname` and can split across local files; resolution is Node-style
  and contained to the package directory (`OpenClipModuleLoader` + `Constants.isPathSafe`), with
  `../`/symlink escapes, absolute paths, and bare/Node-builtin specifiers rejected. Inline
  `scriptCode` actions have no modules (byte-identical legacy behavior).
- **Third-party libraries live on the author side, not the host.** npm deps are bundled by the
  author with esbuild (`--platform=browser --target=es2020`) into `dist/main.js`; the host loader is
  **`.js`-only**, so TypeScript works only through the bundle path (`--with-npm` scaffold). Node
  builtins are rejected at build time by the esbuild platform — they can never run.
- **The consent gate has landed; capability *enforcement* remains future work.** Nothing runs until
  a package is enabled (fail-closed trust states `seen`/`trusted`/`revoked` behind a single
  trust-model consent surface), and a tamper-watch auto-disables a trusted package whose content
  hash changed at a later load. Still future: JIT permission prompts, gating `fetch`/`keyPress`/
  `runShortcut`, seeding `ManifestCapabilityGate`, and a JS honesty-scan acting on mismatches.
  Extensions still execute in-process with the app's user context; module containment bounds file
  reads but is not a privilege boundary.

## Presentation / Rule Holes

- **No `switch action.id` fallback remains.** `ActionCustomizationManager.tableIcon()` resolves via
  `ConfigurableAction.preferenceIconName` — the legacy block is gone. Keep it that way: never add
  id-string switches in presentation.

## Action-Search Palette & Popup Growth

- **A radial menu is available alongside the horizontal bar.** Appearance → Menu Layout stores
  `SettingKey.popupLayout` through `SettingsStore` (default `horizontal`; unknown values fall back).
  `PopupRadialLayout` caps pages at eight annular targets and shares geometry with the sector click
  shapes; actions and word completions both use the disk. A right-click must start and end on the
  same sector. A group hover sub-bar uses the sector for horizontal alignment and both disk edges
  for vertical placement. Placement centers on the release cursor
  and clamps both axes to the screen. The normal visible diameter is 144pt (previously 200pt),
  with symbol-only sectors and titles in the central hub. The controller fixes the footprint
  before the first layout and captures the target display, so reuse and late layout passes do not
  alter edge placement. Exact screen containment precedes the 2pt boundary tolerance.
  Transparent corners use the existing shadow click-through
  path. `PopupPanel.radialActionFrame` restores the original disk frame after search/content
  transitions, including hosting-view auto-resizes. Search, result cards, and group hover sub-bars
  keep their existing layouts; horizontal alignment/vertical position/width settings apply only
  to the bar. The maximum radial scale remains below the shared 300pt panel height cap.
- **AI presets are standalone rows in Preferences and both popup layouts.** `AIActionSync` registers
  them before the selection monitor and hotkeys can open the popup. Popup visibility uses the global
  AI switch and each preset's own toggle. Search includes individually disabled presets only while
  AI Tools is on. The controller starts AI presets before dismissing a hotkey-opened palette. `action.order` saves
  preset positions. Older orders without preset positions use the saved AI Tools position when one
  exists. Both click paths use the AI loading and streaming flow. The AI Tools row opens provider
  settings in Preferences, and each preset's gear opens `EditAIPresetSheet`. Group rows open scoped
  search on click and a transient sub-bar on hover. The Explain default
  requests search/analysis and a concise Chinese ELI25 explanation. On startup, saved Explain
  prompts that match a previous shipped default in any supported locale are updated in place.
  Customized prompts and toggle states are preserved.
- **Content-driven panel growth has no controller callback.** The `NSHostingView` auto-resizes the
  panel window top-anchored when its SwiftUI content grows (e.g. entering search mode);
  `onPreferenceChange`/`onContentSizeChange` never fires for this and `sizingOptions` has no effect.
  The only reliable hook is `PopupPanel.setFrame` (`PopupPanel.swift:42`): when
  `pinBottomEdgeOnResize` is set it keeps the bottom edge fixed so results-above-the-field growth
  never shoves the popup. The pin stays active through the search→bar collapse (Esc no longer jumps
  the popup) and is cleared by `show(for:)` (`PopupWindowController.swift:69`) and `hide()`
  (`:464`) before intentional placement.
- **Button-anchored search placement temporarily disables horizontal resize anchoring.** The
  explicit frame move must use `.none`, then restore `.center` for later content growth; otherwise
  `PopupPanel.setFrame` silently replaces the button's requested center with the old bar center.
- **Search and content modes are the two key exceptions to the never-key rule.** `PopupPanel.allowsKey`
  enables `canBecomeKey`/`canBecomeMain` in both modes (`PopupPanel.swift:19`), routed through the
  same `enterKeyMode()`/`exitKeyMode()` primitives (`PopupWindowController.swift:196,206`). A
  `@FocusState`-in-onAppear request is silently dropped on macOS, so search forces focus via
  `focusSearchField()` on the next run-loop turn (`PopupWindowController.swift:245`);
  `previousFrontmostApp` is captured once per session (on `show(for:)`/`enterKeyMode`, never
  re-captured mid-session) and re-activated on `exitKeyMode`/`hide`.
- **Search and content modes suspend popup dismissal.** The distance auto-dismiss and the key/scroll
  dismissals in `handleEvent` are skipped while `modeStore.mode == .search` or `.content`
  (`PopupWindowController.swift:591,612,622`), so typing with the mouse elsewhere doesn't close the
  palette, and the result card stays open until it is collapsed or the popup hides.
- **The floating bubble panel is gone; content renders inline.** The second `PopupPanel` (and its
  `showBubble`/`hideBubble`/`bubbleBlocksDismiss` machinery) was removed — all action/AI/status
  content renders inside the single panel via `.content` mode (`PopupModeStore`) as a native
  SwiftUI `ResultCardView`. The card is general, not AI-specific: any text-returning action lands
  there with its customization-resolved icon (`DeliveryContext.actionIcon`, snapshotted by the same
  perform paths as `actionTitle`); AI streaming deliveries pass no icon and keep the sparkles glyph. `StatusBadgeModel` and the old `.info`/`.result`/`.menu` emphasis
  model are gone, and the inline status banner is gone too: every `StatusFeedback` renders as a
  floating toast (`ToastPanelController`) with no queue — a status shows over the card — and
  `showsLoading` actions (manifest `"loading"`) use the early-close spinner toast. Each run
  can settle its own spinner. Error cards omit the Copy and Paste buttons and ignore their shortcuts.
- **`MathEvaluator` replaced crash-prone `NSExpression`.** `CalculateAction` used to run
  `NSExpression(format:)`, which throws an **uncaught Objective-C exception** on malformed selection
  text like `+` or `1+` (crash). The pure-Swift `MathEvaluator` (`Sources/Core/Actions/MathEvaluator.swift`)
  returns nil (never traps) and properly supports `%` modulo. Regression coverage in
  `Tests/OpenClipTests/CalculateActionTests.swift`.
- **Search rows render icons strictly `[icon | text]`.** A `.text` icon in the icon column would
  duplicate the title, so `PopupSearchView.rowIcon` falls back to `ConfigurableAction.preferenceIconName`; all four
  `ActionIcon` cases render through the shared `ActionIconView` (`Sources/OpenClip/UI/Icons/ActionIconView.swift`),
  including Iconify-format symbols (`prefix:name`). The popup bar keeps its own `iconView(for:)`
  (`PopupView.swift`) because text icons there need natural width + horizontal padding, not a fixed frame.
- **Popup sizing constants live in the App target.** `PopupMetrics`
  (`Sources/OpenClip/UI/Popup/PopupMetrics.swift`) holds the UI-only values — `searchMaxRows`
  (5), `searchResultRowHeight` (32), `searchPeekRowFraction` (0.5), `popupMaxHeight` (300, the
  shared height cap for the popup panel), the AI card bounds (`aiCardMinWidth` 220 /
  `aiCardIdealWidth` 300 / `aiCardMaxWidth` 360 / `aiCardBodyHeight` 160), plus
  placement/dismissal distances. `Core/Selection/Constants.swift` keeps only
  domain/runtime constants (timeouts, key codes, env vars, manifest keys).

## Unused / Latent

- **`ActionContext.modifiers` is currently unused.** No action reads it; `PopupWindowController`
  passes `modifiers: []`. The click intent itself *is* plumbed: `ActionContext.isSecondaryClick` is
  set from
  the captured `pendingClickIntent` by the bar/palette perform paths (right-click always; ⇧-click
  via the `onClickIntent` closure) and read by `DefineAction` to copy a definition headlessly. True
  modifier keys (⌘/⌥) still don't reach actions.
- **Paste delivery is now standardized but has a probe reliance.** Leaf `.paste` results are
  re-decided by `ActionResultDelivery` (App target) per the rule in the dev-guide §5b: a secondary
  click uses the declared `secondary` outcome (else derives `.copy` from a `.paste` primary), and
  the **unified** `PasteAvailability` answer (per-app rules win, AX `PasteAvailabilityProbe` fills
  in) downgrades a chosen `.paste` to `.copy` when it says no; otherwise the requested paste is
  honored. The delivery inputs are snapshotted at perform time — before
  the dismissing `hide()` clears the session context — so `denyPaste` holds even for pastes that
  dismiss the popup. Result cards carry the original app and input revision across asynchronous
  work. Explicit Paste checks both again immediately before posting ⌘V. Copy remains available
  when the selection is stale. The live probe
  (`PasteAvailabilityProbe`) needs
  Accessibility permission and
  walks the target's Edit ▸ Paste AX menu item; without AX it returns "unknown" and delivery falls
  back to copy (safe but means paste never happens for AX-less users). The same unified decision drives
  `modeStore.canPaste`, which hides the card's Paste button and the bar/search Paste + Cut
  (`PasteRequiringAction`) actions on a confirmed cannot-paste; unknown keeps them visible. The
  probe is started by the trigger sites in parallel with selection retrieval and applied before the
  first frame (probe-before-render, nothing cached), so a same-app focus-context change re-probes
  cleanly. The click-intent capture reads
  only ⇧ (not ⌘/⌥) and only sets it on mouse-down; a keyboard-driven run (search palette Enter) uses
  the last left-click intent. Since Task 4, each action's declared `Action.delivery` (a distinct
  secondary outcome + per-click `primaryToast`/`secondaryToast`) is snapshotted alongside the click
  intent and fed into `resolve`, and the returned tuple's toast is rendered directly — the manual
  `isDowngradedToCopy`/`isCopyDefinition` inline toast detection was removed in favor of the resolved
  `.toast`. Since Task 8, a script-emitted `.toast` (or any result whose `containsToast` is true)
  suppresses the delivery companion toast entirely — one toast per run — and `keepVisible: true`
  stops a toast's auto-dismiss and keeps the popup open (a `.toast` dismisses by default). Only the
  SwiftUI inline perform path snapshots via the new `onWillPerformAction` closure;
  the completion-button paste path (`PopupView` `onResult(.paste(word))`) routes through
  `deliverResult`, which clears `pendingDelivery` right after its snapshot (single-use per perform),
  so a prior non-dismissing action's declared delivery can never leak onto a completion paste. The
  force-copy probe short-circuit skips the AX walk for a secondary click whose outcome is a copy;
  a declared `.paste` secondary is the exception and still probes, so it is honored when the target
  can paste (and downgrades to copy when it cannot). Since Task 3, implicitly returned text
  (runtimes emit `.text`, never auto-dismissing) is resolved per the user's per-click preference
  from the two General-tab settings (`preference(for:)`, unknown values fall back to primary-paste/
  secondary-copy): a paste preference probes like any paste and downgrades to copy when the target
  can't paste, a copy preference delivers a native copy with no toast, and a preview preference keeps
  the popup open for the card render (Task 4) — dismissal for `.text` is decided by the controller's
  `shouldDismiss`, not `dismissesPopup`. The loading re-show path (`settleLoadingResult`)
  re-creates the popup from the pre-early-close selection snapshot to present the card.
  - **Target application and delivery context snapshotted before perform.** Asynchronous actions snapshot
    the target application, app policy, and declared delivery into an `inFlightDeliveryContext` (or local task
    constant) before performing. If the user switches applications while an asynchronous action is executing,
    `resolveDelivery` detects that the target application is no longer active and safely downgrades `.paste`
    to `.copy` with a "Copied" toast to prevent pasting into the newly focused application.
  - **Intervening input prevents automatic paste.** Delivery snapshots system key-down and mouse-down
    event counters before perform, then compares them and rechecks the frontmost app after the
    asynchronous paste probe. Any input downgrades plain/rich paste to copy, conservatively covering
    same-app selection/window changes and typing during network requests. Motion and key-up do not
    invalidate delivery. Programmatic selection changes with no input remain undetected; the final
    check and synthetic paste are not atomic. Explicit card-button requests still bypass this guard.
  - **Re-show binds to the current frontmost app.** The loading-preview re-show
    (`settleLoadingResult`) re-creates the popup from the selection snapshot, but `hide()`
    clears `previousFrontmostApp`, so the re-show re-captures whatever is frontmost at settle
    time — if the user switched apps during a multi-second spinner, dismissal reactivates that
    app. The card's paste probe correctly targets the snapshotted app; only dismissal's
    reactivation is affected.
  - **`.text` inside a `.sequence` is unhandled.** Runtimes emit `.text` only as a lone result
    today, so a `.text` inside a sequence is defensive-only; if the runtime surface ever grows to
    emit `.text` in sequences, the tree-walk needs explicit handling.
- **HotkeyManager.executor pattern** (`HotkeyManager.swift:22`): a latent `Task { @MainActor in`
  inside the shortcut callback could be hardened to an explicit executor; optional.

## Concurrency

- **Residual non-interruptible paths (documented).** Two spots remain that a hostile
  or hung target can make block a background thread:
  (1) `SelectionRetrievalCoordinator.pressEditCopyMenu` starts an AXPress on the dedicated
  `com.openclip.ax-inspect` queue. Menu traversal uses the remaining copy deadline, and the
  pasteboard transaction must still be active immediately before AXPress. Once issued, a blocked
  AXPress can occupy one worker until it returns or its messaging timeout expires.
  The `inspectGate` permit is not held for that duration.
  `pressCopyMenuWithWatchdog` releases the permit at the first of {press returned, `axReadTimeout`},
  same OnceResume race as inspect. The queue is concurrent, so a blocked press does not delay
  later retrieval requests (see below);
  (2) an async-mode
  JS script with a top-level *synchronous* infinite loop blocks inside `evaluateScript`, which the
  watchdog pump loop never reaches (the sync-evaluation gate covers only `isAsync == false`).
  Neither path is main-actor-blocking.
- **AX inspect is deadline-capped.** `SelectionRetrievalCoordinator.inspectWithWatchdog` races
  `AXElementInspector.inspect` against
  `Constants.axReadTimeout` (0.5 s) via the `OnceResume` once-gate, running the blocking snapshot on
  the dedicated `com.openclip.ax-inspect` queue; an unresponsive app returns
  `nil` to the retrieval chain instead of hanging the popup.
- **Inspect concurrency is bounded, not serialized.** The old single fail-fast `axSlot` made every
  overlapping gesture (rapid re-selection, double-click, hotkey+monitor races) miss entirely and
  stayed occupied until the underlying AX call returned — one heavy page suppressed popups
  process-wide for seconds. Reads now go through a counting gate (`Constants.axMaxConcurrentInspects`,
  currently 4): concurrent reads proceed in parallel, the permit frees when the caller's watchdog
  settles (deadline or completion), and only genuinely saturated bursts skip. Menu-copy presses
  share the same gate. The permit is released at `axReadTimeout`, same as inspect.
- **The `ax-inspect` queue is concurrent, not head-of-line blocking.** All blocking AX work in the
  coordinator (the inspect snapshot and the Edit ▸ Copy AXPress) shares one concurrent
  `com.openclip.ax-inspect` queue: a hung AX call occupies one worker thread but later inspect
  snapshots and presses start on other threads, so a slow or stuck target no longer delays the next
  request's start. Each request still gets its own `axReadTimeout` deadline race.
  PasteAvailabilityProbe now follows the same deadline-release model on its concurrent `ax-probe`
  queue, with four caller permits. Menu traversal and the final enabled read share a deadline;
  each AX message gets only the remaining budget. As with inspect, caller permits are not a hard
  lifetime bound on blocked AX workers.
- **Subprocess pipe reads are non-blocking (hang fix).** `ShellProcessRunner` previously read stdout/
  stderr with blocking `readToEnd()` tasks and a `Task.sleep` watchdog — both can be starved, so a
  child (or grandchild) holding a pipe open could wedge the cooperative pool and hang the test
  suite indefinitely when a subprocess was reading stdin. The runner now
  uses a GCD timer watchdog + GCD `readabilityHandler` reads + synchronous stdin close. The
  successful exit path finishes both bounded pipe drains before reading the accumulated output. This claim
  covers only the pipe reads: `process.waitUntilExit()` still blocks its detached thread until the
  child exits — bounded at `Constants.scriptTimeout`. At timeout the watchdog starts descendant
  cleanup (the child, the process group when the child is the leader, and remaining descendants).
  `waitUntilExit()` waits only for the direct child; descendant SIGKILL is scheduled asynchronously
  and may finish after the wait returns. Descendants come from a `proc_listchildpids` walk of the
  child's own subtree (not a scan of the whole process table), snapshotted with start times before
  `terminate()`. Two limits remain: a probe that reports 0 children is still read once, because a
  spurious 0 would silently drop a descendant; and a grandchild that reparented to launchd before
  the snapshot is unreachable by any pid walk.

## Selection Retrieval

- **The coordinator runs a targeted strategy chain with native AX prioritization.**
  `retrievalMode` picks the entry point; retrieval runs that strategy and its fallbacks
  (native text controls fall back to keyboard copy unless strictly native; web areas cascade
  `ax-web-area → keyboard-copy`). Browsers resolve natively via `AXWebArea` in <1 ms with deep
  ancestor search (depth 25 + window search) and fall back to keyboard copy with a 0.6 s timeout.
  Saved `browser-script` rules use this same path.
- **Selection copies no longer suppress hardware input.** `SessionEventTapPoster` uses zero
  suppression interval and permits keyboard, mouse, and system events in both suppression states.
  Its synthetic events carry a source tag so selection/popup monitors do not cancel or dismiss
  their own work. Global monitors remain observation-only; the local popup monitor returns events.
- **Clipboard capture is serialized per pasteboard.** Transactions wait cooperatively, honor
  cancellation before copying, and restore immediately. HID input counters invalidate capture
  and restoration when the user types,
  clicks, or scrolls, preserving an intervening user copy. Rich representations must come from one
  pasteboard generation, and enrichment must match the original AX text. There is no atomic
  clipboard ownership API: unrelated background writes without input and late source-app copy
  completions after timeout remain possible; cancelled captures with intervening input deliberately
  leave the current clipboard untouched. Promised clipboard data can still block synchronously.
- **Address-bar auto-selection is read-only.** Single mouse clicks read an explicit selection
  only from a focused native text editor; they never run page retrieval or a copy fallback.
  Browser native editors bypass cursor heuristics and web/rich-copy strategies. AX inspection
  does not attach an unrelated page to the focused native editor. Cancelled copy transactions
  leave the clipboard untouched even when an input remapper does not advance HID counters.
- **Gesture lifetime follows the source interaction.** New mouse-down, keyboard selection, and
  ordinary key input cancel stale retrieval; dragging cancels an in-flight hold. A hold that fails
  after release retries the eligible mouse-up selection instead of swallowing it. Delivery rechecks
  the source app. Keyboard gestures and the explicit hotkey bypass the mouse cursor gate (a pointer
  parked over a link is irrelevant to keyboard selection), while text-role and app-policy gates stay.
- **Web selection retries and cancellation are covered.** Settle exhaustion falls back to copy once;
  cancellation after inspection never reaches a copy fallback. Marker resolution and fresh web
  reads now run on the AX queue under the same watchdog as inspection, with per-element AX messaging
  timeouts. A timed-out read exits the retry loop. The watchdog bounds the caller, not the total
  lifetime of an AX worker; releasing permits on timeout still allows blocked workers to accumulate.
- **Rich web selection still uses a synthetic copy for enrichment.** Even an AX success may wait
  for clipboard capture (up to the browser polling budget). Selection is temporarily visible on the
  pasteboard before restoration; clipboard managers can observe it. Restore markers only tag the
  restored snapshot, not the source app's copy.
- **Hold-trigger clipboard fallback is gated on an exact fire-time cursor class.** The
  `MacSelectionMonitor` hold task inherits the clipboard only when
  `CursorClassifier.current == .beam` (and paste is not denied). The classifier reads the real
  window-server cursor (`NSCursor.currentSystem` — `NSCursor.current` is process-local and
  always reported arrow for this background app, which silently disabled the whole gate until it
  was fixed). Residual limits: custom cursors whose bitmap silhouette-degrades to `.unknown`
  (some Electron/web apps) fail the strict equality even over editable fields, and a press-hold
  that makes an app swap cursors samples the swapped class.


## Test Isolation

- `TestIsolation.reset()` clears the shared registry, customization manager, rule engine, and
  extension manager. Tests that exercise shared extension registration supply their own callbacks.
- Tests use memory settings, named pasteboards, temporary package directories, and temporary
  secrets files. Selection-retrieval tests inject AX snapshots and copy captures. The popup AI
  preset test clicks Explain in both layouts and uses a stub streaming provider.

## Logging

- **Single `Log` surface is in.** `Sources/Core/Log.swift` owns every `os.Logger` category
  (`settings`, `presentation`, `chrome`, `factory`, `coordinator`, `result-handler`, `shell`, `js`,
  `selection`, `extensions`, `ai`, `permissions`, `icons`, `updates`); all `print()` calls are gone. See
  `docs/logging.md` for the category table and filtering workflow.
- **Level budget is conservative.** Most messages are `.notice`/`.error`; `.debug` is used for
  defensive parses and transient network hiccups (filtered out by default in Console).
- **`chrome` category is reserved but unused** — no popup-window-chrome code logs yet.

## Personal release channel

- Personal versioning starts at 1.0.0 (build 9). Upstream tags/history remain reference material.
- No app update feed or signing key is bundled. AppUpdateManager does not instantiate Sparkle
  without an explicit personal feed plus a valid-length public key, regardless of saved preferences.
  Updates currently require manual installation; release CI builds artifacts only.
- The v1.4.0 assessment and port record are in `docs/upstream/v1.4.0-assessment.md`. The first batch
  includes paste-probe starvation recovery, AX traversal budgets, accurate build paths, icon-mode
  persistence, editor row reuse, and the AI input-boundary prompt. Diff/tooltip remain pending.
- Actions-outline refresh caches the previous rendered signature. Navigation/toggles retain nodes
  and hosting views; same-ID replacements refresh action data, while appearance/structure changes
  invalidate the cached presentation. No upstream action-model rewrite was needed.
- Dev and packaging scripts both use this project's `build/DerivedData`, never a global glob of
  DerivedData bundles. Tests continue to use their existing Xcode test configuration.
