# Telemetree

> Your queries are work, not scratch paper.

Telemetree is a native macOS MySQL client built around persistent, named
query documents instead of disposable tabs — with a real snippet library,
statement-aware execution, and a genuinely native AppKit interface,
keyboard-first throughout.

**[felipepkgs.github.io/telemetree](https://felipepkgs.github.io/telemetree/)**

## What it does

- **Query documents, not tabs.** Every query is a named, persistent
  document — close the app and reopen it, and your workspace is exactly
  how you left it.
- **Snippet library.** Nested folders, search, insert-at-cursor. Keep the
  queries you run every week somewhere better than a scratch file.
- **Statement-aware execution.** Run (⌘Return) only ever fires the
  statement under your cursor — or your selection — never the rest of the
  buffer. Multi-statement documents are safe by default.
- **Destructive SQL confirmation.** `DELETE` / `DROP` / `TRUNCATE`, and any
  `UPDATE` without a `WHERE`, require Touch ID (or your password) before
  they run.
- **Command palette** (`⌘⇧P`) — jump to any query, snippet, connection, or
  action without leaving the keyboard.
- **Query history.** Every run is logged — searchable, reopenable as a new
  document.
- **Syntax highlighting, themed.** Four color schemes (Default, Dracula,
  Monokai, Solarized Dark) and a choice of Geist Mono / SF Mono / Menlo at
  10–18pt, all live in Preferences.
- **SQL keyword autocomplete** — native AppKit completion, no third-party
  dependency.
- **Auto-paginated results.** Large tables page in 500 rows at a time with
  a Load More button, instead of pulling an entire result set into memory.
- **Vapor theme family** — Base, Gold, Silver, and Carbon Fiber, with a real
  pulsing connection-status dot and a woven carbon-fiber texture — native
  chrome, not a skin.
- **Keychain-backed credentials.** Passwords never touch disk in
  plaintext; no account, no cloud, nothing phones home.

## Why I built this

TablePlus-style disposable tabs don't match how queries actually get used —
a query worth running once a week deserves to persist as a real document,
not evaporate when a tab closes. Telemetree is built around that: named
query documents and a snippet library as first-class citizens, not an
afterthought bolted onto a tab strip.

## Install

```sh
brew tap felipepkgs/telemetree
brew install --cask telemetree
```

Ad-hoc signed, not notarized — Gatekeeper will flag the first launch; the
cask clears the quarantine flag automatically. Or build from source:

```sh
swift build
swift run
```

Pure Swift Package Manager, no Xcode project required. Targets macOS 14+,
MySQL only for now.

## Docs

- [Site](https://felipepkgs.github.io/telemetree/) — features, themes,
  screenshots, honest shipped-vs-not status
- [Spec](SPEC.md) — milestone roadmap and implementation addenda, updated
  as the app grows

## Credits

Icons (`Sources/Telemetree/Resources/Icons/`) are by
[Icons8](https://icons8.com), used under their free license. Editor and UI
type is [Geist / Geist Mono](https://vercel.com/font).
