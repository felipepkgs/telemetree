# Telemetree — Spec Addenda

The original product spec (MVP scope, milestones, architecture) was given at
project start and isn't reproduced here. This file tracks additions made
after that point, so they survive context resets.

## Icons — Icons8 (implemented)

- Style: Icons8 "ios" outline style (not "ios-filled" — that read as too
  heavy/blobby; explicitly rejected, including a circled-plus glyph),
  fetched from `img.icons8.com` and bundled locally under
  `Sources/Telemetree/Resources/Icons/*.png` (no runtime network
  dependency). Loaded via `AppIcon` (`UI/AppIcon.swift`), which sets
  `isTemplate = true` so tinting works exactly like SF Symbols did before.
- Current icon map: `add`→plus-math, `connection`→server, `database`→database,
  `table`→data-sheet (NOT the literal "table" slug — that's a kitchen
  table), `folder`→opened-folder, `document`→document, `snippet`→source-code,
  `warning`→error, `close`→multiply (tab close button).
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

Themes (8 total, one shared accent identity each — never reused across
themes): **Vapor** (base/default), **Meniscus** (glassier Vapor),
**Ulm** (Rams/Braun flat matte), **Instrument** (quiet systematic light
mode), **Unibody** (brushed-aluminum hardware look), plus three Vapor
material variants: **Gold**, **Silver**, **Carbon Fiber**.

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
- Applied to: sidebar footer bar, SQL editor toolbar, results grid status
  bar (all via `theme.barFill`/`barBorder`), and the active tab pill in
  the tab bar (`theme.activeSegmentFill`/`activeSegmentText`).
- Switchable via the Theme menu in the menu bar (checkmarks reflect
  current selection via `NSMenuItemValidation` on `MainWindowController`).
- Skipped: Carbon Fiber's woven diagonal-gradient texture from the source
  spec — just the dark tint + red accent, which is the actual identity
  per the spec's own "one accent per theme" rule. Add the weave later via
  a `CAGradientLayer` pattern if it's wanted.

### Not yet built: Meniscus, Ulm, Instrument, Unibody

For each, still needs:
- Background material — translucent `NSVisualEffectView` vibrancy (Vapor
  family, Unibody) vs. flat matte fill (Ulm, Instrument).
- Corner radius per theme — ranges from sharp (Ulm, 3px) to pill-like
  (Meniscus, 20px); Vapor family currently hardcodes 9.
- Icon tinting — dark/glass themes keep flat white template tinting (as
  today); light themes (Ulm, Instrument) need to invert to dark tinted
  icons instead.
- Typography accent — system font weight/tracking only, no custom fonts,
  except Ulm's monospaced row labels (a deliberate exception in the
  source spec, keep it).
- Motion — the dot's pulse stays enabled everywhere except the two
  "precise instrument" themes, Ulm and Instrument (static dot there).

Explicitly dropped for all themes (inapplicable to a windowed macOS app):
Touch Bar global hotkey / panel-pin behavior, the literal digitizer-tracked
"touch dot" concept (reinterpreted as the connection-status dot above),
any Touch-Bar-specific chrome or sizing.

## Milestone 2 addendum: sidebar search

M2's spec listed "search for queries" as a capability but it wasn't built
in that pass. Landed alongside Milestone 3's snippet search instead: one
`NSSearchField` above the sidebar tree filters both the Queries and
Snippets sections by name (flattening matches out of their folder
structure while a search is active; clearing the field restores the
normal nested tree). Connections aren't filtered — no stated need for it.

## Other follow-ups noted during development

- **Security**: prompt for the system password or Touch ID
  (`LocalAuthentication`) before executing destructive SQL (`DELETE`,
  `DROP`, `TRUNCATE`, or `UPDATE`/`DELETE` without a `WHERE` clause).
  User-requested, not yet implemented.
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
