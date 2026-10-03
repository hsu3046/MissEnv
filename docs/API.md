# Core API

There is no HTTP API or server.

## EnvDocument

`EnvDocument(source)` exposes entries, diagnostics, duplicate keys and detected line endings. Each entry includes literal value, original UTF-16 key/value/record ranges, physical line number and associated comments. `duplicates` records all repeated key names; `conflictingDuplicates` records only repeated keys with differing values. `reviewCount` adds syntax diagnostics and conflicting key kinds, excluding identical repeated declarations.

- `replacing(entry, key, value)` validates an exact current entry and splices only key/value ranges.
- `deleting(entry)` deletes the exact assignment, including its own ending newline, preserving adjacent comments and sections.
- `adding(key, value)` appends a validated assignment using the document's line ending.
- `validate(key, value)` rejects malformed keys, unclosed quotes, accidental comments and injected assignments.
- `EnvDifference.compare(current, reference)` returns missing-in-current, extra-in-current, changed and same keys. Last duplicate wins for comparison only.

## FileService

- `scan(root, options: EnvScanOptions)` returns discovered EnvFile records, marked project-root URLs and traversal warnings.
- `read(url)` returns the exact bytes, UTF-8 text and modification date.
- `save(text, to: url, expected: snapshot)` throws on disk conflict and returns the original backup URL after a successful coordinated replacement.

Errors have user-facing Korean descriptions. File contents and variable values must never be logged.

## ProjectDiscovery

`discover(in: roots, options: EnvScanOptions)` returns canonical, deduplicated DiscoveredProject records and scan warnings. A record has stable path identity, name, root URL and env files relative to that project. Git directories/worktree files, recognized manifests and Xcode bundles mark roots. Files use the nearest marked ancestor, falling back to their containing folder. Projects without visible env files are omitted, including marked roots and empty scan roots.

## EnvScanOptions

`includeExamples` defaults to false. Scan excludes filenames containing a case-insensitive dot-delimited `example` component (e.g. `.env.example`, `.env.local.example`, `.env.example.production`), while leaving `.env.example-service` and `.env.sample` unchanged. Opting in restores them through the same discovery pipeline. Example-only folders are omitted while examples are excluded, including marked project roots; opting in restores those folders.

## Developer demo configuration

`MISSENV_REGISTRY` overrides the registry file for isolated testing. `MISSENV_DEMO_ROOT` supplies the fixture root when `--demo` is passed. `scripts/demo.sh` sets both inside the ignored `work/` directory. Neither is required for ordinary app use.

## Duplicate warning policy

Warnings group by exact case-sensitive key within one document, never by shared value or across files. Ordinary true/false/0/empty values may repeat across keys. Identical repeated declarations remain separate/editable and receive neutral information instead of a warning. Plain single/double quoted literals compare after removing only their outer quotes; interior whitespace and case remain significant. Backslashes, dollar signs and backticks retain literal syntax because escape/interpolation/command behavior differs between loaders. Never execute values or introduce blanket key-name exemptions. Comparison remains a literal source comparison using the last declaration; this normalization is shared by duplicate warnings and catalog value grouping.


## VariableCatalog

`init(files: [CatalogFile])` creates a Sendable, memory-only index. CatalogFile carries canonical file/project identity, display project name, relative path and parsed document. File identities are deduplicated. `variables` groups exact keys and includes distinct project count, occurrence count and conservative plain-value groups. `aliases` groups meaningful equal values under multiple names across multiple projects, excluding common scalar values. Every occurrence retains its original EnvEntry including exact source ranges/line. Catalog identities use keys or file/entry coordinates, never credential text.

`EnvDocument.plainValueIdentity` exposes the existing outer-quote comparison policy without evaluating values. Read-only file comparison remains literal. `WorkspaceStore.editCatalogOccurrence` validates the indexed entry and exact fresh file bytes, opens it, then begins the existing inline editor. Stale data triggers a visible error and rescan.
