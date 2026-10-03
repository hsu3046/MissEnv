import SwiftUI
import MissEnvCore

struct ComparisonView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @State private var referenceID = ""
    @State private var showSame = false
    private var candidates: [IndexedFile] { (store.selectedInventory?.files ?? []).filter { $0.id != store.selectedFile?.id && $0.document != nil } }
    private var reference: IndexedFile? { candidates.first { $0.id == referenceID } }
    private var differences: [EnvDifference] {
        guard let parsed = reference?.document else { return [] }
        return EnvDifference.compare(current: store.document, reference: parsed)
    }
    private var visible: [EnvDifference] {
        differences.filter { showSame || $0.kind != .same }.sorted {
            let lhs = ComparisonAppearance($0.kind).order
            let rhs = ComparisonAppearance($1.kind).order
            return lhs == rhs ? $0.key < $1.key : lhs < rhs
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Picker("기준 파일", selection: $referenceID) {
                    Text("파일 선택").tag("")
                    ForEach(candidates) { file in Text(file.file.relativePath).tag(file.id) }
                }.frame(maxWidth: 300)
                Spacer()
                Toggle("동일한 값도 표시", isOn: $showSame).toggleStyle(.checkbox).font(.caption)
            }.padding(.horizontal, 22).padding(.vertical, 16)

            if candidates.isEmpty {
                emptyState("비교할 파일이 없습니다", icon: "doc.on.doc", message: "같은 프로젝트의 다른 env 파일이 필요합니다.")
            } else if let reference {
                summary
                ComparisonTable(
                    differences: visible,
                    currentPath: store.selectedFile?.file.relativePath ?? "현재 파일",
                    referencePath: reference.file.relativePath
                )
                if !store.document.conflictingDuplicates.isEmpty || !(reference.document?.conflictingDuplicates.isEmpty ?? true) {
                    Label("중복 변수는 마지막 선언으로 비교합니다.", systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.orange).padding(14)
                }
            } else {
                emptyState("기준 파일을 선택하세요", icon: "arrow.left.arrow.right", message: "비교할 env 파일을 선택하세요.")
            }
        }
        .onAppear(perform: chooseReference)
        .onChange(of: store.selectedFile?.id) { _, _ in chooseReference() }
        .onChange(of: candidates.map(\.id)) { _, _ in
            if reference == nil { chooseReference() }
        }
    }

    private var summary: some View {
        HStack(spacing: 10) {
            ForEach([EnvDifferenceKind.changed, .extra, .missing], id: \.rawValue) { kind in
                let style = ComparisonAppearance(kind)
                HStack(spacing: 6) {
                    Image(systemName: style.icon)
                    Text(style.title)
                    Text("\(differences.filter { $0.kind == kind }.count)").fontWeight(.semibold).monospacedDigit()
                }.font(.caption).foregroundStyle(style.color)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(style.color.opacity(0.09), in: RoundedRectangle(cornerRadius: 6))
            }
            Spacer(minLength: 0)
        }.padding(.horizontal, 22).padding(.bottom, 16)
    }

    private func emptyState(_ title: String, icon: String, message: String) -> some View {
        ContentUnavailableView(title, systemImage: icon, description: Text(message))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func chooseReference() {
        referenceID = (candidates.first { $0.file.name == ".env.example" } ?? candidates.first)?.id ?? ""
    }
}

private struct ComparisonAppearance {
    let kind: EnvDifferenceKind
    init(_ kind: EnvDifferenceKind) { self.kind = kind }
    var title: String {
        switch kind { case .changed: "값 다름"; case .extra: "현재만 있음"; case .missing: "기준만 있음"; case .same: "동일" }
    }
    var icon: String {
        switch kind { case .changed: "arrow.left.arrow.right"; case .extra: "plus.circle"; case .missing: "minus.circle"; case .same: "equal" }
    }
    var color: Color {
        switch kind { case .changed: .orange; case .extra: Palette.accent; case .missing: .blue; case .same: .secondary }
    }
    var order: Int {
        switch kind { case .changed: 0; case .extra: 1; case .missing: 2; case .same: 3 }
    }
}

private struct ComparisonTable: View {
    let differences: [EnvDifference]
    let currentPath: String
    let referencePath: String

    var body: some View {
        GeometryReader { geometry in
            // A pinned header shares the rows' viewport, including native scroller insets.
            let keyWidth = min(240, max(180, geometry.size.width * 0.24))
            let valueWidth = max(0, (geometry.size.width - keyWidth) / 2)
            VStack(spacing: 0) {
                if differences.isEmpty {
                    tableHeader(keyWidth: keyWidth, valueWidth: valueWidth)
                    ContentUnavailableView("모든 변수가 일치합니다", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                            Section {
                                ForEach(differences) { difference in
                                    ComparisonRow(difference: difference, keyWidth: keyWidth, valueWidth: valueWidth)
                                }
                            } header: {
                                tableHeader(keyWidth: keyWidth, valueWidth: valueWidth)
                            }
                        }
                    }
                }
            }
        }.background(Palette.surface)
    }

    private func tableHeader(keyWidth: CGFloat, valueWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text("변수 / 상태").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .padding(16).frame(width: keyWidth, alignment: .leading)
            fileHeading("현재 파일", path: currentPath, color: Palette.accent, width: valueWidth)
            fileHeading("기준 파일", path: referencePath, color: .blue, width: valueWidth)
        }.background {
            HStack(spacing: 0) {
                Color.clear.frame(width: keyWidth)
                Palette.accent.opacity(0.08).frame(width: valueWidth)
                    .overlay(alignment: .leading) { Rectangle().fill(Palette.border).frame(width: 1) }
                Color.blue.opacity(0.08).frame(width: valueWidth)
                    .overlay(alignment: .leading) { Rectangle().fill(Palette.border).frame(width: 1) }
            }
        }.background(Palette.surface)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.border).frame(height: 1) }
    }

    private func fileHeading(_ role: String, path: String, color: Color, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(role, systemImage: "doc.text").font(.system(size: 10, weight: .semibold)).foregroundStyle(color)
            Text(path).font(.system(size: 13, weight: .semibold, design: .monospaced))
                .lineLimit(2).truncationMode(.middle).help(path)
        }.padding(16).frame(width: width, alignment: .leading)
    }
}

private struct ComparisonRow: View {
    let difference: EnvDifference
    let keyWidth: CGFloat
    let valueWidth: CGFloat
    private var style: ComparisonAppearance { ComparisonAppearance(difference.kind) }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 9) {
                Text(difference.key).font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Label(style.title, systemImage: style.icon).font(.system(size: 10, weight: .medium))
                    .foregroundStyle(style.color).padding(.horizontal, 7).padding(.vertical, 4)
                    .background(style.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
            }.padding(16).frame(width: keyWidth, alignment: .leading)
            ComparisonValueCell(value: difference.current, other: difference.reference, color: Palette.accent)
                .padding(16).frame(width: valueWidth, alignment: .leading)
            ComparisonValueCell(value: difference.reference, other: difference.current, color: .blue)
                .padding(16).frame(width: valueWidth, alignment: .leading)
        }
        .background {
            HStack(spacing: 0) {
                Color.clear.frame(width: keyWidth)
                Palette.accent.opacity(difference.kind == .same ? 0.025 : 0.055).frame(width: valueWidth)
                    .overlay(alignment: .leading) { Rectangle().fill(Palette.border).frame(width: 1) }
                Color.blue.opacity(difference.kind == .same ? 0.025 : 0.055).frame(width: valueWidth)
                    .overlay(alignment: .leading) { Rectangle().fill(Palette.border).frame(width: 1) }
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.border).frame(height: 1) }
        .accessibilityElement(children: .contain)
    }
}

private struct ComparisonValueCell: View {
    let value: String?
    let other: String?
    let color: Color

    var body: some View {
        Group {
            if let value {
                if value.isEmpty {
                    Text("빈 값").italic().foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(value == other ? Color.clear : color.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                } else {
                    Text(highlighted(value)).foregroundStyle(.primary).textSelection(.enabled)
                        .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Label("변수 없음", systemImage: "minus").foregroundStyle(.secondary)
            }
        }.font(.system(size: 12, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func highlighted(_ value: String) -> AttributedString {
        var text = AttributedString(value)
        guard value != other else { return text }
        let characters = Array(value)
        let comparison = Array(other ?? "")
        var prefix = 0
        while prefix < min(characters.count, comparison.count), characters[prefix] == comparison[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(characters.count, comparison.count) - prefix,
              characters[characters.count - suffix - 1] == comparison[comparison.count - suffix - 1] { suffix += 1 }
        // Use grapheme boundaries; never normalize, expand, or alter the displayed literal.
        let start = text.characters.index(text.startIndex, offsetBy: prefix)
        let end = text.characters.index(text.startIndex, offsetBy: characters.count - suffix)
        if start < end {
            text[start..<end].backgroundColor = color.opacity(0.22)
            text[start..<end].font = .system(size: 12, weight: .semibold, design: .monospaced)
        } else {
            // A pure insertion in the other value has no changed characters on this side.
            text.backgroundColor = color.opacity(0.15)
        }
        return text
    }
}

struct SavePreviewView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    private var changes: [PreviewLine] {
        let before = (store.snapshot?.text ?? "").components(separatedBy: "\n")
        let after = store.source.components(separatedBy: "\n")
        return after.difference(from: before).map { change in
            switch change {
            case let .insert(offset, element, _): return .init(line: offset + 1, text: element, inserted: true)
            case let .remove(offset, element, _): return .init(line: offset + 1, text: element, inserted: false)
            }
        }.sorted { $0.line == $1.line ? !$0.inserted && $1.inserted : $0.line < $1.line }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "doc.badge.gearshape").foregroundStyle(Palette.accent)
                Text("변경 확인").font(.title2.bold())
                Spacer()
                Text(store.selectedFile?.file.name ?? "").font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
            }
            Text("저장하면 원본 파일에 반영하고, 저장 직전 원본을 .MissEnvBackups에 보관합니다.")
                .font(.caption).foregroundStyle(.secondary)
            if store.diskChanged {
                Label("원본이 외부에서 변경되어 저장할 수 없습니다. 편집 내용을 복사한 뒤 원본을 다시 불러오세요.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
            if !store.document.diagnostics.isEmpty {
                Label("파일에 문법 확인이 필요한 항목이 있습니다. 원본 내용을 확인한 뒤 저장하세요.", systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.orange)
            }
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(changes.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .top, spacing: 12) {
                            Text(line.inserted ? "+" : "−").frame(width: 12)
                            Text("\(line.line)").foregroundStyle(.tertiary).frame(width: 35, alignment: .trailing)
                            Text(line.text).textSelection(.enabled)
                            Spacer(minLength: 16)
                        }.font(.system(size: 12, design: .monospaced)).padding(.vertical, 7).padding(.horizontal, 10)
                            .foregroundStyle(line.inserted ? Palette.accent : Color.red)
                            .background((line.inserted ? Palette.accent : Color.red).opacity(0.06))
                    }
                    if changes.isEmpty { Text("줄바꿈 형식 또는 파일 끝 공백이 변경되었습니다.").foregroundStyle(.secondary).padding() }
                }.frame(minWidth: 660, alignment: .leading)
            }.frame(height: 320).background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
            Divider()
            HStack {
                Text("\(changes.filter(\.inserted).count)행 추가 · \(changes.filter { !$0.inserted }.count)행 삭제").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("취소") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("원본에 저장") { if store.save() { dismiss() } }.buttonStyle(.borderedProminent)
                    .disabled(store.diskChanged || !store.isDirty).keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 740)
    }

    private struct PreviewLine { let line: Int; let text: String; let inserted: Bool }
}
