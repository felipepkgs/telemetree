# Telemetree

Native macOS MySQL client. SwiftUI + AppKit, Swift Package Manager.

## Running

This machine only has the Command Line Tools installed, not Xcode.app. This
SDK's SwiftUI implements `@State`/`@Observable` etc. via a macro plugin that
ships inside Xcode.app, not CLT — so `swift build` fails on any file using
`@State` with "plugin for module 'SwiftUIMacros' not found". This is an
environment limitation, not a code issue (the non-UI code — `Database/` and
`Connections/` — was verified to compile cleanly against MySQLNIO).

To build and run:

1. Install Xcode from the App Store (or `xcode-select -s /Applications/Xcode.app`
   if already installed elsewhere).
2. Open this folder's `Package.swift` in Xcode — it opens as an app project.
3. Press Run. Xcode bundles the SwiftUI `App` into a runnable `.app` automatically.

## Status: Milestone 1

- Native window, sidebar, SQL editor, results grid.
- Add/test/save MySQL connections (password in Keychain, profile metadata in
  `~/Library/Application Support/Telemetree/connections.json`).
- Browse databases → tables in the sidebar; clicking a table runs a `SELECT * LIMIT 100`.
- Run SQL with the Run button or ⌘Return.

Not yet built: persistent query documents/tabs, snippets, history, command
palette, syntax highlighting, execute-selection, transactions. See the spec
for the full milestone list.
