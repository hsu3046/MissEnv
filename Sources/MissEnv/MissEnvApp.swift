import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var store: WorkspaceStore?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        store?.allowLeavingDocument() == false ? .terminateCancel : .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct MissEnvApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = WorkspaceStore()

    var body: some Scene {
        Window("MissEnv", id: "main") {
            WorkspaceView()
                .environmentObject(store)
                .frame(minWidth: 1060, minHeight: 700)
                .onAppear { delegate.store = store }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in store.checkForExternalChanges() }
        }
        .defaultSize(width: 1320, height: 840)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("탐색 폴더 등록…", action: store.addProjectPanel).keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                Button("변경 저장…", action: store.requestSave).keyboardShortcut("s").disabled(!store.isDirty)
                Button("원본 다시 불러오기", action: store.reloadFromDisk).disabled(store.selectedFile == nil)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("실행 취소", action: store.undo).keyboardShortcut("z").disabled(!store.canUndo)
                Button("다시 실행", action: store.redo).keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!store.canRedo)
            }
            CommandMenu("프로젝트") {
                Button("전체 프로젝트") { store.selectProject(nil) }.keyboardShortcut("1")
                Button("파일 목록 새로고침", action: store.refresh).keyboardShortcut("r").disabled(store.isLoading)
            }
        }
        Settings { SettingsView().environmentObject(store) }
    }
}
