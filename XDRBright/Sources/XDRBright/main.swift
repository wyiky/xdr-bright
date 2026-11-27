import AppKit
import HDRBrightness

// 自检：真实写入 / 读回 / 还原，用于构建后验证，不进入菜单栏常驻状态。
if CommandLine.arguments.contains("--selftest") {
    let controller = HDRBrightnessController()
    let headroom = EDRHeadroomWindow()
    let level = 70
    headroom.show(headroom: CGFloat(HDRBrightnessController.gain(forLevel: level)))
    let applied = controller.apply(level: level)
    let readBack = HDRBrightnessController.currentLevel()
    let restored = controller.restore()
    let afterRestore = HDRBrightnessController.currentLevel()
    let readBackText = readBack.map { String($0) } ?? "nil"
    let afterRestoreText = afterRestore.map { String($0) } ?? "nil"
    print("[selftest] apply=\(applied) readBack=\(readBackText) " +
          "restore=\(restored) afterRestore=\(afterRestoreText)")
    let ok: Bool
    if case .success = applied,
       case .success = restored,
       let value = readBack,
       abs(value - Double(level)) < 1.0,
       let restoredLevel = afterRestore,
       restoredLevel < 1.0 {
        ok = true
    } else {
        ok = false
    }
    print("[selftest] \(ok ? "OK" : "FAILED")")
    exit(ok ? 0 : 1)
}

// 菜单栏常驻工具：不显示 Dock 图标，不创建主窗口。
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
