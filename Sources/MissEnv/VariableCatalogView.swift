import SwiftUI
import MissEnvCore

struct VariableCatalogView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @State private var mode = CatalogMode.names
    @State private var filter = CatalogFilter.all
    @State private var search = ""
    private let controlHeight: CGFloat = 34

    private enum CatalogMode: String, CaseIterable, Identifiable {
        case names = "모든 변수", aliases = "중복되는 값"
        var id: String { rawValue }
    }

    private enum CatalogFilter: String, CaseIterable, Identifiable {
        case all = "전체", shared = "2개 이상 프로젝트에서 사용", different = "같은 이름, 다른 값", empty = "값 없음 또는 공백"
        var id: String { rawValue }
        var explanation: String {
            switch self {
            case .all: "변수 이름별 전체 목록입니다. 숫자는 서로 다른 변수 이름의 개수입니다."
            case .shared: "같은 이름의 변수가 서로 다른 프로젝트 2개 이상에 선언되어 있습니다. 값이 같을 필요는 없으며, 한 프로젝트의 여러 파일은 프로젝트 하나로 셉니다."
            case .different: "같은 변수 이름에 서로 다른 값이 2종류 이상 있습니다. 같은 프로젝트의 파일 간 차이나 중복 선언도 포함하며, 오류를 뜻하지 않습니다. 일반 값의 바깥 따옴표만 다른 경우는 같은 값으로 묶습니다."
            case .empty: "선언 중 하나 이상에 값이 없거나 공백만 있습니다. KEY=, KEY=\"\", KEY='', KEY=\" \" 등이 해당합니다. 0과 false는 비어 있는 값이 아닙니다."
            }
        }
        func includes(_ variable: CatalogVariable) -> Bool {
            switch self {
            case .all: true
            case .shared: variable.projectCount > 1
            case .different: variable.values.count > 1
            case .empty: variable.hasEmptyValue
            }
        }
    }

    private var searchText: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var variables: [CatalogVariable] {
        store.variableCatalog.variables.filter {
            filter.includes($0) && (searchText.isEmpty || $0.key.localizedCaseInsensitiveContains(searchText))
        }
    }
    private var aliases: [CatalogValueGroup] {
        store.variableCatalog.aliases.filter { group in
            searchText.isEmpty || group.keys.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("전체 환경변수").font(.system(size: 16, weight: .semibold))
                Spacer()
                if store.isLoading { ProgressView().controlSize(.small) }
                Text("\(store.variableCatalog.variables.count)개 변수명").font(.caption).foregroundStyle(.secondary)
            }.padding(.top, 8)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) { modePicker; Spacer(minLength: 8); searchField }
                VStack(alignment: .leading, spacing: 12) { modePicker; searchField }
            }
            if mode == .names {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { filterButtons }
                    VStack(alignment: .leading, spacing: 6) { filterButtons }
                }
                if variables.isEmpty {
                    emptyState(title: "표시할 변수가 없습니다", icon: "curlybraces")
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(variables) { variable in CatalogVariableRow(variable: variable) }
                    }
                }
            } else {
                HStack(spacing: 5) {
                    Text("다른 이름으로 같은 값을 사용하는 프로젝트").font(.caption).foregroundStyle(.secondary)
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                        .help("여러 프로젝트에 걸친 서로 다른 변수명을 찾습니다. 빈 값, 숫자, true/false, yes/no, on/off, null/nil/none/undefined는 제외합니다. 값을 실행하거나 확장하지 않습니다.")
                }
                if aliases.isEmpty {
                    emptyState(title: "공유하는 값을 찾지 못했습니다", icon: "link")
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(aliases) { group in CatalogAliasRow(group: group) }
                    }
                }
            }
            ForEach(store.files.filter { $0.error != nil }) { file in
                Label("\(file.projectName) / \(file.file.relativePath) · \(file.error ?? "")", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var modePicker: some View {
        // Native segmented controls retain their intrinsic height; custom segments
        // share the search field's actual outer height instead of adding blank space.
        HStack(spacing: 0) {
            ForEach(CatalogMode.allCases) { option in
                Button { mode = option } label: {
                    Text(option.rawValue).font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity).frame(height: controlHeight)
                        .foregroundStyle(mode == option ? Color.white : Color.primary)
                        .background(mode == option ? Palette.accent : Palette.surface)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityAddTraits(mode == option ? .isSelected : [])
            }
        }.frame(width: 240, height: controlHeight)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay { RoundedRectangle(cornerRadius: 7).stroke(Palette.border) }
            .accessibilityElement(children: .contain).accessibilityLabel("환경변수 보기")
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("변수명 검색", text: $search).textFieldStyle(.plain)
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).help("검색 지우기")
            }
        }.padding(.horizontal, 10).frame(maxWidth: 260).frame(height: controlHeight)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 7))
    }

    private var filterButtons: some View {
        ForEach(CatalogFilter.allCases) { option in
            Button { filter = option } label: {
                HStack(spacing: 5) {
                    Text(option.rawValue)
                    Text("\(store.variableCatalog.variables.filter { option.includes($0) }.count)개 변수").monospacedDigit()
                }.font(.caption).fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .foregroundStyle(filter == option ? Palette.accent : Color.secondary)
                    .background(filter == option ? Palette.accent.opacity(0.12) : Palette.surface, in: RoundedRectangle(cornerRadius: 6))
            }.buttonStyle(.plain).help(option.explanation)
                .accessibilityAddTraits(filter == option ? .isSelected : [])
        }
    }

    private func emptyState(title: String, icon: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 30, weight: .light)).foregroundStyle(.tertiary)
            Text(store.isLoading ? "환경변수를 불러오는 중입니다" : title).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 48)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct CatalogVariableRow: View {
    let variable: CatalogVariable
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 12) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.caption).frame(width: 12)
                    Text(variable.key).font(.system(size: 13, weight: .semibold, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    CatalogCount(text: "\(variable.projectCount) 프로젝트", accented: variable.projectCount > 1)
                    CatalogCount(text: "값 \(variable.values.count)종류", accented: false)
                }.padding(16).contentShape(Rectangle())
            }.buttonStyle(.plain).help(variable.key)
                .accessibilityLabel("\(variable.key), \(variable.projectCount) 프로젝트, \(variable.values.count)개 값, \(expanded ? "접기" : "펼치기")")
            if expanded {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(variable.values) { group in CatalogValueUses(group: group, showsKeys: false) }
                }.padding(.horizontal, 16).padding(.bottom, 16)
            }
        }.background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).stroke(Palette.border) }
    }
}

private struct CatalogAliasRow: View {
    let group: CatalogValueGroup
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { expanded.toggle() } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.caption).frame(width: 12).padding(.top, 3)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(group.keys.joined(separator: " · ")).font(.system(size: 12, weight: .semibold, design: .monospaced)).lineLimit(2)
                        Text(group.value).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    CatalogCount(text: "\(group.projectCount) 프로젝트", accented: true)
                }.padding(16).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if expanded {
                CatalogValueUses(group: group, showsKeys: true).padding(.horizontal, 16).padding(.bottom, 16)
            }
        }.background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).stroke(Palette.border) }
    }
}

private struct CatalogCount: View {
    let text: String
    let accented: Bool
    var body: some View {
        Text(text).font(.caption.monospacedDigit()).foregroundStyle(accented ? Palette.accent : Color.secondary)
            .fixedSize().padding(.horizontal, 7).padding(.vertical, 4)
            .background(accented ? Palette.accent.opacity(0.08) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
    }
}

private struct CatalogValueUses: View {
    let group: CatalogValueGroup
    let showsKeys: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Text(group.isEmpty ? "빈 값" : group.value)
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(group.isEmpty ? Color.secondary : Color.primary)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                Text("\(group.occurrences.count)곳").font(.caption).foregroundStyle(.secondary)
            }.padding(12).background(Palette.background, in: RoundedRectangle(cornerRadius: 6))
                .help("일반 값의 바깥 따옴표만 제거해서 묶습니다. 사용처를 선택하면 원본 구문을 편집합니다.")
            ForEach(group.occurrences) { occurrence in
                CatalogOccurrenceRow(occurrence: occurrence, showsKey: showsKeys)
            }
        }
    }
}

private struct CatalogOccurrenceRow: View {
    @EnvironmentObject private var store: WorkspaceStore
    let occurrence: VariableOccurrence
    let showsKey: Bool
    @State private var hovered = false

    var body: some View {
        Button { store.editCatalogOccurrence(occurrence) } label: {
            HStack(spacing: 10) {
                Image(systemName: "folder").foregroundStyle(Palette.accent)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(occurrence.projectName).fontWeight(.medium)
                        if showsKey { Text(occurrence.entry.key).font(.system(size: 11, design: .monospaced)) }
                    }
                    Text("\(occurrence.relativePath) · \(occurrence.entry.line)행")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "pencil").foregroundStyle(hovered ? Palette.accent : Color.secondary)
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                .background(hovered ? Palette.accent.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 5))
        }.buttonStyle(.plain).onHover { hovered = $0 }
            .help("\(occurrence.fileID) · \(occurrence.entry.line)행 편집")
            .accessibilityLabel("\(occurrence.projectName), \(occurrence.relativePath), \(occurrence.entry.key), \(occurrence.entry.line)행 편집")
    }
}
