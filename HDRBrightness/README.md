# HDRBrightness

macOS 内建 XDR 屏的 HDR 增亮核心模块。纯 `CoreGraphics`，不依赖 AppKit / SwiftUI，
可以被任何 macOS App、CLI 或 SwiftPM 工程直接引用。

## 原理

把显示器 gamma 传输表整体乘以 `1 + 0.00535 × 档位`（档位 0–100，100 档 = 1.535×），
再用 `CGSetDisplayTransferByTable` 以 **256 采样**写回。

> 256 是关键：采样数传 1024 时，系统会把大于 1.0 的项截断成 1.0，增亮完全失效。

增益只叠加在内容信号上，不改系统亮度状态，因此键盘亮度键照常控制 0–100% 背光，
最大亮度即 HDR 区间。gamma 表绑定在设置它的进程连接上，进程退出（含崩溃）会自动还原。

## 使用

把本目录作为本地 Swift Package 加入你的工程：

```swift
dependencies: [
    .package(path: "/Users/wyiky/Documents/coding/dgx-spark-cluster-dashboard/macos/HDRBrightness")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [.product(name: "HDRBrightness", package: "HDRBrightness")]
    )
]
```

```swift
import HDRBrightness

// 调用方必须是常驻进程：gamma 表只在设置它的进程存活期间有效。
let controller = HDRBrightnessController()

controller.apply(level: 80)          // 增亮到 80 档，返回 Result<Void, HDRBrightnessError>
controller.restore()                 // 还原

HDRBrightnessController.currentLevel()   // 读当前实际档位（Double?）
HDRBrightnessController.gain(forLevel: 80)  // 1.428
HDRBrightnessController.targetDisplays()    // 目标显示器 ID
```

## 注意

- 调用方进程必须常驻；一次性 CLI 设完退出，增亮会立即消失。
- 只对支持 EDR 的内建 XDR 屏有明显效果；外接非 HDR 屏只会裁剪高光。
- 需要 macOS 14+。
