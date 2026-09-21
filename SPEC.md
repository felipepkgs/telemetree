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
Fiber**. **Decision: only the Vapor family ships in Telemetree.**
Meniscus/Ulm/Instrument/Unibody are explicitly out of scope, not just
deferred — don't build them without a fresh ask.

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

## Other follow-ups noted during development

- **Dev signing**: `swift build` produces an ad-hoc-signed binary whose
  signature changes on every rebuild, so macOS Keychain re-prompts for the
  saved connection password after each rebuild during development.
  Tried `codesign -s - --force --identifier com.telemetree.app` for a
  stable identifier — confirmed this keeps *relaunches of the same build*
  from re-prompting, but a new build still changes the binary's hash, so
  it likely still re-prompts after actual code changes. Not fully solved;
  not an issue once distributed as a normally-signed app.
- **App icon**: no custom app icon yet; About window and Dock currently
  show the system's generic default icon.
