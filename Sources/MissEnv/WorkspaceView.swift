import SwiftUI
import Combine
import MissEnvCore

enum Palette {
    static let accent = Color(red: 0.16, green: 0.48, blue: 0.34)
    static let background = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let border = Color.primary.opacity(0.09)
}

struct WorkspaceView: View {
    @EnvironmentObject private var store: WorkspaceStore
    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationSplitView {
            sidebar.navigationSplitViewColumnWidth(min: 215, ideal: 240, max: 300)
        } detail: {
            VStack(spacing: 0) {
                if !store.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    SearchResultsView()
                } else if store.selectedFile != nil {
                    FileEditorView()
                } else {
                    OverviewView()
                }
            }
            .background(Palette.background)
        }
        .tint(Palette.accent)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("전체 프로젝트에서 변수 검색", text: $store.query)
                        .textFieldStyle(.plain).frame(width: 220)
                        .accessibilityLabel("전체 변수 검색")
                    if !store.query.isEmpty {
                        Button { store.query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                Button(action: store.refresh) { Image(systemName: "arrow.clockwise") }
                    .help("목록 새로고침 · ⌘R").disabled(store.isLoading)
                Button(action: store.addProjectPanel) { Label("폴더 등록", systemImage: "plus") }
                    .help("탐색 폴더 등록 · ⌘O")
                SettingsLink { Image(systemName: "gearshape") }
                    .help("설정 · 사용 설명서 · ⌘,").accessibilityLabel("설정 및 사용 설명서")
            }
        }
        .sheet(isPresented: $store.showSavePreview) { SavePreviewView() }
        .alert("작업을 완료하지 못했습니다", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("확인") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .onReceive(timer) { _ in store.checkForExternalChanges() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "curlybraces").font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Palette.accent).frame(width: 38, height: 38)
                    .background(Palette.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text("MissEnv").font(.system(size: 18, weight: .bold))
                    Text("YOUR ENV, IN ONE PLACE").font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 22)

            ScrollView {
                VStack(alignment: .leading, spacing: 7) {
                    Button { store.selectProject(nil) } label: {
                        HStack {
                            Image(systemName: "square.grid.2x2").frame(width: 20)
                            Text("전체 프로젝트").fontWeight(.medium)
                            Spacer()
                            Text("\(store.inventories.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }.padding(10).contentShape(Rectangle())
                            .background(store.selectedProjectID == nil && store.query.isEmpty ? Palette.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)

                    Text("PROJECTS").font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
                        .padding(.leading, 10).padding(.top, 22).padding(.bottom, 5)
                    ForEach(store.inventories) { inventory in
                        ProjectSidebarItem(inventory: inventory)
                    }
                    if store.projects.isEmpty {
                        Text("탐색 폴더를 등록해\n.env 파일을 모아보세요.")
                            .font(.caption).foregroundStyle(.secondary).lineSpacing(4).padding(10)
                    }
                    if !store.projects.isEmpty {
                        Text("탐색 폴더 · \(store.projects.count)").font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary).padding(.leading, 10).padding(.top, 22)
                        ForEach(store.projects) { root in
                            Label(root.name, systemImage: "folder.badge.gearshape")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).padding(10)
                                .help(root.path)
                                .contextMenu {
                                    Button("Finder에서 보기") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: root.path) }
                                    Button("탐색 폴더 등록 해제", role: .destructive) { store.removeProject(root.id) }
                                }
                        }
                    }
                }.padding(.horizontal, 10)
            }
            Spacer(minLength: 0)
        }.background(Palette.surface.opacity(0.4))
    }


}

struct ProjectSidebarItem: View {
    @EnvironmentObject private var store: WorkspaceStore
    let inventory: ProjectInventory
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Button { expanded.toggle() } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .bold)).frame(width: 14, height: 28)
                }.buttonStyle(.plain).foregroundStyle(.secondary)
                Button { store.selectProject(inventory.id) } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "folder.fill").foregroundStyle(Palette.accent)
                        Text(inventory.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Spacer(minLength: 2)
                        if !inventory.warnings.isEmpty { Image(systemName: "exclamationmark.circle").foregroundStyle(.orange) }
                        else { Text("\(inventory.files.count)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary) }
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
            }.padding(.horizontal, 7).padding(.vertical, 3)
                .background(store.selectedProjectID == inventory.id && store.selectedFile == nil ? Palette.accent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contextMenu {
                    Button("Finder에서 보기") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: inventory.path) }
                }
            if expanded {
                ForEach(inventory.files) { file in
                    Button { store.openFile(file) } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "doc.text").font(.system(size: 11)).foregroundStyle(file.error == nil ? Color.secondary : Color.orange)
                            Text(file.file.relativePath).font(.system(size: 11, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 0)
                            if file.id == store.selectedFile?.id && store.isDirty { Circle().fill(Palette.accent).frame(width: 5, height: 5) }
                        }.padding(.leading, 30).padding(.trailing, 10).padding(.vertical, 8).contentShape(Rectangle())
                            .background(store.selectedFile?.id == file.id ? Palette.accent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    }.buttonStyle(.plain).help(file.file.url.path)
                }
                if inventory.files.isEmpty {
                    Text(inventory.warnings.isEmpty ? ".env 파일 없음" : "폴더 접근을 확인하세요")
                        .font(.caption2).foregroundStyle(.secondary).padding(.leading, 32).padding(.vertical, 6)
                }
            }
        }
    }
}

struct OverviewView: View {
    @EnvironmentObject private var store: WorkspaceStore
    private var shown: [ProjectInventory] { store.selectedInventory.map { [$0] } ?? store.inventories }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("WORKSPACE").font(.system(size: 11, weight: .medium, design: .monospaced)).tracking(2).foregroundStyle(Palette.accent)
                    Text(store.selectedInventory?.name ?? "중요한 정보를 통합 관리").font(.system(size: 30, weight: .bold))
                    Text(store.selectedInventory?.path ?? "프로젝트 환경변수 파일의 검색, 편집, 비교를 한곳에서 쉽게 해보세요")
                        .font(.system(size: 13)).foregroundStyle(.secondary).textSelection(.enabled)
                }.padding(.top, 10)

                HStack(spacing: 16) {
                    MetricCard(title: "프로젝트", number: shown.count, icon: "folder", subtitle: "하위 폴더에서 찾은 프로젝트")
                    MetricCard(title: "환경 파일", number: shown.reduce(0) { $0 + $1.files.count }, icon: "doc.text", subtitle: ".env 및 .env.*")
                    MetricCard(title: "환경변수", number: shown.flatMap(\.files).reduce(0) { $0 + ($1.document?.entries.count ?? 0) }, icon: "curlybraces", subtitle: "원본에서 읽은 변수")
                }
                ForEach(store.scanWarnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }
                if store.projects.isEmpty {
                    VStack(spacing: 18) {
                        Image(systemName: "folder.badge.plus").font(.system(size: 42, weight: .light)).foregroundStyle(Palette.accent)
                        Text("탐색 폴더를 등록하세요").font(.title2.bold())
                        Text("프로젝트 폴더나 여러 프로젝트가 들어 있는 폴더를 선택하세요.\n하위 폴더의 .env 파일까지 찾아드립니다.")
                            .multilineTextAlignment(.center).foregroundStyle(.secondary).lineSpacing(5)
                        Button(action: store.addProjectPanel) { Label("탐색 폴더 등록", systemImage: "plus") }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                    }.frame(maxWidth: .infinity).padding(.vertical, 64)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
                } else if store.selectedProjectID == nil {
                    VariableCatalogView()
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("프로젝트 파일").font(.system(size: 16, weight: .semibold))
                            Spacer()
                            Text("파일을 선택하면 편집할 수 있습니다").font(.caption).foregroundStyle(.secondary)
                        }.padding(.top, 8)
                        if shown.isEmpty && !store.isLoading {
                            ContentUnavailableView("프로젝트를 찾지 못했습니다", systemImage: "folder", description: Text("Git·프로젝트 설정 파일 또는 .env 파일이 있는 하위 폴더를 찾습니다. 탐색 폴더와 접근 권한을 확인하세요."))
                        }
                        VStack(alignment: .leading, spacing: 28) {
                            ForEach(shown) { inventory in
                                ForEach(inventory.warnings, id: \.self) { warning in
                                    Label(warning, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).padding(.horizontal, 20)
                                }
                                ForEach(inventory.files) { file in
                                    Button { store.openFile(file) } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: "folder.fill").font(.title3).foregroundStyle(Palette.accent)
                                            VStack(alignment: .leading, spacing: 5) {
                                                Text(inventory.name).font(.system(size: 15, weight: .semibold))
                                                Text(file.file.url.path).font(.system(size: 10, design: .monospaced))
                                                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                            }
                                            Spacer()
                                            if let error = file.error {
                                                Text(error).font(.caption).foregroundStyle(.orange).lineLimit(1)
                                            } else {
                                                Text("\(file.document?.entries.count ?? 0) variables").font(.caption.monospaced()).foregroundStyle(.secondary)
                                            }
                                        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                    }.buttonStyle(.plain).help(file.file.url.path)
                                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                                        .overlay { RoundedRectangle(cornerRadius: 12).stroke(Palette.border) }
                                }
                            }
                        }
                    }
                }
            }.padding(32)
        }
    }
}

struct MetricCard: View {
    let title: String
    let number: Int
    let icon: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary); Spacer(); Image(systemName: icon).foregroundStyle(Palette.accent) }
            Text("\(number)").font(.system(size: 32, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(subtitle).font(.caption2).foregroundStyle(.tertiary)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(Palette.border) }
    }
}

struct EnvironmentBadge: View {
    let name: String
    private var label: String {
        if name.contains("example") || name.contains("sample") { return "TEMPLATE" }
        if name.contains("production") || name.contains("prod") { return "PRODUCTION" }
        if name.contains("local") { return "LOCAL" }
        if name.contains("test") { return "TEST" }
        if name.contains("development") || name.contains("dev") { return "DEV" }
        if name.contains("staging") { return "STAGING" }
        return "ENV"
    }
    private var color: Color { label == "PRODUCTION" ? .orange : label == "TEMPLATE" ? .secondary : Palette.accent }
    var body: some View {
        Text(label).font(.system(size: 8, weight: .semibold, design: .monospaced)).tracking(0.5)
            .padding(.horizontal, 6).padding(.vertical, 4).foregroundStyle(color)
            .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 4))
    }
}

struct SearchResultsView: View {
    @EnvironmentObject private var store: WorkspaceStore
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("전체 프로젝트 검색").font(.system(size: 24, weight: .bold))
                Text("\(store.searchResults.count)개 결과 · 변수 이름 기준").foregroundStyle(.secondary)
            }.padding(.horizontal, 30).padding(.top, 30)
            if store.searchResults.isEmpty {
                ContentUnavailableView("검색 결과가 없습니다", systemImage: "magnifyingglass", description: Text("다른 변수명을 입력하거나 프로젝트 목록을 새로고침하세요."))
            } else {
                List(store.searchResults) { match in
                    Button { store.openFile(match.file, key: match.entry.key, entryID: match.entry.id) } label: {
                        HStack(alignment: .top, spacing: 16) {
                            Image(systemName: "curlybraces").foregroundStyle(Palette.accent).padding(.top, 3)
                            VStack(alignment: .leading, spacing: 7) {
                                Text(match.entry.key).font(.system(size: 13, weight: .medium, design: .monospaced))
                                Text("\(match.file.projectName) / \(match.file.file.relativePath) · \(match.entry.line)행").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            EnvironmentBadge(name: match.file.file.name)
                            Image(systemName: "arrow.up.right").foregroundStyle(.tertiary)
                        }.padding(.vertical, 10).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }.listStyle(.inset)
            }
            Spacer(minLength: 0)
        }
    }
}
