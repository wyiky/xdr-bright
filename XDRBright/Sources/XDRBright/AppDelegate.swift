import AppKit
import Foundation
import HDRBrightness
import OSLog

/// 常驻菜单栏的 XDR 增亮工具。
///
/// 与 SparkMiniMonitor 共用同一个 `HDRBrightness` 核心包：
/// gamma 表（256 采样）+ 1×1 EDR 头空间窗口。
/// 额外加入 BrightIntosh 同款的“漂移自愈”：每 2 秒核对一次 gamma 末端，
/// 被系统或别的 App 改掉就自动重新施加。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let controller = HDRBrightnessController()
    private let headroom = EDRHeadroomWindow()
    private let logger = Logger(subsystem: "local.xdrbright", category: "app")

    private static let levelKey = "XDRBrightLevel"
    private static let loginLabel = "local.xdrbright.app"
    private static let presetLevels: [(level: Int, title: String)] = [
        (30, "一档（30%）"),
        (50, "二档（50%）"),
    ]

    private var level: Int
    private var isOn = false
    private var driftTimer: Timer?

    override init() {
        let saved = UserDefaults.standard.integer(forKey: Self.levelKey)
        if Self.presetLevels.contains(where: { $0.level == saved }) {
            level = saved
        } else if saved > 0 && saved < 50 {
            level = 30
        } else {
            level = 50
        }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "sun.max",
                accessibilityDescription: "XDR Bright"
            )
        }
        rebuildMenu()

        // 开发用：启动即开启，便于外部脚本验证漂移自愈。
        if CommandLine.arguments.contains("--start-on") {
            turnOn()
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reapplyIfNeeded() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reapplyIfNeeded() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        driftTimer?.invalidate()
        driftTimer = nil
        if isOn {
            controller.restore()
        }
    }

    // MARK: - 增亮控制

    private func turnOn() {
        let gain = HDRBrightnessController.gain(forLevel: level)
        headroom.show(headroom: CGFloat(gain))
        switch controller.apply(level: level) {
        case .success:
            isOn = true
            logger.notice("boost on level=\(self.level, privacy: .public)")
            startDriftTimer()
        case let .failure(error):
            logger.error("boost failed: \(error.description, privacy: .public)")
            presentError(error.description)
        }
        rebuildMenu()
    }

    private func turnOff() {
        switch controller.restore() {
        case .success:
            isOn = false
            headroom.hide()
        case let .failure(error):
            logger.error("restore failed: \(error.description, privacy: .public)")
            presentError(error.description)
        }
        driftTimer?.invalidate()
        driftTimer = nil
        rebuildMenu()
    }

    private func startDriftTimer() {
        driftTimer?.invalidate()
        // 与 BrightIntosh 一致的 2 秒核对节奏。
        driftTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reapplyIfNeeded() }
        }
        driftTimer?.tolerance = 0.5
    }

    private func reapplyIfNeeded() {
        guard isOn else { return }
        guard controller.needsReapply(level: level) else { return }
        logger.notice("gamma drifted; reapplying level=\(self.level, privacy: .public)")
        let gain = HDRBrightnessController.gain(forLevel: level)
        headroom.show(headroom: CGFloat(gain))
        _ = controller.apply(level: level)
    }

    // MARK: - 菜单

    private func rebuildMenu() {
        let menu = NSMenu()

        let toggle = NSMenuItem(
            title: isOn ? "关闭 HDR 增亮" : "开启 HDR 增亮",
            action: #selector(toggleBoost),
            keyEquivalent: "b"
        )
        toggle.target = self
        toggle.state = isOn ? .on : .off
        menu.addItem(toggle)

        menu.addItem(.separator())

        for preset in Self.presetLevels {
            let item = NSMenuItem(
                title: preset.title,
                action: #selector(selectLevel(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = preset.level
            item.state = preset.level == level ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let login = NSMenuItem(
            title: "登录时启动",
            action: #selector(toggleLoginItem),
            keyEquivalent: ""
        )
        login.target = self
        login.state = isLoginItemEnabled ? .on : .off
        menu.addItem(login)

        let about = NSMenuItem(
            title: "关于 XDR Bright",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        about.target = self
        menu.addItem(about)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        statusItem.button?.image = NSImage(
            systemSymbolName: isOn ? "sun.max.fill" : "sun.max",
            accessibilityDescription: "XDR Bright"
        )
        statusItem.button?.toolTip = isOn ? "HDR 增亮：开（\(level)%）" : "HDR 增亮：关"
    }

    @objc private func toggleBoost() {
        if isOn {
            turnOff()
        } else {
            turnOn()
        }
    }

    @objc private func selectLevel(_ sender: NSMenuItem) {
        level = sender.tag
        UserDefaults.standard.set(level, forKey: Self.levelKey)
        turnOn()
    }

    // MARK: - 登录启动（LaunchAgent，便于未经公证的 App 直接使用）

    private var loginPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(Self.loginLabel).plist")
    }

    private var isLoginItemEnabled: Bool {
        FileManager.default.fileExists(atPath: loginPlistURL.path)
    }

    @objc private func toggleLoginItem() {
        if isLoginItemEnabled {
            disableLoginItem()
        } else {
            enableLoginItem()
        }
        rebuildMenu()
    }

    private func enableLoginItem() {
        let plist: [String: Any] = [
            "Label": Self.loginLabel,
            "ProgramArguments": ["/usr/bin/open", "-a", Bundle.main.bundlePath],
            "RunAtLoad": true,
            "LimitLoadToSessionType": "Aqua",
        ]
        do {
            try FileManager.default.createDirectory(
                at: loginPlistURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try PropertyListSerialization.data(
                fromPropertyList: plist,
                format: .xml,
                options: 0
            )
            try data.write(to: loginPlistURL)
            runLaunchctl(["bootstrap", "gui/\(getuid())", loginPlistURL.path])
        } catch {
            logger.error("enable login item failed: \(error.localizedDescription, privacy: .public)")
            presentError("无法写入登录项：\(error.localizedDescription)")
        }
    }

    private func disableLoginItem() {
        runLaunchctl(["bootout", "gui/\(getuid())", loginPlistURL.path])
        try? FileManager.default.removeItem(at: loginPlistURL)
    }

    private func runLaunchctl(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    // MARK: - 其它

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "XDR Bright"
        alert.informativeText = """
        为内建 XDR 显示器解锁 HDR 亮度。
        点击菜单栏太阳图标开关；亮度键仍可正常调节。

        gamma 表由本 App 持有，退出或崩溃会自动还原。
        """
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    @objc private func quit() {
        if isOn {
            controller.restore()
        }
        NSApp.terminate(nil)
    }

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "XDR Bright"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
