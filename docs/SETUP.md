# Setup and verification

## Requirements

macOS 14+, Swift 6 toolchain (Xcode recommended). No package installation is needed. All builds and tests use system Apple frameworks. Binary architecture follows the build host (the initial build is arm64).

```bash
swift test
./scripts/build.sh
open build/MissEnv.app
```

The executable target can also be run through SwiftPM, but the app bundle provides the correct name, identifier and icon. The optional sandbox entitlements file is not applied to local builds.

## Manual scenarios

Use `./scripts/demo.sh` or register a disposable folder. The demo contains only invented values and uses an isolated registry.

1. Register two umbrella folders containing three projects. Confirm the overview/sidebar count three projects and the scan-root section counts two folders; relaunch and verify restoration. Register a child root again and verify projects/files are not duplicated.
2. Check a nested `.env.local` is listed, while node_modules and `.MissEnvBackups` are not.
3. Search `DATABASE_URL` globally and open a result in its exact file.
4. Edit a quoted value containing Korean text, `#`, `$&` and newlines. Inspect raw source; surrounding comments and spacing stay intact.
5. Add/delete a variable, undo/redo, and switch files. Verify the save/discard/cancel prompt.
6. Compare against `.env.example`; check missing/extra/changed direction and show-same toggle.
7. Save after reviewing source lines. Check `.MissEnvBackups` contains the previous original.
8. Edit the opened file in another editor while MissEnv has unsaved text. Verify the conflict banner appears and save is blocked. Explicit reload must ask before discarding edits.
9. Verify values remain visible in the list, inspector, comparison and save preview. Open the toolbar gear and verify Settings, User Guide, About and MIT license.
10. Quit with unsaved edits; cancel should leave the app open.

## Limits

UTF-8 only, maximum 2MB per file, maximum discovery depth 12, no symlink traversal. Search is by variable name and is refreshed with ⌘R. Backups are retained until manually removed. Clipboard copies remain until replaced by the system/user. No framework-specific environment merging or code-usage scanning in this version.

## Example file option

In Settings (⌘,), toggle **example 파일 포함**. Default is off. Verify `.env.example` is absent from files/counts/search/comparison, then appears when enabled; relaunch and confirm the preference persists. With unsaved edits in an example file, disable the option and cancel the save/discard prompt: both file and preference should remain active. Undo the edit, then exclude the clean example and confirm the original stays unchanged.
