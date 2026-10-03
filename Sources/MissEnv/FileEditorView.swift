import SwiftUI
import AppKit
import MissEnvCore

private struct DeleteRequest {
    let entry: EnvEntry
    let source: String
    let fileID: String?
}

struct FileEditorView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @State private var filter = ""
    @State private var deleting: DeleteRequest?
    @State private var pathHovered = false

    private var entries: [EnvEntry] {
        store.document.entries.filter { filter.isEmpty || $0.key.localizedCaseInsensitiveContains(filter) }
    }
    private var otherFiles: [IndexedFile] {
        (store.selectedInventory?.files ?? []).filter { $0.id != store.selectedFile?.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if store.diskChanged {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("외부에서 원본이 변경되었습니다. 현재 편집 내용은 유지됩니다.")
                    Spacer()
                    Button("원본 다시 불러오기", action: store.reloadFromDisk)
                }.font(.caption).foregroundStyle(.orange).padding(12).background(Color.orange.opacity(0.08))
            }
            HStack(spacing: 16) {
                Picker("편집 방식", selection: Binding(get: { store.editorMode }, set: store.selectEditorMode)) {
                    ForEach(WorkspaceStore.EditorMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                }.pickerStyle(.segmented).frame(width: 220)
                Spacer()
                Text("\(store.document.entries.count) variables").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                if store.document.reviewCount > 0 {
                    Label("\(store.document.reviewCount)개 확인 필요", systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.orange)
                        .help("구문 경고 \(store.document.diagnostics.count)개 · 동일 변수명 값 충돌 \(store.document.conflictingDuplicates.count)개")
                }
            }.padding(.horizontal, 24).padding(.vertical, 16)
            Divider()

            switch store.editorMode {
            case .variables: variables
            case .source:
                VStack(spacing: 0) {
                    HStack {
                        Text("원본 구문을 그대로 편집합니다. 변경은 저장할 때 파일에 적용됩니다.")
                        Spacer()
                    }.font(.caption).foregroundStyle(.secondary).padding(14).background(Palette.surface)
                    CodeTextEditor(text: Binding(get: { store.source }, set: { store.updateSource($0) }))
                        .id(store.selectedFile?.id)
                    diagnostics
                }
            case .compare: ComparisonView()
            }
        }
        .alert("이 변수를 삭제할까요?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { request in
            Button("취소", role: .cancel) { }
            Button("삭제", role: .destructive) {
                // Confirm the exact file and declaration captured when deletion was requested.
                guard request.fileID == store.selectedFile?.id, request.source == store.source else {
                    store.errorMessage = EnvEditError.staleEntry.localizedDescription
                    return
                }
                store.deleteEntry(request.entry)
            }
        } message: { request in
            Text("\(request.entry.key) (\(request.entry.line)행)을 삭제할까요? 저장 전에는 원본 파일이 바뀌지 않습니다.")
        }
        .onChange(of: store.selectedFile?.id) { _, _ in filter = ""; pathHovered = false }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "folder").foregroundStyle(Palette.accent)
                Text(store.selectedFile?.projectName ?? "").fontWeight(.medium)
                Text("/").foregroundStyle(.tertiary)
                HStack(spacing: 0) {
                    if let path = store.selectedFile?.file.relativePath, let slash = path.lastIndex(of: "/") {
                        Text(String(path[...slash])).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Button {
                        if let url = store.selectedFile?.file.url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    } label: {
                        Text(store.selectedFile?.file.name ?? "")
                            .foregroundStyle(pathHovered ? Palette.accent : Color.secondary).underline(pathHovered)
                            .lineLimit(1).truncationMode(.middle)
                    }.buttonStyle(.plain)
                        .onHover { pathHovered = $0 }
                        .animation(.easeInOut(duration: 0.15), value: pathHovered)
                        .help("Finder에서 파일 보기 · \(store.selectedFile?.file.url.path ?? "")")
                        .accessibilityLabel(store.selectedFile?.file.name ?? "파일")
                }.font(.system(size: 11, design: .monospaced))
                Spacer()
            }.font(.system(size: 11))
            HStack(spacing: 12) {
                Text(store.selectedFile?.file.name ?? "").font(.system(size: 28, weight: .bold, design: .monospaced))
                if let name = store.selectedFile?.file.name { EnvironmentBadge(name: name) }
                if store.isDirty { Text("수정됨").font(.caption).foregroundStyle(Palette.accent) }
                Spacer()
                Button(action: store.requestSave) {
                    Label("변경 저장", systemImage: "checkmark").frame(height: 32)
                }
                    .buttonStyle(.borderedProminent).disabled(!store.isDirty).help("⌘S")
            }
        }.padding(24).background(Palette.surface)
    }

    private var variables: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    HStack(spacing: 7) {
                        Image(systemName: "line.3.horizontal.decrease").foregroundStyle(.secondary)
                        TextField("이 파일에서 변수 찾기", text: $filter).textFieldStyle(.plain).font(.system(size: 12))
                    }
                    Spacer()
                    Button { store.beginVariableEditing(nil) } label: { Label("변수 추가", systemImage: "plus") }
                        .buttonStyle(.borderless).font(.caption)
                }.padding(.horizontal, 18).padding(.vertical, 14)
                HStack {
                    Text("VARIABLE NAME").frame(width: 220, alignment: .leading)
                    Text("VALUE").frame(maxWidth: .infinity, alignment: .leading)
                    Text("LINE").frame(width: 32)
                }.font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(.tertiary)
                    .padding(.horizontal, 20).padding(.vertical, 10).background(Palette.surface.opacity(0.6))
                Divider()
                if entries.isEmpty {
                    ContentUnavailableView(filter.isEmpty ? "변수가 없습니다" : "일치하는 변수가 없습니다", systemImage: "curlybraces", description: Text(filter.isEmpty ? "변수를 추가하거나 원본 탭에서 파일을 확인하세요." : "다른 변수명으로 검색하세요."))
                } else {
                    List(selection: Binding(get: { store.selectedEntryID }, set: { store.selectEntry($0) })) {
                        ForEach(entries) { entry in
                            HStack(spacing: 14) {
                                HStack(spacing: 7) {
                                    Text(entry.key).font(.system(size: 11, weight: .medium, design: .monospaced)).lineLimit(1)
                                    if store.document.conflictingDuplicates.contains(entry.key) { Image(systemName: "exclamationmark.circle").foregroundStyle(.orange) }
                                }.frame(width: 220, alignment: .leading)
                                Text(entry.value.isEmpty ? "비어 있음" : entry.value.replacingOccurrences(of: "\n", with: " ↵ "))
                                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(entry.value.isEmpty ? Color.orange : Color.secondary)
                                    .lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                                Text("\(entry.line)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary).frame(width: 32)
                            }.padding(.vertical, 9).tag(entry.id)
                                .onTapGesture(count: 2) { store.beginVariableEditing(entry) }
                                .contextMenu {
                                    Button("편집") { store.beginVariableEditing(entry) }
                                    Button("변수명 복사") { copy(entry.key) }
                                }
                        }
                    }.listStyle(.plain)
                }
                diagnostics
            }.frame(minWidth: 440, maxWidth: .infinity)
            inspector.frame(minWidth: 260, idealWidth: 290, maxWidth: 360)
                .background(Palette.surface)
        }
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("VARIABLE DETAILS").font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(.tertiary)
                if let draft = store.variableDraft {
                    InlineVariableEditor(draftID: draft.id)
                } else if let entry = store.selectedEntry {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "curlybraces.square").font(.system(size: 26, weight: .light)).foregroundStyle(Palette.accent)
                        Text(entry.key).font(.system(size: 15, weight: .semibold, design: .monospaced)).textSelection(.enabled)
                        Text("\(entry.line)행 · \(store.selectedFile?.file.name ?? "")").font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        detailLabel("값")
                        Text(entry.value.isEmpty ? "비어 있음" : entry.value)
                            .font(.system(size: 12, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12).background(Palette.background, in: RoundedRectangle(cornerRadius: 7))
                    }
                    HStack(spacing: 18) {
                        Button { copy(entry.value) } label: { Label("복사", systemImage: "doc.on.doc") }.help("값 복사")
                        Button { store.beginVariableEditing(entry) } label: { Label("편집", systemImage: "pencil") }.help("편집")
                        Button(role: .destructive) {
                            deleting = .init(entry: entry, source: store.source, fileID: store.selectedFile?.id)
                        } label: { Label("삭제", systemImage: "trash") }.help("변수 삭제 · 확인 필요")
                    }.labelStyle(.iconOnly).buttonStyle(.plain).font(.system(size: 14))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    if !entry.comment.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            detailLabel("주석")
                            Text(entry.comment).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled).lineSpacing(4)
                        }
                    }
                    if !otherFiles.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 13) {
                            detailLabel("다른 환경 파일의 선언 여부")
                            ForEach(otherFiles) { file in
                                let present = file.document?.entries.contains { $0.key == entry.key } ?? false
                                Button { store.openFile(file, key: entry.key) } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: file.error != nil ? "exclamationmark.circle" : present ? "checkmark.circle.fill" : "minus.circle")
                                            .foregroundStyle(file.error != nil ? Color.orange : present ? Palette.accent : Color.secondary)
                                        Text(file.file.relativePath).font(.system(size: 10, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                                        Spacer(minLength: 0)
                                        Text(file.error != nil ? "오류" : present ? "있음" : "누락").font(.system(size: 9)).foregroundStyle(.secondary)
                                    }
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    if store.document.conflictingDuplicates.contains(entry.key) {
                        let lines = store.document.entries.filter { $0.key == entry.key }.map { String($0.line) }.joined(separator: ", ")
                        Label("같은 변수명에 서로 다른 값이 선언되어 있습니다. 선언 위치: \(lines)행. 적용되는 값은 사용하는 로더와 선언 순서에 따라 달라질 수 있습니다.", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    } else if store.document.duplicates.contains(entry.key) {
                        Label("동일한 값으로 반복 선언되어 있습니다.", systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text("변수를 선택하세요.").font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 22)
        }
    }

    @ViewBuilder private var diagnostics: some View {
        if !store.document.diagnostics.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(store.document.diagnostics.prefix(3)) { diagnostic in
                    Label("\(diagnostic.line)행: \(diagnostic.message)", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
                }
                if store.document.diagnostics.count > 3 { Text("외 \(store.document.diagnostics.count - 3)개 · 원본 탭에서 확인하세요").font(.caption2).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(Color.orange.opacity(0.06))
        }
    }

    private func detailLabel(_ title: String) -> some View { Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary) }
    private func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
}

struct InlineVariableEditor: View {
    @EnvironmentObject private var store: WorkspaceStore
    let draftID: UUID
    @FocusState private var keyFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("변수명").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                TextField("VARIABLE_NAME", text: Binding(get: { store.variableDraft?.key ?? "" }, set: store.updateVariableKey))
                    .textFieldStyle(.plain).font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .focused($keyFocused)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("값").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                CodeTextEditor(text: Binding(get: { store.variableDraft?.value ?? "" }, set: store.updateVariableValue), allowsNativeUndo: true)
                    .id(draftID).frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            if let error = store.variableEditError {
                Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.red)
            }
            HStack(spacing: 18) {
                Button("취소", action: store.cancelVariableEditing)
                Button("적용") { store.applyVariableDraft() }
                    .foregroundStyle(Palette.accent).disabled(store.variableDraft?.key.isEmpty != false)
            }.buttonStyle(.plain).font(.caption.weight(.medium))
        }
        .onAppear { keyFocused = true }
        .onChange(of: draftID) { _, _ in keyFocused = true }
    }
}

/// NSTextView disables smart quotes/dashes so editing never silently changes dotenv syntax.
struct CodeTextEditor: NSViewRepresentable {
    @Binding var text: String
    var allowsNativeUndo = false

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        let editor = NSTextView(frame: .zero)
        editor.delegate = context.coordinator
        editor.isRichText = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.isGrammarCheckingEnabled = false
        editor.allowsUndo = allowsNativeUndo
        editor.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        editor.textColor = .labelColor
        editor.backgroundColor = .textBackgroundColor
        editor.textContainerInset = NSSize(width: 16, height: 16)
        editor.minSize = .zero
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.string = text
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? NSTextView, editor.string != text else { return }
        let selection = editor.selectedRange()
        context.coordinator.updating = true
        editor.string = text
        editor.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
        context.coordinator.updating = false
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeTextEditor
        var updating = false
        init(_ parent: CodeTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard !updating, let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }
    }
}
