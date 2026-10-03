import AppKit
import Combine
import MissEnvCore

struct ProjectRegistration: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var path: String
    var bookmark: Data?
}

struct IndexedFile: Identifiable, Sendable {
    var id: String { file.id }
    let projectID: String
    let projectName: String
    let file: EnvFile
    let document: EnvDocument?
    let modified: Date?
    let error: String?
}

struct ProjectInventory: Identifiable, Sendable {
    var id: String { project.id }
    var name: String { project.name }
    var path: String { project.url.path }
    let project: DiscoveredProject
    var files: [IndexedFile]
    var warnings: [String]
}

struct SearchMatch: Identifiable {
    var id: String { "\(file.id):\(entry.id)" }
    let file: IndexedFile
    let entry: EnvEntry
}

struct VariableDraft: Identifiable {
    let id = UUID()
    let entry: EnvEntry?
    let source: String
    let fileID: String
    var key: String
    var value: String

    var isChanged: Bool {
        if let entry { return key != entry.key || value != entry.value }
        return !key.isEmpty || !value.isEmpty
    }
}

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published private(set) var projects: [ProjectRegistration] = []
    @Published private(set) var inventories: [ProjectInventory] = []
    @Published private(set) var variableCatalog = VariableCatalog(files: [])
    @Published private(set) var isLoading = false
    @Published private(set) var includeExamples = false
    @Published private(set) var selectedProjectID: String?
    @Published private(set) var scanWarnings: [String] = []
    @Published private(set) var selectedFile: IndexedFile?
    @Published private(set) var source = ""
    @Published private(set) var document = EnvDocument("")
    @Published private(set) var snapshot: FileSnapshot?
    @Published private(set) var diskChanged = false
    @Published var selectedEntryID: Int?
    @Published var query = ""
    @Published var notice: String?
    @Published var errorMessage: String?
    @Published var showSavePreview = false
    @Published var editorMode = EditorMode.variables
    @Published private(set) var variableDraft: VariableDraft?
    @Published private(set) var variableEditError: String?
    @Published private(set) var lastBackup: URL?
    private var registrationsURL: URL
    private var activeScopes: [UUID: URL] = [:]
    private var refreshGeneration = 0
    private var history: [String] = []
    private var future: [String] = []

    enum EditorMode: String, CaseIterable, Identifiable {
        case variables = "변수", source = "원본", compare = "비교"
        var id: String { rawValue }
    }

    var isDirty: Bool { (snapshot.map { source != $0.text } ?? false) || variableDraft?.isChanged == true }
    var isEditingVariable: Bool { variableDraft != nil }
    var files: [IndexedFile] { inventories.flatMap(\.files) }
    var variableCount: Int { files.reduce(0) { $0 + ($1.document?.entries.count ?? 0) } }
    var selectedEntry: EnvEntry? { document.entries.first { $0.id == selectedEntryID } }
    var selectedInventory: ProjectInventory? { inventories.first { $0.id == selectedProjectID } }
    var canUndo: Bool { isEditingVariable || !history.isEmpty }
    var canRedo: Bool { isEditingVariable || !future.isEmpty }

    init() {
        includeExamples = UserDefaults.standard.bool(forKey: "includeExampleFiles")
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = support.appendingPathComponent("vote.aib.missenv", isDirectory: true)
        // A separate registry keeps demo data from polluting the user's real project list.
        if let override = ProcessInfo.processInfo.environment["MISSENV_REGISTRY"], !override.isEmpty {
            registrationsURL = URL(fileURLWithPath: override)
        } else { registrationsURL = folder.appendingPathComponent("projects.json") }
        do {
            if FileManager.default.fileExists(atPath: registrationsURL.path) {
                projects = try JSONDecoder().decode([ProjectRegistration].self, from: Data(contentsOf: registrationsURL))
            }
            for index in projects.indices {
                guard let bookmark = projects[index].bookmark else { continue }
                var stale = false
                do {
                    let url = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
                    _ = url.startAccessingSecurityScopedResource()
                    activeScopes[projects[index].id] = url
                    projects[index].path = url.path
                    if stale { projects[index].bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) }
                } catch {
                    // Retain the registration so the user can reconnect a moved/unavailable folder.
                    errorMessage = "\(projects[index].name) 폴더 접근을 복원하지 못했습니다. 폴더를 다시 등록해 주세요."
                }
            }
        } catch { errorMessage = "프로젝트 목록을 불러오지 못했습니다: \(error.localizedDescription)" }
        if ProcessInfo.processInfo.arguments.contains("--demo") { loadDemoRegistrations() }
        refresh()
    }

    private func loadDemoRegistrations() {
        guard let root = ProcessInfo.processInfo.environment["MISSENV_DEMO_ROOT"] else { return }
        projects = ["atlas-web", "orbit-api", "studio-site"].map { name in
            .init(id: UUID(), name: name, path: URL(fileURLWithPath: root).appendingPathComponent(name).path, bookmark: nil)
        }
    }

    private func persist(_ next: [ProjectRegistration]) throws {
        let folder = registrationsURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Only folder metadata is persisted. Environment variable values stay in the original files.
        try encoder.encode(next).write(to: registrationsURL, options: .atomic)
        projects = next
    }

    func addProjectPanel() {
        let panel = NSOpenPanel()
        panel.title = "탐색 폴더 등록"
        panel.prompt = "등록"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.message = "프로젝트 폴더 또는 여러 프로젝트가 들어 있는 상위 폴더를 선택하세요."
        guard panel.runModal() == .OK else { return }
        addProjects(panel.urls)
    }

    func addProjects(_ urls: [URL]) {
        var next = projects
        var newlyScoped: [(UUID, URL)] = []
        do {
            for url in urls {
                let normalized = url.standardizedFileURL.resolvingSymlinksInPath()
                if next.contains(where: { $0.path == normalized.path }) { continue }
                let id = UUID()
                let started = url.startAccessingSecurityScopedResource()
                do {
                    let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                    next.append(.init(id: id, name: normalized.lastPathComponent, path: normalized.path, bookmark: bookmark))
                    if started { newlyScoped.append((id, url)) }
                } catch {
                    if started { url.stopAccessingSecurityScopedResource() }
                    throw error
                }
            }
            try persist(next)
            for (id, url) in newlyScoped { activeScopes[id] = url }
            refresh()
            notice = "탐색 폴더를 등록했습니다."
        } catch {
            for (_, url) in newlyScoped { url.stopAccessingSecurityScopedResource() }
            errorMessage = "폴더를 등록하지 못했습니다: \(error.localizedDescription)"
        }
    }

    func removeProject(_ id: UUID) {
        guard let registration = projects.first(where: { $0.id == id }) else { return }
        let root = URL(fileURLWithPath: registration.path).standardizedFileURL.resolvingSymlinksInPath().path
        let affectsSelection = selectedProjectID.map { $0 == root || $0.hasPrefix(root == "/" ? "/" : root + "/") } ?? false
        if affectsSelection && !allowLeavingDocument() { return }
        do {
            try persist(projects.filter { $0.id != id })
            if let scope = activeScopes.removeValue(forKey: id) { scope.stopAccessingSecurityScopedResource() }
            if affectsSelection { clearSelection() }
            refresh()
            notice = "목록에서 제거했습니다. 원본 폴더와 파일은 유지됩니다."
        } catch { errorMessage = "목록을 저장하지 못했습니다: \(error.localizedDescription)" }
    }

    func setIncludeExamples(_ include: Bool) {
        guard include != includeExamples else { return }
        if !include, selectedFile?.file.isExample == true {
            // Hiding the current file follows the same draft protection as switching files.
            guard allowLeavingDocument() else { return }
            let projectID = selectedProjectID
            clearSelection()
            selectedProjectID = projectID
        }
        includeExamples = include
        UserDefaults.standard.set(include, forKey: "includeExampleFiles")
        refresh()
        notice = include ? "example 파일을 포함합니다." : "example 파일을 제외합니다."
    }

    func refresh() {
        refreshGeneration += 1
        let generation = refreshGeneration
        let registrations = projects
        let options = EnvScanOptions(includeExamples: includeExamples)
        isLoading = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                let discovery = ProjectDiscovery.discover(in: registrations.map { URL(fileURLWithPath: $0.path) }, options: options)
                let inventories = discovery.projects.map { project -> ProjectInventory in
                    let indexed = project.files.map { file -> IndexedFile in
                        do {
                            let snapshot = try FileService.read(file.url)
                            return .init(projectID: project.id, projectName: project.name, file: file,
                                         document: EnvDocument(snapshot.text), modified: snapshot.modified, error: nil)
                        } catch {
                            return .init(projectID: project.id, projectName: project.name, file: file,
                                         document: nil, modified: nil, error: error.localizedDescription)
                        }
                    }
                    return .init(project: project, files: indexed, warnings: [])
                }
                // Aggregate once per scan, off the main actor. Values remain memory-only.
                let catalog = VariableCatalog(files: inventories.flatMap(\.files).compactMap { file in
                    guard let document = file.document else { return nil }
                    return CatalogFile(id: file.id, projectID: file.projectID, projectName: file.projectName,
                                       relativePath: file.file.relativePath, document: document)
                })
                return (inventories, discovery.warnings, catalog)
            }.value
            guard generation == refreshGeneration else { return }
            inventories = result.0
            scanWarnings = result.1
            variableCatalog = result.2
            // Rebind metadata after discovery without touching an open draft or undo history.
            if let selectedFile, let updated = files.first(where: { $0.id == selectedFile.id }) {
                self.selectedFile = updated
                selectedProjectID = updated.projectID
            } else if selectedFile == nil, selectedInventory == nil {
                selectedProjectID = nil
            }
            isLoading = false
            if selectedFile == nil, ProcessInfo.processInfo.arguments.contains("--demo"), let first = files.first(where: { $0.file.name == ".env.local" }) { openFile(first) }
            checkForExternalChanges()
        }
    }

    func selectProject(_ id: String?) {
        guard allowLeavingDocument() else { return }
        clearSelection()
        selectedProjectID = id
        query = ""
    }

    private func clearSelection() {
        cancelVariableEditing()
        selectedProjectID = nil
        selectedFile = nil
        source = ""
        document = EnvDocument("")
        snapshot = nil
        selectedEntryID = nil
        diskChanged = false
        history = []
        future = []
    }

    @discardableResult
    func openFile(_ file: IndexedFile, key: String? = nil, entryID: Int? = nil, expectedSource: String? = nil) -> Bool {
        // A previous inventory can remain visible while a new scan is finishing.
        guard includeExamples || !file.file.isExample else { return false }
        guard file.id != selectedFile?.id else {
            if let expectedSource, !source.utf8.elementsEqual(expectedSource.utf8) { return rejectStaleCatalog() }
            if let key {
                let target = document.entries.first { $0.key == key && (entryID == nil || $0.id == entryID) }
                guard selectEntry(target?.id) else { return false }
            }
            query = ""
            return true
        }
        guard allowLeavingDocument() else { return false }
        do {
            let loaded = try FileService.read(file.file.url)
            // An overview occurrence must never fall back to a different declaration
            // after an external insertion, deletion or duplicate-key change.
            if let expectedSource, loaded.data != Data(expectedSource.utf8) { return rejectStaleCatalog() }
            cancelVariableEditing()
            selectedProjectID = file.projectID
            selectedFile = file
            snapshot = loaded
            source = loaded.text
            document = EnvDocument(loaded.text)
            selectedEntryID = key.flatMap { key in document.entries.first { $0.key == key && (entryID == nil || $0.id == entryID) }?.id } ?? document.entries.first?.id
            diskChanged = false
            query = ""
            notice = nil
            history = []
            future = []
            return true
        } catch { errorMessage = "파일을 열지 못했습니다: \(error.localizedDescription)"; return false }
    }

    func editCatalogOccurrence(_ occurrence: VariableOccurrence) {
        guard let file = files.first(where: { $0.id == occurrence.fileID }),
              let indexed = file.document, indexed.entries.contains(occurrence.entry) else {
            _ = rejectStaleCatalog()
            return
        }
        guard openFile(file, key: occurrence.entry.key, entryID: occurrence.entry.id, expectedSource: indexed.source),
              selectedEntry == occurrence.entry else { return }
        beginVariableEditing(occurrence.entry)
    }

    private func rejectStaleCatalog() -> Bool {
        errorMessage = "파일이 변경되었습니다. 새로고침한 목록에서 다시 선택하세요."
        refresh()
        return false
    }

    func updateSource(_ next: String) {
        guard next != source else { return }
        history.append(source)
        if history.count > 100 { history.removeFirst() }
        future.removeAll()
        source = next
        document = EnvDocument(next)
    }

    func undo() {
        if isEditingVariable {
            // Inline text edits belong to their field until explicitly applied.
            (NSApp.keyWindow?.firstResponder as? NSTextView)?.undoManager?.undo()
            return
        }
        guard let previous = history.popLast() else { return }
        future.append(source)
        source = previous
        document = EnvDocument(previous)
    }

    func redo() {
        if isEditingVariable {
            (NSApp.keyWindow?.firstResponder as? NSTextView)?.undoManager?.redo()
            return
        }
        guard let next = future.popLast() else { return }
        history.append(source)
        source = next
        document = EnvDocument(next)
    }

    func editEntry(_ entry: EnvEntry?, key: String, value: String, startingSource: String) throws {
        guard startingSource == source else { throw EnvEditError.staleEntry }
        if key != entry?.key, document.entries.contains(where: { $0.key == key && $0.id != entry?.id }) {
            throw NSError(domain: "MissEnv", code: 1, userInfo: [NSLocalizedDescriptionKey: "같은 이름의 변수가 이미 있습니다."])
        }
        let next = try entry.map { try document.replacing($0, key: key, value: value) } ?? document.adding(key: key, value: value)
        updateSource(next)
        selectedEntryID = entry.map(\.id) ?? document.entries.last { $0.key == key }?.id
    }

    func beginVariableEditing(_ entry: EnvEntry?) {
        guard let fileID = selectedFile?.id else { return }
        if let draft = variableDraft, draft.entry?.id == entry?.id { return }
        let index = entry.flatMap { requested in document.entries.firstIndex { $0 == requested } }
        guard entry == nil || index != nil, resolveVariableDraft() else { return }
        let current = index.flatMap { document.entries.indices.contains($0) ? document.entries[$0] : nil }
        selectedEntryID = current?.id
        editorMode = .variables
        variableDraft = .init(entry: current, source: source, fileID: fileID, key: current?.key ?? "", value: current?.value ?? "")
        variableEditError = nil
    }

    func updateVariableKey(_ key: String) { variableDraft?.key = key; variableEditError = nil }
    func updateVariableValue(_ value: String) { variableDraft?.value = value; variableEditError = nil }
    func cancelVariableEditing() { variableDraft = nil; variableEditError = nil }

    @discardableResult
    func applyVariableDraft() -> Bool {
        guard let draft = variableDraft else { return true }
        do {
            // Never apply field input to another file or to coordinates from an older source.
            guard draft.fileID == selectedFile?.id, draft.source == source else { throw EnvEditError.staleEntry }
            if draft.isChanged {
                try editEntry(draft.entry, key: draft.key, value: draft.value, startingSource: draft.source)
            }
            cancelVariableEditing()
            return true
        } catch {
            variableEditError = error.localizedDescription
            // Keep invalid input visible even if save was requested from global search.
            query = ""
            editorMode = .variables
            return false
        }
    }

    @discardableResult
    func selectEntry(_ id: Int?) -> Bool {
        if id == selectedEntryID, variableDraft?.entry != nil { return true }
        // Applying an earlier declaration can shift every later source coordinate.
        let index = document.entries.firstIndex { $0.id == id }
        guard resolveVariableDraft() else { return false }
        selectedEntryID = index.flatMap { document.entries.indices.contains($0) ? document.entries[$0].id : nil }
        return true
    }

    func selectEditorMode(_ mode: EditorMode) {
        guard mode != editorMode, resolveVariableDraft() else { return }
        editorMode = mode
    }

    private func resolveVariableDraft() -> Bool {
        guard variableDraft?.isChanged == true else { cancelVariableEditing(); return true }
        let alert = NSAlert()
        alert.messageText = "입력 중인 변경을 적용할까요?"
        alert.addButton(withTitle: "취소")
        alert.addButton(withTitle: "적용")
        alert.addButton(withTitle: "변경 버리기")
        switch alert.runModal() {
        case .alertSecondButtonReturn: return applyVariableDraft()
        case .alertThirdButtonReturn: cancelVariableEditing(); return true
        default: return false
        }
    }

    func deleteEntry(_ entry: EnvEntry) {
        do {
            updateSource(try document.deleting(entry))
            selectedEntryID = document.entries.first?.id
        } catch { errorMessage = error.localizedDescription }
    }

    func requestSave() {
        guard applyVariableDraft(), isDirty else { return }
        checkForExternalChanges()
        showSavePreview = true
    }

    @discardableResult
    func save() -> Bool {
        guard applyVariableDraft() else { return false }
        guard let file = selectedFile, let expected = snapshot else { return false }
        do {
            let writing = source
            lastBackup = try FileService.save(writing, to: file.file.url, expected: expected)
            // A successful write records only the saved snapshot; it never replaces the current draft.
            snapshot = .init(data: Data(writing.utf8), text: writing, modified: Date())
            diskChanged = false
            showSavePreview = false
            notice = "저장했습니다. 이전 원본의 백업도 만들었습니다."
            refresh()
            return true
        } catch {
            if let fileError = error as? FileServiceError, case .changedOnDisk = fileError { diskChanged = true }
            errorMessage = "저장하지 못했습니다: \(error.localizedDescription)"
            return false
        }
    }

    func reloadFromDisk() {
        guard let file = selectedFile else { return }
        if isDirty {
            let alert = NSAlert()
            alert.messageText = "수정 내용을 버리고 다시 불러올까요?"
            alert.informativeText = "현재 편집 중인 내용은 사라지고 디스크의 원본을 불러옵니다."
            alert.addButton(withTitle: "취소")
            alert.addButton(withTitle: "다시 불러오기")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        do {
            let loaded = try FileService.read(file.file.url)
            cancelVariableEditing()
            snapshot = loaded
            source = loaded.text
            document = EnvDocument(loaded.text)
            diskChanged = false
            selectedEntryID = document.entries.first?.id
            history = []
            future = []
            refresh()
        } catch { errorMessage = "다시 불러오지 못했습니다: \(error.localizedDescription)" }
    }

    func checkForExternalChanges() {
        guard let file = selectedFile, let snapshot else { return }
        do {
            let current = try FileService.read(file.file.url)
            diskChanged = current.data != snapshot.data
        } catch {
            diskChanged = true
            // Keep the draft and expose deletion/permission errors without replacing user edits.
            notice = "원본 파일을 확인할 수 없습니다. 편집 내용은 유지됩니다."
        }
    }

    func allowLeavingDocument() -> Bool {
        guard isDirty else { cancelVariableEditing(); return true }
        let alert = NSAlert()
        alert.messageText = "저장하지 않은 변경이 있습니다."
        alert.informativeText = "\(selectedFile?.file.name ?? "파일")의 수정 내용을 어떻게 할까요?"
        alert.addButton(withTitle: "취소")
        alert.addButton(withTitle: "저장 후 계속")
        alert.addButton(withTitle: "변경 버리기")
        switch alert.runModal() {
        case .alertSecondButtonReturn: return save()
        case .alertThirdButtonReturn: cancelVariableEditing(); return true
        default: return false
        }
    }

    var searchResults: [SearchMatch] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !search.isEmpty else { return [] }
        // Search variable names, never values. Unsaved changes in the current file are included.
        return files.flatMap { file in
            let parsed = file.id == selectedFile?.id ? document : file.document
            return (parsed?.entries ?? []).filter { $0.key.localizedCaseInsensitiveContains(search) }.map { SearchMatch(file: file, entry: $0) }
        }
    }
}
