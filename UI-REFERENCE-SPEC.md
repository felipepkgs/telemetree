# Telemetree — Midnight Visual Implementation Spec

**Status:** Implemented locally; compact Dark-mode workspace visually reviewed. Large-window and Light-mode review remain open.

**Platform:** Native macOS, Swift + AppKit

**Identity:** Midnight — Quiet Precision

## Objective

Refine Telemetree's existing database workspace into a polished, precise native macOS tool. This is a **visual-only pass**: the current UX, layout, navigation, controls, interaction behavior, and information architecture are established and must remain unchanged.

The app should feel like a professional instrument: Apple's native craftsmanship, Linear's restraint, and Xcode's technical clarity. Preserve practical density; do not turn the workspace into a dashboard.

## Visual system

Use these as the starting Dark palette. Tune only when needed for readability, contrast, or native control behavior.

| Semantic token | Dark value | Intended use |
| --- | --- | --- |
| Window | `#11151D` | Main window and outer workspace surface |
| Sidebar | `#171C26` | Persistent navigation surface |
| Editor | `#1C222E` | SQL editing surface |
| Elevated | `#252D3B` | Existing controls, selected/raised surfaces |
| Accent | `#A2AFFF` | Telemetree indigo for selection and focus |
| Text primary | `#E7EBF5` | Main content and labels |
| Text secondary | `#9DA7BA` | Supporting labels and quiet telemetry |

Create a coherent semantic Light counterpart using the existing Light appearance; do not remove or replace Light/Dark preferences. Keep GitHub Light/Dark syntax palettes independent from interface appearance. Preserve current editor font and size preferences; use SF Mono as the visual reference/default only where it does not override a user's saved choice.

Indigo should consistently identify active/selected/focused state across existing tabs, sidebar rows, grid selection, and controls. Keep the established green Run button as the primary execution action; its semantic success/run color is an intentional exception to the indigo interaction language.

## Component requirements

- **Sidebar:** Keep the same tree, sections, actions, and navigation. Improve row hierarchy, indentation, icon alignment, and selected-state clarity. Use a subtle indigo selection surface and a restrained edge marker; retain connection identity/status indicators.
- **Tabs and existing toolbars:** Keep all controls in their current locations with their current behavior. Unify active-tab styling with sidebar selection. Clarify primary, secondary, and tertiary visual emphasis without introducing a new toolbar or moving actions.
- **SQL editor:** Preserve all editing, selection, statement-scoped execution, completion, formatting, and keyboard behavior. Keep syntax colors restrained and readable, text calm, and line spacing comfortable. Do not replace the user's chosen font or font size.
- **Results grid:** Preserve sorting, resizing, horizontal/vertical scrolling, copy/export, pagination, inline-edit safety, and foreign-key navigation. Use 12–13 pt regular-weight data text, understated headers/separators, subtle alternating rows, clear focus/selection, and legible NULL styling. Align numeric values only when the underlying type is known reliably; do not guess from string contents.
- **Status bars:** Preserve location, data, and actions. Improve contrast and hierarchy for connection/database, execution duration, row count, and editing state using compact typography and distinct semantic indicators.
- **Custom icons:** Keep every existing Telemetree icon asset, shape, and meaning. Do not replace icons with SF Symbols or another library. Tune only size, alignment, spacing, color, or opacity. SF Symbols are allowed only for genuinely new functionality, which is out of scope here.

## Design and implementation constraints

- Reuse `DesignTokens`, `Theme`, and existing AppKit components; keep the change focused on presentation.
- No UX redesign, new panels, floating command bars, toolbar migration, control relocation, or functionality removal.
- Do not change database behavior, query execution, persistence, search behavior, tab lifecycle, keyboard shortcuts, or accessibility semantics. Visual adjustments must not regress accessibility.
- Avoid generic card/dashboard styling, excessive gradients, glow, oversized corner radii, and unnecessary Liquid Glass. Keep content surfaces solid and easy to read.
- Do not add dependencies or refactor unrelated code.
- If a desired visual adjustment requires changing behavior or layout architecture, leave it unchanged and record the issue in `todo.md` for separate review.

## Implementation areas

Start with the existing UI and theme code; inspect current source before editing:

- `Sources/Telemetree/UI/DesignTokens.swift`
- `Sources/Telemetree/UI/Theme/Theme.swift` and `ThemeStore.swift`
- `Sources/Telemetree/UI/Sidebar/SidebarViewController.swift`
- `Sources/Telemetree/UI/QueryTabs/DocumentTabBarView.swift` and `TabButtonView.swift`
- `Sources/Telemetree/UI/SQLEditor/SQLEditorViewController.swift` and `SQLSyntaxHighlighter.swift`
- `Sources/Telemetree/UI/ResultsGrid/ResultsGridViewController.swift`
- `Sources/Telemetree/UI/WorkspaceStatusBarView.swift`

Keep changes within these visual surfaces unless source inspection shows a directly required theme hookup. Avoid feature/back-end files.

## Visual validation and acceptance

Build and launch the **local Debug app only**. Inspect the actual rendered interface and iterate from screenshots; compiling alone is insufficient.

Use `~/Downloads/current_state_telemetree.png` as the compact baseline (905 × 604 px). Verify at that compact size and a comfortably large window, in both Light and Dark appearances. Confirm:

1. The window, sidebar, editor, and elevated surfaces read as distinct but related layers.
2. Active sidebar row and tab share the same indigo selection language; focus remains visible and accessible.
3. SQL syntax, selection, and caret remain readable against the editor surface.
4. Grid text is balanced at 12–13 pt; long values remain accessible through existing resize/scroll behavior rather than being hidden by aggressive styling.
5. Connection/database and query status remain legible at compact width.
6. Existing custom icons remain recognizable and unchanged in meaning.
7. Existing workflows and controls behave as before; no unrelated features are modified.

Do not commit, release, update marketing screenshots, or change versions as part of this visual pass unless separately requested.
