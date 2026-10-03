import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: WorkspaceStore

    var body: some View {
        TabView {
            general.tabItem { Label("설정", systemImage: "gearshape") }
            manual.tabItem { Label("사용 설명서", systemImage: "book") }
            about.tabItem { Label("앱 정보", systemImage: "info.circle") }
        }.padding(20).frame(width: 580, height: 540).tint(Palette.accent)
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("파일 탐색").font(.title2.bold())
            // Explicit closure avoids a Swift 6.3 actor-isolated method reabstraction crash.
            Toggle("example 파일 포함", isOn: Binding(get: { store.includeExamples }, set: { store.setIncludeExamples($0) }))
            Text(".env.example 같은 예제 파일을 목록·검색·비교에 포함합니다. 변경하면 목록을 새로고침합니다.")
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
        }.padding(24)
    }

    private var manual: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                guide("시작하기", content: "오른쪽 위 + 또는 ⌘O로 프로젝트 폴더나 상위 폴더를 등록하세요. 하위 폴더의 .env 파일도 찾습니다. 환경변수 파일이 있는 프로젝트만 목록에 표시됩니다.")
                guide("전체 환경변수", content: "모든 변수에서 같은 변수명의 프로젝트 수와 값별 사용처를 확인하세요. 사용처를 선택하면 해당 변수를 바로 편집합니다. 중복되는 값에서는 이름이 달라도 같은 값을 쓰는 프로젝트를 찾습니다. 빈 값·숫자·true/false 등 일반 값은 이 보기에서 제외합니다.")
                guide("필터 기준", content: "2개 이상 프로젝트에서 사용: 같은 변수명이 서로 다른 프로젝트에 있습니다.\n같은 이름, 다른 값: 같은 변수명에 값이 2종류 이상 있습니다. 같은 프로젝트의 파일 간 차이도 포함합니다.\n값 없음 또는 공백: 선언된 값 중 하나 이상이 비어 있거나 공백뿐입니다. 0과 false는 제외합니다.\n필터의 숫자는 변수명 개수이며, 프로젝트 간 값 차이는 오류가 아닙니다.")
                guide("편집과 저장", content: "사이드바에서 파일을 고르고 변수를 선택하세요. 연필 버튼으로 인라인 편집하고 적용을 누릅니다. ⌘S 또는 변경 저장으로 변경 내용을 확인한 뒤 원본에 저장합니다. 삭제할 때는 재확인 창이 표시됩니다.")
                guide("파일 비교", content: "비교 탭에서 같은 프로젝트의 다른 환경 파일을 선택하세요. 현재 파일·기준 파일의 값 차이와 각 파일에만 있는 변수를 확인할 수 있습니다. 비교 화면 자체는 파일을 변경하지 않습니다.")
                guide("원본과 백업", content: "값은 원본 파일에서 직접 읽고 씁니다. 매 저장 전에 이전 원본을 같은 폴더의 .MissEnvBackups에 보관합니다. 백업에도 실제 값이 들어 있으므로 해당 폴더를 Git에 올리지 마세요. 외부에서 원본이 바뀌면 덮어쓰기를 차단하고, 미저장 내용은 유지합니다.")
                guide("단축키", content: "⌘O  폴더 등록\n⌘S  변경 저장\n⌘R  목록 새로고침\n⌘1  전체 프로젝트\n⌘Z / ⇧⌘Z  실행 취소 / 다시 실행\n⌘,  설정")
                Link("온라인 사용 설명서", destination: URL(string: "https://github.com/hsu3046/MissEnv/blob/main/docs/USER_GUIDE.md")!)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
        }
    }

    private var about: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("MissEnv", systemImage: "curlybraces.square.fill")
                    .font(.largeTitle.bold()).foregroundStyle(Palette.accent)
                Text("프로젝트 환경변수의 검색, 편집, 비교를 한곳에서.").foregroundStyle(.secondary)
                Text("버전 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0") · macOS 14 이상")
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                Text("제작사 · AIB Inc.").font(.headline)
                Link("www.aib.vote", destination: URL(string: "https://www.aib.vote")!)
                Link("GitHub · 소스 코드", destination: URL(string: "https://github.com/hsu3046/MissEnv")!)
                Link("문의 · 문제 신고", destination: URL(string: "https://github.com/hsu3046/MissEnv/issues")!)
                Text("개인정보").font(.headline)
                Text("계정과 서버 없이 동작합니다. 환경변수 파일과 값은 외부로 전송하지 않으며, 등록 목록에는 폴더 정보만 저장합니다.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("MIT License").font(.headline)
                Text("누구나 개인·상업적 용도로 사용, 수정, 배포할 수 있습니다. 배포 시 저작권과 라이선스 고지를 포함하세요.")
                    .font(.callout).foregroundStyle(.secondary)
                DisclosureGroup("라이선스 전문") {
                    Text(licenseText).font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                }
                Text("© 2026 AIB Inc.").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
        }
    }

    private var licenseText: String {
        guard let url = Bundle.main.url(forResource: "LICENSE", withExtension: nil) else {
            return "라이선스 파일을 찾지 못했습니다. GitHub 저장소의 LICENSE를 확인하세요."
        }
        do { return try String(contentsOf: url, encoding: .utf8) }
        catch { return "라이선스를 읽지 못했습니다. GitHub 저장소의 LICENSE를 확인하세요." }
    }

    private func guide(_ title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(content).font(.callout).foregroundStyle(.secondary).lineSpacing(4).textSelection(.enabled)
        }
    }
}
