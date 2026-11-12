import AppKit
import SwiftUI

@main
struct JenkinsMonitorApp: App {
    @State private var viewModel: MonitoringViewModel

    init() {
        _viewModel = State(initialValue: MonitoringViewModel())
        MenuBarJobStatusAligner.install()
    }

    var body: some Scene {
        Window("Jenkins Monitor", id: "main") {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .toolbar) {
                Button("刷新任务") {
                    Task { await viewModel.refreshAll(force: true) }
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }

        Settings {
            SettingsView(viewModel: viewModel)
        }

        MenuBarExtra {
            MenuBarRoot(viewModel: viewModel)
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
                .help(menuBarHelp)
        }
        .menuBarExtraStyle(.menu)
    }

    private var menuBarHelp: String {
        if !viewModel.hasConfiguredServer {
            return "Jenkins Monitor：尚未配置实例"
        }
        return "Jenkins Monitor：\(viewModel.overallStatus.displayName)"
    }
}

private struct MenuBarRoot: View {
    @Bindable var viewModel: MonitoringViewModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        MenuBarStatusView(viewModel: viewModel) {
            showMainWindow()
        }
    }

    private func showMainWindow() {
        if let window = NSApp.windows.first(where: Self.isMainWindow) {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func isMainWindow(_ window: NSWindow) -> Bool {
        if window.identifier?.rawValue == "main" {
            return true
        }
        // 排除菜单栏弹窗、设置和系统面板，只认带完整窗口按钮的主窗口。
        guard !(window is NSPanel) else { return false }
        let mask = window.styleMask
        return mask.contains(.titled)
            && mask.contains(.closable)
            && mask.contains(.miniaturizable)
            && mask.contains(.resizable)
            && window.frame.width >= 800
    }

}
