# Deferred UI / UX Work

**Status:** Implementation complete; Felipe will perform local interaction review.

## Implemented in this pass

- Removed the command-palette Run action because it bypassed editor selection/caret statement scoping.
- In-workspace connection switching uses a cancelable sheet, preserving the workspace when canceled.
- Table browsing creates temporary documents; closing disposes them, and Save As promotes them to persistent queries.
- Search Everywhere already searches saved query names and tables in the active database; no connections/actions scope was added.
- Tab bar horizontally scrolls and brings the active tab into view.
- Completion rows expose candidate name, detail, and selected state to accessibility; mouse/VoiceOver activation accepts a candidate, while typing alone does not.
- Applied Midnight palette surfaces to workspace, tabs, editor active-statement highlight, results background, status bar, and window; grid font size is constrained to 12–13 pt.
- Added a persistence regression test for temporary browse documents and explicit Save As promotion.

## Felipe's local review

- Review switch/cancel behavior, ephemeral browsing/Save As, tab overflow, and completion mouse/VoiceOver interaction.
- Review active database labeling while switching databases on a shared server connection.
- Review compact and large window sizes in Light and Dark themes.
- `swift test` cannot resolve XCTest because the selected Command Line Tools installation has missing framework search paths; Debug `swift build` succeeds.

## Nice to have / separate decisions

- Decide whether Search Everywhere should include connections and actions.
- Consider a command-palette Run action only if it can use the editor's exact selection/caret execution target.
- Revisit toolbar reorganization only as a separately approved UX proposal; it remains excluded from the visual pass.
- Keep launch chooser versus workspace restoration as a separate product decision; launch behavior was not changed.

Preserve existing custom icons, native AppKit behavior, keyboard workflows, accessibility, and user data.
