# Telemetree — Spec Addenda

The original product spec (MVP scope, milestones, architecture) was given at
project start and isn't reproduced here. This file tracks additions made
after that point, so they survive context resets.

## Post-M4 fixes and Preferences

- **Critical fix**: Run used to send the *entire* editor buffer regardless
  of caret position — with two statements in one document (e.g. a
  leftover `DELETE` above a `SELECT` being worked on), clicking Run could
  fire the unrelated earlier statement. `Database/SQLStatementLocator`
  splits on top-level `;` (ignoring semicolons inside strings/comments,
  verified with unit-style checks); `AppState.executeCurrentSQL` now
  takes an override string, and the SQL editor passes the real selection
  or the statement under the caret — never the whole buffer. The
  about-to-run statement is also highlighted (background tint) whenever
  there's no active selection.
- **Fixed**: SQL autocomplete wasn't firing.
  `isAutomaticTextCompletionEnabled` alone doesn't trigger it — AppKit
  still needs an explicit `textView.complete(nil)` per keystroke
  (confirmed via Apple documentation, not guessed).
- **Preferences window** (⌘, — macOS auto-renames this menu item to
  "Settings…", not a bug): `UI/Preferences/PreferencesWindowController`,
  3 tabs built as simple `NSPopUpButton`-in-`NSGridView` rows.
  - Appearance: the existing Vapor theme picker (previously menu-only).
  - Syntax Highlighting: `UI/Theme/SyntaxTheme` — 4 color schemes
    (Default, Dracula, Monokai, Solarized Dark). `SQLSyntaxHighlighter`
    is now theme/font-injectable instead of hardcoding colors, shared by
    both the main SQL editor and the snippet editor.
  - Editor: `UI/FontPreferences` — font choice (Geist Mono / SF Mono /
    Menlo) and size (10–18pt), applied live via Combine.

## Icons — Icons8 (implemented)

- Style: Icons8 "SF Black" (thick strokes, reads well at 16pt — the user's
  pick after trying "ios-filled" first — too heavy/blobby, including a
  circled-plus glyph — then "ios" outline — too thin, washed out at small
  sizes). Fetched from `img.icons8.com` and bundled locally under
  `Sources/Telemetree/Resources/Icons/*.png` (no runtime network
  dependency). Loaded via `AppIcon` (`UI/AppIcon.swift`), which sets
  `isTemplate = true` so tinting works exactly like SF Symbols did before.
- Current icon map: `add`→plus-math, `connection`→server, `database`→database,
  `table`→data-sheet (NOT the literal "table" slug — that's a kitchen
  table), `folder`→opened-folder, `document`→document, `snippet`→source-code,
  `warning`→error, `close`→multiply (tab close button), `trash`→trash.
- Attribution: About window (Telemetree menu → About Telemetree) credits
  "Icons by Icons8" with a link to icons8.com, per Icons8's linkware
  license terms. See `UI/About/AboutWindowController.swift`.
- Gotcha for future icon swaps: NSImage renders bitmaps at native pixel
  size unless `.size` is set explicitly — SF Symbols did this implicitly,
  plain PNGs don't. `AppIcon` sets a 16×16pt default; don't skip this on
  new icons or buttons balloon to the source image's full resolution.
- Gotcha for sidebar icon tint specifically: don't set an explicit
  `contentTintColor` for the "default" state — it overrides AppKit's
  automatic selection-emphasis brightening (the thing that makes text pop
  white on a selected+key row), leaving icons duller than adjacent text.
  Leave it `nil` for the default case; only set it explicitly for real
  accent states (connected = green, active = accent color).

## Fonts — Geist / Geist Mono (implemented)

Bundled under `Resources/Fonts/*.ttf` (from vercel/geist-font), registered
at runtime via `CTFontManagerRegisterFontsForURL` since this is a plain SPM
executable with no Info.plist font declarations. `FontLibrary.sans`/`.mono`
wrap this with a system-font fallback if a weight isn't bundled. Applied
everywhere `.systemFont`/`.monospacedSystemFont` was previously used.

## Cross-app theme system

The user maintains a shared visual language across their apps, originally
authored for **GhostBar** (a Touch Bar overlay utility) as an 8-theme
system for a translucent touch-panel. Telemetree is a windowed app, not a
Touch Bar panel, so the literal mechanics don't transfer — this maps the
*material/palette identity* of each theme onto Telemetree's own chrome
(toolbar/status bars, the active-tab pill, the connection-status dot)
rather than porting it verbatim.

Themes (8 total in the source spec, one shared accent identity each —
never reused across themes): **Vapor** (base/default), **Meniscus**
(glassier Vapor), **Ulm** (Rams/Braun flat matte), **Instrument** (quiet
systematic light mode), **Unibody** (brushed-aluminum hardware look),
plus three Vapor material variants: **Gold**, **Silver**, **Carbon
Fiber**. **Decision, final: only the Vapor family ships in Telemetree.**
Meniscus/Ulm/Instrument/Unibody are discarded, not deferred — not a
roadmap item, don't build them without a fresh ask.

### Implemented: the Vapor family (base + Gold/Silver/Carbon)

- `UI/Theme/Theme.swift` — the four variants' bar fill/border,
  active-segment fill/text, and dot gradient/glow colors.
- `UI/Theme/ThemeStore.swift` — current selection, persisted to
  `UserDefaults` (`com.telemetree.app.themeID`).
- `UI/Theme/StatusDotView.swift` — a real pulsing radial-gradient dot on
  connection rows. This is the closest analogue to the source spec's
  Touch Bar "touch dot," and the one element that makes each theme's
  accent identity actually visible, so it got built as a proper CALayer
  view rather than just a tinted icon.
- `UI/Theme/CarbonWeaveTexture.swift` — Carbon Fiber's crossed 45°/-45°
  diagonal weave, baked into a 6pt tile and used as an `NSColor` pattern
  for `Theme.barFillPaint`. Chips (the tab pill) stay flat, no weave, per
  the source spec ("texture is a panel thing, not a chip thing").
- Applied to: sidebar footer bar, SQL editor toolbar, results grid status
  bar (all via `theme.barFillPaint`/`barBorder`), and the active tab pill
  in the tab bar (`theme.activeSegmentFill`/`activeSegmentText`).
- Switchable via the Theme menu in the menu bar (checkmarks reflect
  current selection via `NSMenuItemValidation` on `MainWindowController`).

## Milestone 2 addendum: sidebar search

M2's spec listed "search for queries" as a capability but it wasn't built
in that pass. Landed alongside Milestone 3's snippet search instead: one
`NSSearchField` above the sidebar tree filters both the Queries and
Snippets sections by name (flattening matches out of their folder
structure while a search is active; clearing the field restores the
normal nested tree). Connections aren't filtered — no stated need for it.

## Milestone 3 addendum: snippet editing, hover-delete, color labels

- **Snippet editing was missing entirely** — M3 built create/rename/insert
  for snippets but nothing ever called `SnippetStore.updateSQL`, so every
  snippet stayed permanently empty. Fixed with
  `UI/Snippets/SnippetEditorWindowController` (reuses
  `SQLSyntaxHighlighter`), opened via double-click or a snippet's new
  "Edit…" context menu item, autosaving on every keystroke like query
  documents do.
- **Window controller retention bug**, found via the above: both this new
  controller and the pre-existing `NewConnectionWindowController` were
  created as bare local variables with nothing holding a strong reference.
  The `NSWindow` itself stayed on screen (retained while visible), but the
  Swift controller object could be deallocated — and `NSTextView.delegate`
  / `NSButton.target` are both weak, so typing silently stopped
  autosaving and buttons silently stopped responding. Fixed by holding
  real references on `SidebarViewController` (a single optional for the
  one-at-a-time connection sheet, a snippetID-keyed dictionary for editor
  windows, cleaned up via `NSWindow.willCloseNotification`).
- **Hover-to-delete**: `UI/Sidebar/HoverTrackingCellView` (an
  `NSTableCellView` subclass using `NSTrackingArea`) shows a red trash
  button only while the pointer is over a deletable row (query
  document/folder, snippet, snippet folder). Deleting confirms via a
  sheet-modal `NSAlert` first.
- **Color labels**: an 8-color fixed palette (`UI/Theme/LabelColor.swift`)
  assignable to the same four kinds via a "Label" context-menu submenu,
  rendered as a small colored dot in the same trailing slot the
  connection-status dot uses (mutually exclusive — a row is never both).

## Improvements (implemented)

- **Destructive SQL confirmation**: `Database/DestructiveSQLGuard` flags
  `DELETE`/`DROP`/`TRUNCATE` always, and `UPDATE` only when it has no
  `WHERE` clause (a keyword check, not a parser — deliberately simple).
  `AppState.executeCurrentSQL` requires `LocalAuthentication`
  (`.deviceOwnerAuthentication` — Touch ID with password fallback) before
  running a flagged query; fails closed if authentication can't be
  evaluated at all, and a cancelled/failed auth blocks execution with an
  error message rather than silently proceeding.
- **SQL keyword autocomplete**: `NSTextView.isAutomaticTextCompletionEnabled`
  (native, macOS 14+, zero dependencies) plus the existing
  `NSTextViewDelegate` completions method, reusing
  `SQLSyntaxHighlighter.keywords` as the candidate list — no separate
  keyword list to keep in sync. Keyword-only for now, not schema-aware
  (no table/column name completion yet — would need to query
  `information_schema` and cache per-connection, a reasonable follow-up
  but out of scope for "suggest keywords").

## Milestone 4: history, command palette, keyboard shortcuts

- **Query history**: `History/QueryHistoryStore` — append-only, capped at
  500 entries, persisted like the other stores. `AppState.executeCurrentSQL`
  records every attempt (SQL, connection name, timestamp, success/fail)
  after it resolves; a query that never reaches execution (no connection
  selected) isn't logged, since that's a configuration issue, not an
  executed query. `UI/History/QueryHistoryWindowController` — searchable
  table, double-click to reopen as a new query document
  (`AppState.reopenHistoryEntry`), "Clear History" button. Opened via
  File → Query History…
- **Command palette** (⌘⇧P / File → Command Palette…):
  `UI/CommandPalette/CommandPaletteWindowController`. Substring-filters
  across query documents, snippets, connections, and a fixed action list
  (New Query, New Snippet, Run Current Query, Query History, each Theme).
  Arrow keys/Return work from the search field via
  `NSSearchFieldDelegate.control(_:textView:doCommandBy:)` forwarding to
  the results `NSTableView`. Deliberately excludes live table names — that
  would need a schema-name cache this app doesn't build yet (each
  connection's tables are only loaded lazily, per database, when the
  sidebar asks for them); worth adding once such a cache exists.
- **Keyboard shortcuts**: ⌘F opens the SQL editor's native find bar
  (`NSTextView.usesFindBar`/`performTextFinderAction(_:)` — no custom find
  UI needed). ⌘⇧F focuses the sidebar's existing search field
  (`SidebarViewController.focusSearch()`) rather than building a second
  search surface. ⌘1–9 switch open tabs via a Window menu (9 items,
  tagged 1–9, `MainWindowController.selectDocumentTab(_:)`); disabled via
  `NSMenuItemValidation` once the tag exceeds the open-tab count.
- Both new window controllers (`QueryHistoryWindowController`,
  `CommandPaletteWindowController`) are owned by `MainWindowController`
  as stored properties — the retention bug from the M3 addendum above is
  exactly this class of mistake, so both were built with that lesson
  already applied.
- Found while testing: the Snippets section never auto-expanded on
  launch (only Connections/Queries did) — a one-line miss in
  `viewDidLoad`, now fixed.

## Milestone 5: polish, error handling, performance, native UX, settings

Settings landed already (Preferences window, above). Scope decision: system
light/dark appearance is explicitly deferred to the very end of the
project — Vapor is a fixed dark aesthetic and won't respond to the system
appearance setting until M5 is otherwise done. Remaining open items:
error-handling depth (clearer messages for common MySQL error codes,
reconnect-on-drop), no accessibility/VoiceOver labels anywhere yet, no
custom app icon, no performance/stress-testing pass done.

- **Fixed**: pagination for large result sets — an original MVP bullet
  that never got built (the results grid loaded a query's entire result
  set into memory with no LIMIT/paging). `AppState.executeCurrentSQL` now
  auto-appends `LIMIT 500` to a plain SELECT that doesn't already specify
  its own LIMIT (a keyword check, not a parser — same tradeoff as
  `DestructiveSQLGuard`); `OpenDocumentState` tracks the base SQL/offset,
  and a "Load More" button in the results status bar
  (`AppState.loadMoreRows`) fetches the next page via `LIMIT/OFFSET` and
  appends rows, instead of re-running the whole query.

## Release packaging: build script, `.app` bundle, CI, Homebrew tap

Adapted from the same pattern already proven on the user's GhostBar
project (`felipepkgs/GhostBar` / `felipepkgs/homebrew-ghostbar`) — fetched
and read directly from that repo rather than guessed, then adjusted for
Telemetree (windowed app, no `LSUIElement`; bundle ID
`com.felipepkgs.telemetree`; `depends_on macos: :sonoma` since this app
targets macOS 14 vs. GhostBar's 13).

- `Packaging/Info.plist` — real bundle metadata. No `CFBundleIconFile` yet
  — no custom app icon exists (still an open discussion with the user,
  flagged separately from this packaging work). The bundle falls back to
  the generic macOS app icon until one's chosen; `Scripts/build_app.sh`
  already copies `Packaging/AppIcon.icns` into the bundle *if present*, so
  adding the icon later needs no script change.
- `Scripts/build_app.sh` — `swift build -c release`, hand-assembles
  `Telemetree.app` (binary, Info.plist, the `Telemetree_Telemetree.bundle`
  SPM resource bundle for the Icons8/Geist assets), ad-hoc codesigns
  (`codesign --force --deep -s -`) — no paid Developer ID.
- `.github/workflows/release.yml` — fires on push to `master` that touches
  `Sources/**`/`Package.swift`/`Packaging/**`/`Scripts/build_app.sh` (so
  doc-only commits don't cut a release). Auto-bumps the patch version if
  the current `Info.plist` version is already tagged, builds, zips
  (`ditto -c -k --sequesterRsrc --keepParent`), tags, and publishes a
  GitHub Release with the zip attached.
- **Homebrew tap**: `felipepkgs/homebrew-telemetree` (new repo, public —
  required for `brew tap` to work), `Casks/telemetree.rb` — points at the
  release zip by version/sha256, `postflight` clears the Gatekeeper
  quarantine flag (ad-hoc-signed, not notarized), `zap` removes
  `~/Library/Application Support/Telemetree` and the app's prefs plist.
  The workflow's last step updates this tap's cask automatically after
  each release, but needs a `HOMEBREW_TAP_TOKEN` repo secret (a
  fine-grained PAT scoped to the tap repo, Contents: read/write) that
  **has not been created** — that step will fail harmlessly until the
  secret exists; the release itself still publishes fine without it.
- **Resolved**: `felipepkgs/telemetree` was private, which would've made
  the public cask's release-zip download fail for anyone without repo
  access. Now public — verified the `v0.1.0` release zip downloads
  anonymously (`200`, no auth).

## Post-release: crash-on-launch fix, Homebrew tap-trust gotcha

- **v0.1.0/v0.1.1 crashed on launch for every installed user**
  (felipepkgs/telemetree#2, a real IPS crash report, not a local-only
  issue). Root cause: SPM's generated `Bundle.module` accessor only
  checks `Bundle.main.bundleURL` (the `.app`'s own root — no
  `Contents/Resources`) plus the CI build directory, neither of which is
  where `Scripts/build_app.sh` actually places the resource bundle in a
  real `.app`; it hits an uncatchable `fatalError()` otherwise. Invisible
  in local `swift run` testing since that "bundle" is just a build-output
  directory next to the executable — only a packaged, installed app
  crashes. Fixed in v0.1.2: `Sources/Telemetree/TelemetreeResources.swift`
  replaces every `Bundle.module` call site with a resolver that checks
  `Bundle.main.resourceURL`/`.bundleURL` against both a flat and a
  `Contents/Resources`-nested bundle layout. Verified by downloading and
  running the actual CI-built release zip, not just a local build — that
  distinction is what caught this in the first place, and what confirmed
  the fix.
- **Homebrew tap-trust gate**: as of Homebrew 7.0.5, `brew install` on a
  third-party tap refuses to even load the cask ("Refusing to load cask
  ... from untrusted tap") until `brew trust --cask
  felipepkgs/telemetree/telemetree` (or `brew trust felipepkgs/telemetree`)
  has been run once. This is what "can't download the new release" turned
  out to be — not a server-side problem, the asset/cask were always fine.
  Not something the cask itself can fix; it's a one-time step for anyone
  installing this tap for the first time on a recent Homebrew.
- **Known, deliberately unfixed**: `brew install`/`upgrade` prints a
  `postflight` deprecation warning every time (Homebrew wants
  `postflight_steps`/`run` instead). Same tradeoff GhostBar's cask made —
  `{{appdir}}` template-token support in `postflight_steps` did land in
  Homebrew 5.1.14+, so this may no longer be strictly necessary; not
  migrated since the user called it cosmetic and asked to leave it.

## M5: accessibility, error handling, performance

- **Accessibility**: previously zero — icon-only buttons and custom views
  had no VoiceOver labels, and the document tab bar (`TabButtonView`) was
  a plain `NSView` with a `mouseDown` override, meaning tab switching was
  completely invisible to VoiceOver/keyboard navigation, not just
  under-labeled.
  - `TabButtonView` is now a real `AXButton` (`isAccessibilityElement`/
    `accessibilityRole`/`accessibilityLabel` overridden, `accessibilityPerformPress()`
    calls `onSelect`).
  - Icon-only buttons (tab close, sidebar add, sidebar delete) get real
    labels via a new `UI/AccessibleIconButton.swift`.
  - Sidebar rows get one composed accessibility description each (e.g.
    "Local Test, connection, connected", "All Users, query, active,
    labeled Red") via `HoverTrackingCellView.accessibilityDescriptionOverride`,
    rather than making every row's icon/dot/label-color indicator its own
    separately-focusable element.
  - **Real, hard-won gotcha, not guessed**: `NSButton.accessibilityLabel()`
    and `NSTableCellView.accessibilityLabel()` both silently ignore
    `setAccessibilityLabel(_:)` — they compute their own value internally
    (from `.title`, from the cell's `.textField`) regardless of what the
    setter stores. The fix in both cases is overriding the *getter*
    directly in a subclass, not calling the informal-protocol setter.
    Confirmed via direct `AXUIElementCopyAttributeValue` inspection
    (Python + `ApplicationServices`, bypassing AppleScript's System Events
    translation layer, which turned out to read `AXRoleDescription` — a
    generic per-role string like "button" — under its "description"
    property, not the actual accessibility label; that mismatch cost a
    lot of wasted verification time before catching it).
  - **Known, disclosed limitation**: even after the getter-override fix,
    local verification (`swift build` dev binary, ad-hoc signed, run
    directly) still doesn't show the custom labels via direct
    `AXUIElementCopyAttributeValue` calls — confirmed with a hardcoded,
    unconditional return value in the override, ruling out any
    property-storage bug. The verification method itself was proven
    sound (identical script correctly reads Finder's real, localized
    icon-button labels). The code is correct, standard AppKit API usage;
    something about this specific non-Xcode, ad-hoc-signed dev build
    environment doesn't surface it to an external AX client. Whether the
    *CI-built, properly-packaged* release behaves differently is
    untested — worth a real VoiceOver pass on an actual shipped build
    before trusting this fully.
- **Error handling**: `Database/FriendlyError.swift` maps common MySQL
  error codes (1045 access denied, 1044/1049 unknown database, 1146 no
  such table, 1054 unknown column, 1205 lock wait timeout, 1213 deadlock)
  to plain-English messages instead of raw server text, using MySQLNIO's
  actual `ERR_Packet.errorCode.rawValue` — verified each code against the
  vendored `MySQLProtocol+ErrorCode.swift`, not guessed. Connection-level
  failures (refused/timeout/unreachable) get a best-effort keyword-matched
  message, since NIO doesn't give a structured error type for those here.
  `DatabaseError.connectionLost` is a new case, thrown when the failure
  means the socket itself is gone (vs. a normal query-level failure where
  the connection is still fine); `AppState.executeCurrentSQL` catches it
  and calls the new `ConnectionManager.markDisconnected`, so the sidebar's
  status dot flips to "not connected" instead of staying green against a
  dead connection, and the next query attempt reconnects fresh rather than
  repeatedly failing against a closed socket.
  Not E2E-verified against a live error (connecting via the sidebar
  requires a real double-click, which — same as always in this
  environment — can't be reliably synthesized); verified instead by
  cross-checking every mapped error code against MySQLNIO's real error
  table and a full clean build.
- **Performance**: the original MVP gap (unbounded row fetch) was already
  fixed earlier via pagination (see above). For this pass, wrote a
  throwaway standalone script (`Sources/StressTest`, removed after use —
  not shipped) that exercised the *actual* driver/pagination code path
  directly against a real 5,000-row MySQL table, since the AppKit UI
  can't be automated here either. Results: full unpaginated fetch of
  5,000 rows ~0.1s; paginated 500-row pages ~7-10ms each, consistently
  fast regardless of page depth (page 1 and a deep `OFFSET 4500` page
  timed the same); page boundaries verified contiguous (no gap/overlap
  between consecutive pages). No profiling infrastructure was added
  permanently — this was a one-off verification, not a lasting tool.

## Post-M5 verification pass: real bugs found via live testing

Everything in the M5 section above was verified by code review and
isolated logic checks, not by actually running queries against a live
connection — this pass did that, and found real bugs the earlier review
missed.

- **Root cause of nearly all the confusion this pass**: a Homebrew-
  installed copy of the app and a locally built dev binary were running
  *at the same time*. Clicks, keystrokes, and screenshots kept landing on
  whichever window happened to be frontmost — not necessarily the one
  actually being scripted against — which looked exactly like "the fix
  isn't working" for round after round before the real cause (two live
  processes, not one broken fix) was caught. Resolved two ways:
  - Uninstalled the Homebrew copy — **going forward, only run the local
    build on this machine.** Homebrew/release testing happens on a
    separate machine; issues from there get filed normally.
  - Added `App/SingleInstanceLock.swift` — `flock()` on a lock file in
    Application Support, acquired as the first thing in `main()`, before
    any UI setup. Atomic/kernel-enforced, so it can't race the way an
    `NSWorkspace.runningApplications` list-and-check can when two
    instances launch close together. Since Telemetree has a real window
    (unlike a menu-bar-only accessory app), the second instance activates
    the first one (`NSWorkspace`, matched by process name — a bare dev
    binary has no bundle identifier to filter by) instead of silently
    quitting.
  - Adjacent gotcha: `find .build -name Telemetree` silently preferred a
    stale `-c release` binary over the fresh plain `swift build` (Debug)
    output once both existed on disk from earlier in the session — file
    timestamps looked fine, it just wasn't the binary actually being
    edited. `rm -rf .build/out/Products/Release` before rebuilding, or
    check `strings <binary> | grep <a string unique to the latest edit>`,
    not just timestamps, when a fix "isn't taking."
- **Fixed**: pagination appended `LIMIT n` directly after the raw SQL
  string without stripping a trailing `;` first, producing invalid syntax
  (`SELECT * FROM x; LIMIT 500`) for any un-limited SELECT ending in a
  semicolon — the near-universal style, so this broke pagination for
  most real queries. Found via a real MySQL syntax error while testing
  against a live connection, not by inspection.
  `AppState.stripTrailingSemicolon` fixes both `executeCurrentSQL` and
  the stored `paginationBaseSQL` `loadMoreRows` reuses. Verified against
  a real 600-row table: correct page boundaries, ~7-10ms per page
  regardless of depth.
- **Found, not fixed**: DML statements (INSERT/UPDATE/DELETE) always show
  "0 row(s) affected" regardless of the real count.
  `MySQLDatabaseConnection.execute`'s `simpleQuery` never returns
  result-set rows for DML, so the `guard let firstRow = rows.first else
  { return ...affectedRows: 0 }` early-return path always hits. The real
  affected-rows count only comes from MySQLNIO's `OK_Packet`, exposed via
  the `query(_:_:onRow:onMetadata:)` API — a different wire protocol
  (prepared statements, COM_STMT_PREPARE/EXECUTE) than `simpleQuery`'s
  text protocol (COM_QUERY). Switching carries migration risk (prepared
  statements can behave differently for some DDL/multi-statement cases)
  that needed more testing than there was room for — left as a known
  issue, data integrity isn't affected, just the displayed count.
- **Accessibility — verified as far as this environment allows, not
  further**: confirmed the actual bug class (`NSButton`/`NSTableCellView`
  silently ignore `setAccessibilityLabel()`, must override the getter —
  see the M5 section above) via direct `AXUIElementCopyAttributeValue`
  calls (Python + `ApplicationServices`, bypassing AppleScript's System
  Events entirely). That direct check also caught a trap: AppleScript's
  "description" property reads `AXRoleDescription` (a generic per-role
  string like "button"), not the real accessibility label — this cost
  real time before switching to the direct API call. Even after the
  getter-override fix and confirming the direct-API method works
  correctly (proven against Finder's real, localized icon-button labels),
  the custom labels still don't show up externally on this specific
  local ad-hoc-signed dev build — ruled out a property-storage bug with a
  hardcoded-return-value test. The code is correct, standard AppKit API
  usage; something about this non-Xcode dev-build environment doesn't
  surface it. Worth a real VoiceOver check on an actual installed build
  before fully trusting this.
- **Screenshots added to the docs site** (all captured from real, live
  interactions against the actual database, not staged): auto-pagination
  with a real 600-row table and the Load More button, the friendly
  "Table doesn't exist" error message, the New Connection dialog's fixed
  centering, and the real Touch ID/password system prompt triggered by a
  DELETE (plus confirmed cancelling it blocks the query).
- Shipped as `v0.1.7`.

## Other follow-ups noted during development

- **Dev signing**: `swift build` produces an ad-hoc-signed binary whose
  signature changes on every rebuild, so macOS Keychain re-prompts for the
  saved connection password after each rebuild during development.
  Tried `codesign -s - --force --identifier com.telemetree.app` for a
  stable identifier — confirmed this keeps *relaunches of the same build*
  from re-prompting, but a new build still changes the binary's hash, so
  it likely still re-prompts after actual code changes. Not fully solved;
  not an issue once distributed as a normally-signed app.

## App icon and the DML affected-rows fix

- **App icon, implemented**: `Packaging/icon-source.svg` reuses the docs
  site's nav logo glyph (`docs/index.html`'s `.brand` svg — the
  connection-tree mark, a nod to "Telemetree") scaled 38x onto a purple
  gradient squircle, with stroke widths scaled proportionally rather than
  redrawn as hairlines. That distinction mattered: a cross-session tip
  from GhostBar (who'd shipped a thin-outline icon that turned into an
  illegible smudge at Dock/Spotlight/Raycast sizes) prompted checking this
  one at actual 16px/32px render size before committing, not just at
  full size — it held up because the strokes are proportionally thick,
  not thin. `Packaging/icon-regen.sh` rebuilds `AppIcon.icns` from the SVG
  (via `sips` + `iconutil`, no extra dependency); `Packaging/Info.plist`
  now sets `CFBundleIconFile`. The iconset intermediate PNGs aren't
  committed (regenerable, would just be repo bloat) — only the SVG
  source, the regen script, and the compiled `.icns`.
- **Fixed**: DML affected-rows always showing 0 (noted above as found but
  not fixed). `MySQLDatabaseConnection.execute` now calls MySQLNIO's
  `query(_:onMetadata:)` (prepared-statement protocol,
  COM_STMT_PREPARE/EXECUTE) instead of `simpleQuery` (text protocol,
  COM_QUERY) — the latter never returns an `OK_Packet`; the former does,
  and its `affectedRows` is threaded through when a query returns no rows
  (i.e. any DML). Verified via a clean build; not yet re-verified against
  a live INSERT/UPDATE/DELETE the way the earlier pagination fix was.

## SQL editor: replaced AppKit's native completion entirely

Live testing surfaced two related bugs in the keyword-autocomplete
feature (added earlier in M5): Backspace couldn't correct a wrong
suggestion, and completing against `SQLSyntaxHighlighter.keywords` forced
a real table named `order` to `ORDER` mid-query — "order" is both a
common table name and a SQL keyword (`ORDER BY`), and the completer had
no notion of position (identifier expected vs. keyword expected).

The Backspace bug was first patched narrowly (skip forcing
`complete(nil)` on a deletion), and the case bug by making completions
positional (`identifierPositionKeywords` — after `FROM`/`JOIN`/`INTO`/
`UPDATE`/etc., suggest from a per-connection table-name cache instead of
the keyword list). But testing then surfaced the real underlying issue:
AppKit's `NSTextView.complete(_:)` auto-inserts (and re-cases) the sole
match into the document as soon as typing narrows to one candidate, with
no explicit accept step — there's no supported way to suppress just that
part of it. That's what both bugs actually traced back to.

Replaced `complete(_:)` outright with a small custom popup
(`UI/SQLEditor/CompletionPopup.swift`) that never mutates the document on
its own — only an explicit Tab (intercepted via
`NSTextViewDelegate.textView(_:doCommandBy:)`) accepts a candidate, real
case preserved for table names. Space, Return, and everything else just
behave as if the popup weren't there, since they're not command selectors
AppKit routes through `doCommandBy` at all once the native machinery is
gone. This also made the deletion-guard workaround unnecessary — removed
it along with the old `shouldChangeTextIn` override.

Known gap, not fixed: the popup doesn't auto-dismiss on a stray caret
move (arrow keys past it, or a mouse click elsewhere) — it only closes on
Tab-accept, Escape, or the next text edit recomputing it away. Minor and
not yet reported as an issue in practice.

## Three more fixes from live testing, plus the icon rework (felipepkgs/telemetree#5)

- **UPDATE always confirms now**: `DestructiveSQLGuard` used to exempt any
  UPDATE that had a WHERE clause, on the reasoning that a scoped UPDATE
  is safer than an unscoped one. Reported as "updates aren't requiring
  Touch ID" — the exemption was inconsistent: a scoped UPDATE still
  overwrites real rows, the same way a scoped DELETE does (which was
  never exempt). DELETE/DROP/TRUNCATE/UPDATE all confirm unconditionally
  now; the WHERE-clause check is gone.
- **Statement boundary fix**: `SQLStatementLocator.statement(containing:)`
  attributed the caret position immediately after a `;` to the *next*
  statement (whose range technically starts there, at its leading
  whitespace) rather than the one that just ended. Fixed by checking
  `NSMaxRange(statement.range) == location` first. This is the same
  lookup `currentExecutionTarget()` uses for what Run actually sends, so
  Run was affected too, not just the visual highlight.
- **Statement highlight redesigned**: green background fill
  (`NSColor.systemGreen.withAlphaComponent(0.16)`) plus a solid green
  border, replacing the low-contrast blue-ish `controlAccentColor` tint.
  AppKit's text-attribute system has no per-range border, only fill, so
  the border is a plain `NSView` overlay (`statementBorderView`) added
  as a direct subview of the text view, repositioned from
  `layoutManager.boundingRect(forGlyphRange:in:)` on every highlight
  update so it scrolls and tracks correctly with the text.
- **App icon reworked** from a provided design
  (felipepkgs/telemetree#5): same connection-tree concept, redrawn as a
  fuller 5-node hierarchy glyph with a richer purple gradient (plus a
  subtle radial highlight) instead of the flatter two-stop gradient of
  the first pass. Re-checked at real 16px/32px render size before
  shipping, same as the first icon.

## Statement-highlight border reverted; completion extracted and reused

- **Border dropped**: the green border added alongside the highlight fill
  read as misleading rather than helpful — removed, back to fill only.
  `updateStatementHighlight` also now trims the painted range to start at
  the statement's actual first character (it previously started right
  after the prior statement's `;`, which could include a gap of leading
  whitespace/newlines before the real content).
- **Completion logic extracted**: the Tab-only popup built for the main
  SQL editor was never wired into the snippet editor
  (`SnippetEditorWindowController`) — that window still had the *original*
  `NSTextView.complete(_:)`-based implementation, with the exact same
  forced-uppercase/no-backspace bugs, found live by testing the "create
  snippet" page specifically. Rather than copy the fix a second time,
  pulled the shared logic into `UI/SQLEditor/SQLCompletionController.swift`
  and pointed both editors at it. The snippet editor leaves
  `tableNamesProvider` at its default (empty) — snippets aren't tied to
  one connection, so only keyword completion applies there; the
  identifier-position check still suppresses keyword suggestions in that
  case rather than falling back to something wrong.

## Three open issues closed (#6, #7, #8)

- **#6 — last-clicked database assumed by default**: clicking a database
  node in the sidebar now runs a real `USE \`database\`` on that
  connection's shared connection (`AppState.selectDatabase`) — session
  state on the server, so it applies to every document/tab on that
  connection, not just the one active when it was clicked. Also sets that
  connection active, matching what clicking the connection node itself
  already did. Known gap: table-name completion still lists tables from
  the connection profile's originally-configured database, not whatever
  was last `USE`'d — a reasonable follow-up, not done here.
- **#7 — command palette state bug + "most used"**: `showWindow` cleared
  `searchField.stringValue` *after* `reload()` had already filtered using
  the stale query — the field looked empty on reopen but the row list
  stayed stuck on the previous search's single result until you typed
  something. Reordered so the clear happens first. Also added usage
  tracking (`UserDefaults`, keyed by a stable per-item id) — the palette
  now sorts by use count (ties broken alphabetically), both for the
  empty-query default list and for search results.
- **#8 — completion popup had no accept/dismiss hint**: added a muted
  footer row ("⇥ accept · space dismisses") to `CompletionPopup`. The
  issue asked for Icons8 kbd glyphs specifically; used plain muted text
  instead to avoid pulling in new icon assets for two key names — a
  reasonable-scope call, not a hard blocker if it turns out to matter.

## Other themes discarded for good, column-name autocomplete, two gap fixes

- **Other theme families discarded, not deferred**: tightened the
  Meniscus/Ulm/Instrument/Unibody language in `Theme.swift`, SPEC.md, and
  the docs site — was "explicitly out of scope, not deferred," now just
  states the decision as final and drops it from the public "not built
  yet" list entirely (it's not a roadmap item to list, it's a closed
  decision).
- **Column-name autocomplete, implemented**: `SQLCompletionController`
  now has a `columnNamesProvider` alongside `tableNamesProvider`. In the
  non-identifier-position branch (previously keywords only), it merges
  keyword matches with column matches from
  `referencedTableNames()` — a best-effort regex over `FROM`/`JOIN`
  clauses in the *statement under the caret* (via `SQLStatementLocator`,
  not the whole buffer, so a multi-statement document doesn't leak
  columns from an unrelated statement). `MySQLDatabaseConnection.
  listColumns(table:inDatabase:)` (new — `SHOW COLUMNS FROM`) backs it,
  fetched lazily per table on first ask and cached
  (`cachedColumnsByTable`), since unlike table names there's no small
  fixed set to warm ahead of time.
- **Gap 1 fixed — table/column completion now follows the last-`USE`'d
  database**: previously kept caching against
  `profile.database` (the connection's originally-configured default)
  even after the sidebar's #6 fix switched databases server-side.
  `ConnectionManager` now tracks `currentDatabases: [UUID: String]`
  (initialized to `profile.database` on connect, updated by
  `AppState.selectDatabase` after a successful `USE`), and
  `SQLEditorViewController`'s table-name cache key
  (`cachedTablesKey`) and column fetches both read that instead —
  clearing `cachedColumnsByTable` on a database change, since a
  same-named table in a different database could have different columns.
- **Gap 2 fixed — popup auto-dismisses on a stray caret move**:
  `SQLCompletionController` now tracks `completionAnchor` (the caret
  position `showCompletions` expects next) and hides the popup in the new
  `selectionDidChange()` if the caret ends up anywhere else — arrow keys
  past it, a mouse click elsewhere. Deliberately *not* implemented via an
  `isHandlingTextChange`-style reentrancy flag: whether
  `textViewDidChangeSelection` fires nested inside `textDidChange`'s call
  frame (flag still true) or as a later sibling call within the same
  keystroke (flag already reset by `defer`) isn't something to rely on
  without being able to verify it live — the anchor approach sidesteps
  the ambiguity entirely, since by the time `selectionDidChange` runs,
  `textDidChange` has already updated the anchor either way.

## UX nitpick batch: pagination redesign, exports, dialogs, qualified completion

A round of small UX fixes and one larger feature, done together and
verified against a real 10,000-row seeded table (`telemetree_seed_test`,
in the `telemetree-mysql` Docker container used for local dev) before
shipping:

- **Numbered pagination replaces "Load More"**: page size dropped from
  500 to 100 (`AppState.resultPageSize`). `OpenDocumentState` now tracks
  `currentPage`/`totalRowCount` instead of `hasMorePages`/
  `paginationOffset`; `AppState.goToPage(_:)` replaces
  `loadMoreRows()` and *replaces* the grid's rows rather than appending
  to them. Total count comes from a separate `SELECT COUNT(*) FROM
  (base) AS telemetree_count` fired after the first page loads, so it
  doesn't block showing results. `ResultsGridViewController` shows
  "1-100 of 10,000" (a row range reads better than "Page 1 of 100",
  which was tried first and replaced after testing against the real
  seeded table) plus Prev/Next and individual page buttons, capped at
  10 buttons before falling back to just Prev/Next.
- **Qualified pre-FROM column completion**: `SQLCompletionController`
  gained `allColumnsProvider` — when the statement under the caret has
  no `FROM` yet, completion offers `table.column` across every table
  this connection has cached columns for (warmed proactively in
  `SQLEditorViewController.refreshTableNamesIfNeeded`, sequentially —
  one `SHOW COLUMNS` at a time, since this is a single MySQL
  connection, not a pool). Accepting one inserts just the column and
  appends the matching `FROM \`table\`` to the end of the statement,
  caret staying right at the field, not jumping to the new FROM.
  Getting the caret behavior right took three attempts: (1) insert
  field, append FROM, manually restore the caret — didn't work; (2)
  reorder to append FROM first so the field insert (done last) lands
  the caret naturally — still didn't work, live-tested and confirmed
  broken by the user (this environment's own accessibility automation
  is blocked, so these had to be verified by the user directly rather
  than by me interactively); (3) root cause was two separate
  programmatic `insertText` calls in the same synchronous pass, not
  their order — rebuilt as a single textStorage edit over the whole
  statement (field replaced and FROM appended together, in one
  `insertText` call) followed by one explicit `setSelectedRange`.
  Confirmed working. Marked V1 by the user at this point.
- **Export CSV and JSON**: both next to Copy Results.
  CSV is hand-rolled RFC 4180 quoting; JSON goes through
  `JSONSerialization` rather than a hand-rolled serializer (correct
  escaping for free, at the cost of object key order not being
  preserved — acceptable since JSON object key order isn't semantically
  meaningful anyway). Every value is a JSON string or `null`, since
  `QueryValue` doesn't preserve a numeric/bool distinction at this
  layer — same tradeoff CSV already had.
- **Save Query As**: shown only while a document is still named
  "Untitled Query" (`QueryStore.untitledQueryName`, extracted as a
  named constant so the UI check and the default-name default can't
  drift apart). Rebuilt as a plain custom `NSWindow` sheet instead of
  an `NSAlert` accessory view — the accessory-view version rendered
  broken (overflowing its own dialog bounds) once it grew past a single
  text field to include a folder picker; `NSAlert.accessoryView` sizing
  is a known-flaky combination once it's asked to host more than one
  simple control.
- **New Connection dialog padding fixed**: `NSStackView.edgeInsets` was
  set but visibly not rendering — the fields sat flush against the
  window edges. Switched to explicit constant insets on the constraints
  pinning the stack to its container, which is guaranteed to render
  regardless of whatever edge case made edgeInsets a no-op here.
- **`FROM` now suggests every table immediately**, not just once a
  prefix is typed — `SQLCompletionController.updateCompletions`
  previously required a non-empty current word to show anything;
  the identifier-position branch now also fires on an empty word
  right after `FROM`/`JOIN`/etc.
- **Play icon added to Run** (SF Symbol `play.fill`, no new asset).
- **Font size preference now applies to the results grid and Query
  History's SQL column** — both were hardcoded `FontLibrary.mono(11)`,
  ignoring the Preferences font-size setting entirely; the results grid
  was the one place in the app where changing that setting visibly did
  nothing. Row height in the grid now scales with the chosen size too.

## PostgreSQL and SQLite support added

MySQL was the only engine until now — `DatabaseDriver`/`DatabaseConnection`
were already engine-agnostic protocols, so adding two more meant new
driver implementations, not a redesign.

- **`ConnectionProfile` gained `engine: DatabaseEngine`** (mysql/postgres/
  sqlite) and `filePath` (SQLite only). Decoded via a custom
  `init(from:)`, not synthesized defaults — a missing `engine`/`filePath`
  key in an existing `connections.json` (every profile saved before this
  change) decodes as `.mysql`/`""` explicitly, not a guess about whether
  Swift's Codable synthesis would fall back correctly. This app already
  had a real crash-on-launch incident from a saved-data decode assumption
  once; not repeating that.
- **`PostgresDriver`** (`PostgresNIO`, same vapor-ecosystem library
  family as `MySQLNIO`) and **`SQLiteDriver`** (the system's own
  `libsqlite3` via a raw C module map — `Sources/CSQLite`, a SwiftPM
  `systemLibrary` target with a hand-written modulemap pointing straight
  at the SDK's `sqlite3.h`, not `pkgConfig:` — macOS doesn't ship a
  `sqlite3.pc` file for pkg-config to find even though the SDK always has
  the header + library, a known pain point; the modulemap route
  sidesteps it entirely). No new external dependency for SQLite — it
  ships with macOS already.
- **`ConnectionManager`** now picks the driver per `profile.engine`
  instead of hardcoding `MySQLDriver()`. SQLite skips the Keychain
  password check entirely (no username/password concept).
- **`NewConnectionWindowController`** gained an engine picker; rows
  toggle between server fields (host/port/username/password/database)
  and a single file-path field + "Choose…" panel depending on engine.
- **Real cross-engine differences, not papered over**:
  - Postgres has no session-level `USE` — a connection is bound to one
    database for its lifetime. `AppState.selectDatabase` now only
    attempts `USE` for MySQL; for Postgres/SQLite it's a no-op (was
    previously a guaranteed syntax error for Postgres — session USE just
    doesn't exist there, "switching" means a new connection).
    `PostgresDriver.listTables`/`listColumns` ignore the `database`
    parameter and query the connected database's `public` schema
    directly, documented as such rather than pretending cross-database
    browsing works.
  - Identifier quoting is engine-specific: MySQL/SQLite use backticks,
    Postgres only accepts ANSI double quotes (backtick is a hard syntax
    error there — hit live: `syntax error at or near "` "`` from a query
    still using MySQL-style quoting). Centralized as
    `DatabaseEngine.quoteIdentifier(_:)` and threaded through every call
    site that builds a qualified identifier: the sidebar's table
    double-click preview query, the completion popup's auto-inserted
    `FROM` clause, and `USE`. Found and fixed after the user hit the
    syntax error live, then audited for the same MySQL-only backtick
    pattern already existing in `MySQLDriver` itself (inconsistent, not
    broken — fixed for consistency and because unescaped backticks don't
    handle a legitimately-backtick-containing name).
  - `FriendlyError` now translates Postgres errors too, via
    `PSQLError.serverInfo?[.sqlState]` — the same SQLSTATE-code lookup
    MySQL gets from its own numeric error codes (access denied, database/
    table/column not found, deadlock, lock timeout, duplicate entry,
    syntax error). `isConnectionLost` recognizes Postgres's
    `.clientClosedConnection`/`.serverClosedConnection` codes too. SQLite
    errors come through already reasonably readable from
    `sqlite3_errmsg` — no translation layer added there.
  - Both new drivers verified against real servers before shipping (a
    throwaway `postgres:16` Docker container, a real SQLite file) via a
    temporary standalone executable target exercising the same
    PostgresNIO/CSQLite API calls the real driver files use — not the
    literal driver files themselves (SwiftPM target isolation would have
    needed a bigger restructuring to import them directly from a second
    executable target), and not the app's own GUI (this environment's
    accessibility automation is blocked, so end-to-end verification
    through the actual New Connection dialog needed the user's own
    testing). The temporary target was deleted after verification.

## A real crash, found by the user, root-caused and fixed

`NewConnectionWindowController.buildUI()` called `updateFieldVisibility()`
(to hide the file-path row for the non-default engine) before `mainStack`
— which `updateFieldVisibility()` → `resizeToFitContent()` needs — was
constructed later in the same function. Implicitly-unwrapped optional,
so this was a guaranteed crash on every "New Connection" click, not an
edge case; missed because this environment's accessibility automation
being blocked meant it was never clicked through interactively before
shipping. Fixed two ways: the immediate ordering bug, and the underlying
fragility — `grid`/`mainStack` are real `Optional`s now, not IUO, built
as locals and only assigned to the stored properties once fully
constructed, with the two post-construction methods that use them
guarding against nil instead of force-unwrapping.

## Manual production-readiness pass

Requested after ruling out any existing agent skill as a fit for AppKit
specifically (checked the curated Swift-Agent-Skills list, a GitHub topic
search, and two specifically-named candidates — `claude-apple-dev`,
which claims AppKit but is SwiftUI end to end on inspection, and
`Axiom`, which explicitly scopes itself to "xOS" — iOS/iPadOS/watchOS/
tvOS — and calls macOS out as a support *boundary*, not a target). No
credible AppKit-specific skill exists in the current ecosystem; this was
a grep+read audit instead. Found and fixed:
- `PostgresDriver.listColumns` interpolated a table name into a SQL
  string literal unescaped — a table name containing `'` would break the
  query (injection-shaped, low practical risk since `table` only ever
  comes from this driver's own `listTables()` output today, not raw user
  input, but a real correctness bug regardless).
- `MySQLDriver.listTables`/`listColumns` still used raw unescaped
  backtick interpolation instead of the new `quoteIdentifier` helper —
  the crash-fix section above.
- The `NewConnectionWindowController` IUO fragility — the crash-fix
  section above.
- Postgres/SQLite error messages weren't friendly — the driver-support
  section above.

## Phase-one round: styling pass, inline cell editing, connection labels, session monitor

Four features, prioritized after a competitor scan (TablePlus, DataGrip,
DBeaver, Sequel Ace, Postico, Beekeeper Studio, pgAdmin) and built in
parallel via isolated worktree agents, reviewed and merged one at a time.
Explicitly declined: a single "Run All Statements" action. Deferred to a
later phase: FK click-to-navigate, column-header live filter, EXPLAIN tree
view, SQL formatter, SSH tunnel, CSV/JSON import wizard.

- **Visual polish pass**: `UI/DesignTokens.swift` — a small spacing (4/8/
  12/16/20) and corner-radius (4/6) scale plus a semantic `border` color,
  inspired by shadcn/ui's token approach but scoped to layout/spacing only
  — doesn't touch `Theme.swift` or the Vapor family's own palette. Applied
  to `AboutWindowController`'s padding; that surfaced a real clipping risk
  (padding added with no resize compensation on a fixed-size window),
  fixed with the same `fittingSize`-based resize-to-fit pattern already
  used elsewhere in the app.
- **Inline cell editing**: double-clicking a cell in the results grid now
  edits it in place, gated by `Database/EditableResultDetector` (regex
  single-table-SELECT check) and each driver's new
  `primaryKeyColumns(table:inDatabase:)` — no real primary key, no
  editing, since there'd be no safe way to scope the UPDATE to one row.
  `AppState.updateCell(table:setColumn:oldValue:newValue:whereColumns:
  whereValues:)` runs the UPDATE as its own statement (never routed
  through `executeCurrentSQL`, which replaces the whole displayed
  `QueryResult`) and refreshes via the existing `goToPage` path.
  `AppState.confirmDestructiveQuery` gained a `reason: String` parameter
  (was hardcoded) so the Touch ID prompt can show the specific
  old → new value being written — a lightweight "diff before commit,"
  shown in the prompt text itself rather than a separate diff UI.
  `ResultsGridViewController.controlTextDidEndEditing` always reverts the
  cell to its pre-edit text immediately; the grid never shows an
  unconfirmed value.
- **Connection color labels**: `ConnectionProfile` gained
  `labelColor: LabelColor?`, threaded through the existing custom
  `init(from:)` decoder pattern (`decodeIfPresent(...) ?? default` — this
  app had a real crash-on-launch from a decode assumption once, so every
  new field follows this). `ConnectionManager.setLabelColor` mirrors
  `QueryStore.setLabelColor`. `SidebarViewController`'s `LabelTarget` enum
  gained a `.connection(UUID)` case and its own submenu, using the same
  8-color palette and rendering slot queries/snippets/folders already had
  — connections were the one row kind that couldn't be labeled before
  this.
- **Session / activity monitor**: `DatabaseConnection.activeSessions()
  async throws -> QueryResult` — `SHOW FULL PROCESSLIST` for MySQL,
  `pg_stat_activity` for Postgres; SQLite has no server/session concept
  at all, so the sidebar gates the menu item off for SQLite connections
  rather than calling a method that would just return empty.
  `UI/SessionMonitor/SessionMonitorWindowController` mirrors
  `QueryHistoryWindowController`'s shape: columns rebuilt dynamically from
  the returned `QueryResult` (server-specific, not fixed), a 2.5s
  `Timer.scheduledTimer` while the window is open (invalidated via
  `NSWindow.willCloseNotification`), plus a manual "Refresh Now" button.
  Opened via a connection's "Show Active Sessions…" context-menu item,
  singleton-per-connection like the snippet editor windows.
- **Found and fixed while merging**: a labelDotView hover-restore bug —
  hiding the color dot on hover-in but never un-hiding it on hover-out,
  so a labeled row's dot vanished for good after the first hover. Found
  by the color-coding agent in its own new code path (the connection/
  database refresh-button hover) and fixed there; the same bug already
  existed in a separate, older path (the trash-icon hover for queries/
  snippets/folders) — correctly left alone by that agent as out of its
  scope, then fixed the same way as a small separate follow-up.
- All four features merged into `master` via sequential `git merge` per
  worktree branch; the session-monitor branch conflicted with the
  cell-editing and color-coding branches on `DatabaseDriver.swift`,
  `MySQLDriver.swift`, `PostgresDriver.swift`, and
  `SidebarViewController.swift` (both branches added sibling methods/
  menu items at the same insertion point) — resolved by keeping both
  additions in each file, not by picking one side.

## Foreign key click-to-navigate

Picked as the next phase-two item to pull forward: highest-frequency
motion when actually browsing data, and a natural extension of the
schema-introspection pattern `primaryKeyColumns` already established per
driver.

- `Database/DatabaseDriver.swift` gained `ForeignKeyReference` (column,
  referencedTable, referencedColumn) and
  `DatabaseConnection.foreignKeys(table:inDatabase:)`. MySQL reads
  `information_schema.KEY_COLUMN_USAGE`; Postgres joins
  `table_constraints`/`key_column_usage`/`constraint_column_usage` scoped
  to the `public` schema (same schema assumption `listColumns`/
  `primaryKeyColumns` already make there); SQLite uses `PRAGMA
  foreign_key_list`, whose `table`/`from`/`to` columns map directly to
  referencedTable/column/referencedColumn.
- `ResultsGridViewController` caches `foreignKeysByColumn` per
  (connection, table) — same shape and same `editableTable` gate as the
  primary-key cache, but independent of it: navigating away from a FK
  cell doesn't require a primary key on the table being navigated *from*.
  A cell whose column is a known FK renders in link color with a tooltip
  naming the referenced table.
- **Trigger is ⌥-click, not ⌘-click**: ⌘-click is already bound to
  NSTableView's native multi-row selection toggle (this grid has
  `allowsMultipleSelection`) — reusing it for navigation would silently
  break normal multi-select. Option has no competing meaning in
  NSTableView, so `tableView.action` (fires on every left click,
  including modified ones) gates on `NSEvent.modifierFlags.contains(
  .option)` before doing anything, leaving plain and ⌘-clicks exactly as
  they were.
- Navigating calls `AppState.navigateForeignKey`, which builds `SELECT *
  FROM <referencedTable> WHERE <referencedColumn> = <value> LIMIT 100`
  and runs it via the existing `runQuery` — the same "reuse the active
  tab" behavior the sidebar's table double-click preview already uses,
  not a new always-open-a-new-tab convention.
- No mouse-cursor affordance (pointing-hand cursor on hover) — would need
  a custom NSView + tracking area per cell instead of the current plain
  NSTextField cells; the link-color + tooltip combination was judged
  enough for discoverability given the added complexity that would take.
- **Found live, in the user's first real test**: link-color + tooltip
  alone wasn't discoverable — a real user saw the blue cell and still
  didn't know ⌥-click was the gesture. Fixed by spelling it out in the
  results grid's status-bar row-count label whenever the current result
  has at least one FK column ("42 row(s) · 🔗 ⌥-click a blue cell to
  follow its foreign key") — the one label that's always on screen,
  instead of relying on a hover tooltip nobody's guaranteed to find.
  The 🔗 is the bundled Icons8 "SF Black" `link` glyph
  (`Resources/Icons/link.png`, `AppIcon.link`), not a literal emoji
  character — matches the rest of the icon set's weight, and a plain
  `NSTextField.stringValue` emoji wouldn't have picked up dark-mode
  tinting anyway. Since a template `NSImage` dropped into an
  `NSAttributedString` via `NSTextAttachment` draws flat black (template
  tinting is a control-level behavior, e.g. `NSButton.contentTintColor`,
  not something `NSAttributedString` attachments get automatically), the
  glyph is pre-tinted to `.secondaryLabelColor` with a manual
  lock-focus/`sourceAtop` composite before being attached — otherwise
  it'd have rendered invisible-black against this app's dark chrome.
