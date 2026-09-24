# Telemetree

> Your queries are work, not scratch paper.

<img width="1800" height="1200" alt="image" src="https://github.com/user-attachments/assets/109733ff-5f1c-4575-bea4-29698e758cf4" />


Telemetree is a native macOS SQL client for MySQL, PostgreSQL and SQLite,
built around persistent, named query documents instead of disposable tabs —
with a real snippet library, statement-aware execution, and a genuinely
native AppKit interface, keyboard-first throughout.

**[felipepkgs.github.io/telemetree](https://felipepkgs.github.io/telemetree/)**

## What it does

- **MySQL, PostgreSQL &amp; SQLite** — three real engine implementations
  (engine-specific identifier quoting, error translation, schema
  browsing), not a MySQL client with the others faked.
- **Query documents, not tabs.** Every query is a named, persistent
  document — close the app and reopen it, and your workspace is exactly
  how you left it.
- **Snippet library.** Nested folders, search, insert-at-cursor. Keep the
  queries you run every week somewhere better than a scratch file.
- **Statement-aware execution.** Run (⌘Return) only ever fires the
  statement under your cursor — or your selection — never the rest of the
  buffer. Multi-statement documents are safe by default.
- **Destructive SQL confirmation.** `DELETE` / `DROP` / `TRUNCATE`, and any
  `UPDATE`, require Touch ID (or your password) before they run.
- **Inline cell editing.** Double-click a result cell (real primary key
  required) to edit it in place — Touch ID confirms the exact old → new
  value before the UPDATE runs.
- **Foreign key click-to-navigate.** Option-click a FK cell to jump to its
  referenced row in the other table, backed by real schema introspection.
- **Session &amp; activity monitor.** Live view of a MySQL/PostgreSQL
  server's active connections and queries, auto-refreshing.
- **Command palette** (`⌘⇧P`) — jump to any query, snippet, connection, or
  action without leaving the keyboard.
- **Query history.** Every run is logged — searchable, reopenable as a new
  document.
- **Color labels.** An 8-color palette for connections, queries, snippets
  and folders, from each row's context menu.
- **Syntax highlighting, themed.** Four color schemes (Default, Dracula,
  Monokai, Solarized Dark) and a choice of Geist Mono / SF Mono / Menlo at
  10–18pt, all live in Preferences.
- **SQL autocomplete** — keywords, real table/column names scoped to the
  statement under your cursor, Tab-only accept. Native AppKit popup, no
  third-party dependency.
- **Numbered pagination.** Large tables page in 100 rows at a time
  ("1-100 of 10,000"), instead of pulling an entire result set into memory.
- **Export CSV/JSON**, alongside plain copy-to-clipboard.
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

Pure Swift Package Manager, no Xcode project required. Targets macOS 14+.

## Docs

- [Site](https://felipepkgs.github.io/telemetree/) — features, themes,
  screenshots, honest shipped-vs-not status
- [Spec](SPEC.md) — milestone roadmap and implementation addenda, updated
  as the app grows

## Credits

Icons (`Sources/Telemetree/Resources/Icons/`) are by
[Icons8](https://icons8.com), used under their free license. Editor and UI
type is [Geist / Geist Mono](https://vercel.com/font).
