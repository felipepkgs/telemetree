# Telemetree — Spec Addenda

The original product spec (MVP scope, milestones, architecture) was given at
project start and isn't reproduced here. This file tracks additions made
after that point, so they survive context resets.

## Icons — Icons8 (implemented)

- Style: Icons8 "ios-filled", fetched from `img.icons8.com` and bundled
  locally under `Sources/Telemetree/Resources/Icons/*.png` (no runtime
  network dependency). Loaded via `AppIcon` (`UI/AppIcon.swift`), which sets
  `isTemplate = true` so `NSImageView.contentTintColor` / button tinting
  works exactly like SF Symbols did before.
- Current icon map: `add`→plus, `connection`→server, `database`→database,
  `table`→data-sheet (NOT the literal "table" slug — that's a kitchen
  table), `folder`→opened-folder, `document`→document, `warning`→error,
  `close`→multiply (tab close button).
- Attribution: About window (Telemetree menu → About Telemetree) credits
  "Icons by Icons8" with a link to icons8.com, per Icons8's linkware
  license terms. See `UI/About/AboutWindowController.swift`.
- Gotcha for future icon swaps: NSImage renders bitmaps at native pixel
  size unless `.size` is set explicitly — SF Symbols did this implicitly,
  plain PNGs don't. `AppIcon` sets a 16×16pt default; don't skip this on
  new icons or buttons balloon to the source image's full resolution.

## Cross-app theme system (spec only — not yet built)

The user maintains a shared visual language across their apps, originally
authored for **GhostBar** (a Touch Bar overlay utility) as an 8-theme
system for a translucent touch-panel. Telemetree is a windowed app, not a
Touch Bar panel, so the literal mechanics don't transfer — this section
maps the *material/palette identity* of each theme onto Telemetree's own
chrome (sidebar, toolbar bars, active-tab highlighting, the connection
status dot already on connection rows) rather than porting it verbatim.

Themes (8 total, one shared accent identity each — never reused across
themes): **Vapor** (base/default), **Meniscus** (glassier Vapor),
**Ulm** (Rams/Braun flat matte), **Instrument** (quiet systematic light
mode), **Unibody** (brushed-aluminum hardware look), plus three Vapor
material variants: **Gold**, **Silver**, **Carbon Fiber**.

For each theme, define:
- Background material — translucent `NSVisualEffectView` vibrancy (Vapor,
  Meniscus, Unibody, the 3 materials) vs. flat matte fill (Ulm, Instrument).
- Bar/chip fill + border + corner radius (sidebar row selection, active
  tab pill, toolbar) — radius ranges from sharp (Ulm, 3px) to pill-like
  (Meniscus, 20px).
- One accent color per theme, applied to: the connection-status dot,
  active-tab/segment highlight fill, and active-segment text color.
- Icon tinting — dark/glass themes keep flat white template tinting (as
  today); light themes (Ulm, Instrument) invert to dark tinted icons.
- Typography accent — system font weight/tracking only, no custom fonts
  (Ulm is the one exception: monospaced row labels). Matches Telemetree's
  own "no unnecessary visual noise" design direction.
- Motion — the connection-status dot's pulse animation stays enabled by
  default, but is disabled (static dot) on the two "precise instrument"
  themes, Ulm and Instrument.

Explicitly dropped (inapplicable to a windowed macOS app):
- Touch Bar global hotkey / panel-pin behavior.
- The literal "touch dot" (digitizer-tracked cursor position) — reinterpreted
  as the existing green/gray connection-status indicator.
- Any Touch-Bar-specific chrome or sizing.

Proposed implementation shape (not yet built):
- A `Theme` type describing the tokens above, plus a small `ThemeStore`
  (Combine `ObservableObject`, persisted like `ConnectionManager`) holding
  the active theme.
- Sidebar/toolbar/tab-bar views read colors/radii from the active theme
  instead of the hardcoded `NSColor`/`CGFloat` literals they use today.
- This is squarely Milestone 5 ("Polish… light/dark mode… Settings")
  territory, and larger than that milestone originally scoped alone — build
  the architecture + Vapor first (closest to the current look), then layer
  in the other 7 rather than attempting all 8 at once.

## Other follow-ups noted during development

- **Security**: prompt for the system password or Touch ID
  (`LocalAuthentication`) before executing destructive SQL (`DELETE`,
  `DROP`, `TRUNCATE`, or `UPDATE`/`DELETE` without a `WHERE` clause).
  User-requested, not yet implemented.
- **Dev signing**: `swift build` produces an ad-hoc-signed binary whose
  signature changes on every rebuild, so macOS Keychain re-prompts for the
  saved connection password after each rebuild during development. Needs a
  stable signing identity (or equivalent) before this stops being a
  nuisance — not an issue once distributed as a normally-signed app.
- **App icon**: no custom app icon yet; About window and Dock currently
  show the system's generic default icon.
