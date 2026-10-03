# Architecture

## Modules

```text
Sources/MissEnvCore/
  EnvDocument.swift     lossless source parser, exact range edits, file comparison
  FileService.swift     recursive discovery, UTF-8 snapshots, coordinated safe save
  ProjectDiscovery.swift canonical project roots, nearest-owner grouping, cross-root deduplication
  VariableCatalog.swift cross-project key/value groups and exact declaration locations
Sources/MissEnv/
  MissEnvApp.swift      native app, menu shortcuts, termination protection
  WorkspaceStore.swift  folder registry, background indexing, draft and file conflict state
  WorkspaceView.swift   project navigation, overview and global key search
  VariableCatalogView.swift integrated key catalog, shared-value aliases and inline-edit navigation
  FileEditorView.swift  variable inspector/editor, native source editor
  ComparisonView.swift  file comparison and save preview
Tests/MissEnvCoreTests/  parser and real filesystem regression tests
resources/              bundle metadata, app icon, optional sandbox entitlements
scripts/                build, launch and isolated demo
```

## State

`WorkspaceStore` is main-actor isolated. Scanning and indexing run in a detached task with immutable Sendable values. A generation counter prevents stale scans from replacing newer registration state.

Only one file has an active editable draft. Inspector copy/edit/delete share a borderless icon row. Variable addition and editing happen inline in the inspector; there is no variable-edit sheet or instructional paragraph. The bottom status footer and sidebar footer are removed; credits/version remain in Settings. Delete confirmation captures the variable, source snapshot and file identity; stale requests are rejected. Other-file presence shows the selected key in other visible env files of the same project and is hidden when no such files exist. A store-owned VariableDraft captures the exact entry, source and file identity plus pending field input. Pending input contributes to dirty state, survives refresh/search, and is validated before applying or saving. Switching declarations/editor modes resolves pending field changes; switching projects/files or quitting uses the existing save/discard/cancel guard. Cancellation retains the input. Native undo belongs to inline fields until application; applying becomes one source-history step. Switching projects/files or quitting checks dirty state. Structured edits splice original ranges; the raw editor changes the same source. Undo/redo operates on that source and is limited to 100 snapshots. Saving does not replace the current draft with data read back from disk.

The registry is `~/Library/Application Support/vote.aib.missenv/projects.json`. It contains folder IDs, names, paths and security-scoped bookmarks, never environment variable values. Folder access scopes stay active while registered. Local builds are unsandboxed; distribution entitlement templates are provided but a sandboxed distribution has not been validated.

## Project discovery

Registered folders are scan roots, not projects. ProjectDiscovery merges scans across roots and identifies Git roots, recognized language manifests and Xcode project/workspace bundles. Only projects owning env files visible under the current filter are included; projects with no visible env files are omitted. Nested manifests define separate projects; each env file belongs to its nearest marked ancestor. Without a marker, the env file's containing directory is a fallback project. Empty umbrella folders do not contribute to the project count.

Canonical project paths and file paths provide stable identities and deduplicate overlapping registrations. Overview metrics, sidebar counts and project lists all use the discovered inventories. Registered scan folders have their own sidebar section and removal action. The persisted registry format is unchanged. Refresh rebinds only selected-file metadata and preserves draft, snapshot and undo history. Scan failures appear as overview warnings, not fabricated projects.

## Example file preference

`EnvScanOptions.includeExamples` defaults to false. Filtering happens inside FileService before file contents are indexed, so sidebar, overview counts, search, presence checks and comparison candidates share the same result. Project markers remain independent of env-file filtering for ownership, but only groups with visible env files are returned. The Settings toggle persists in UserDefaults under `includeExampleFiles` and immediately starts a new generation-guarded scan. An open example file goes through the normal save/discard/cancel guard before exclusion; cancellation leaves the preference/draft unchanged. Other open drafts survive rescan. Comparison repairs its reference when filtering removes that candidate.

## File safety

Discovery canonicalizes the root (including macOS `/var` vs `/private/var`), does not follow symlinks, excludes common artifacts and descends at most 12 directory levels. Backup/key files are excluded. UTF-8 files up to 2MB are editable.

`EnvDocument` computes all coordinates from the untouched NSString source. It recognizes exported assignments, quoted multiline literals, escaped quotes, backticks and inline comments. Unsupported lines remain in the original source and appear as diagnostics. Duplicate/conflict key sets are derived once per parse. Repeated equal values are informational; only differing values for the same case-sensitive key contribute to the review count. Plain literals ignore surrounding single/double quotes for this check, while escape/expansion/command syntax stays literal. Values are literal syntax; the app does not interpret or execute them.

Save coordinates the write with NSFileCoordinator, compares disk bytes with the opened/saved snapshot, creates a unique original backup, stages bytes beside the original, checks again and atomically replaces it while preserving POSIX permissions. NSFileCoordinator protects cooperating apps; an editor that does not participate can still race between the final byte check and replacement. Hard links, ACLs, ownership and extended attributes have not received dedicated validation. New backups are mode 0600 in a 0700 directory and are not automatically deleted.

External checks only set conflict state. Neither clean nor dirty drafts are automatically reloaded. The user explicitly reloads. Search includes the active unsaved draft; other indexed files update on refresh.

## Integrated variable catalog

The all-project overview replaces redundant file cards with VariableCatalogView; a selected project's overview retains its file cards. VariableCatalog aggregates indexed declarations in the background once per generation-guarded scan. Group names are case-sensitive. Project counts use distinct canonical project IDs, not file or declaration counts. Overlapping file identities are deduplicated; repeated assignments retain exact entry coordinates and remain separately navigable.

The name view offers name-only search and all/multiple-project/different-value/empty-value filters. Shared names sort by project count then key. Expanding a name shows each value and its project/file/line occurrences. Plain outer quotes use the existing conservative equality policy; escapes, dollar signs, backticks, case and interior spaces remain literal. Different values are configuration information, not warnings. All assignments are included, rather than collapsing to the last effective assignment.

The same-value view finds aliases: one meaningful value under different names across multiple projects. Empty/whitespace-only values, finite numeric literals (including hex/octal/binary integers), and true/false, yes/no, on/off, null/nil/none/undefined are excluded only from this alias view. They remain visible in the name view. No expansion or runtime semantics are inferred.

Occurrence selection opens the exact original declaration directly in the existing inline editor. Compare freshly read bytes with the indexed source before using coordinates; reject and refresh a stale catalog instead of choosing another same-name declaration. Failed file reads appear separately and do not generate fictional empty values. Catalog values stay in process memory; registry persistence and logs contain no values. Saving retains the existing review/backup workflow. Batch writes are not implemented.

## Comparison presentation

The comparison table uses a shared measured column layout for its pinned section header and lazy scroll rows in the same viewport. Current-file and reference-file roles have distinct accent/blue columns, separators, and relative paths. Directional status is next to the key: 값 다름, 현재만 있음, 기준만 있음, 동일. Different values come first; each category is sorted by key. Literal values wrap without ellipsis and remain selectable. Common grapheme prefix/suffix boundaries highlight the differing middle interval; missing and empty values use distinct labels. Highlights only decorate text and never change the comparison semantics or source. Only real duplicate conflicts require a short explanatory note.

The save action is labelled 변경 저장; its existing reviewed save workflow is retained. Values are always visible: the eye button, shared reveal state, menu toggle/shortcut and masking branches have been removed across the inspector, variable table, comparison and save preview.


Catalog UI labels: 모든 변수 / 중복되는 값. Custom accessible segments and the adjacent name-search field share a 34pt actual outer height. Filters state the criterion explicitly: 2개 이상 프로젝트에서 사용 / 같은 이름, 다른 값 / 값 없음 또는 공백. Tooltips distinguish declarations with an empty value from absent declarations, exclude 0/false from empty, and explain that value differences can occur within a project and are not errors. Filter counts show unique variable-name counts; row badges show value-kind counts.
