import AppKit
import QuartzCore

/// 1×1 的 EDR 头空间窗口。
///
/// DisplayBuddy 的 UltraBright 并不只是改 gamma：它的二进制里有
/// `setWantsExtendedDynamicRangeContent:` / `setColorspace:` 调用，
/// 并且运行时常驻一个 1×1、layer 1000 的窗口。这个窗口的作用是让
/// WindowServer 把显示器切到 EDR 输出模式（抬高背光、数字衰减 SDR），
/// 之后 gamma 表里大于 1.0 的项才会变成真实光输出，而不是被裁剪成过曝。
///
/// 这里用同尺寸、同层级的最小实现：
/// - 1×1、透明、不接收鼠标、不参与切换
/// - 图层内容是一张 extended linear Display P3 的 1×1 浮点图（值 > 1）
/// - 只负责“解锁头空间”，不改变可见画面
@MainActor
public final class EDRHeadroomWindow {
    private var window: NSWindow?

    public init() {}

    public var isVisible: Bool { window != nil }

    public func show(headroom: CGFloat = 4) {
        guard window == nil else { return }

        let content = Self.makeHeadroomLayer(headroom: headroom)
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        host.wantsLayer = true
        host.layer = content

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = NSWindow.Level(rawValue: 1000)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.contentView = host
        window.orderFrontRegardless()
        self.window = window
    }

    public func hide() {
        window?.orderOut(nil)
        window = nil
    }

    private static func makeHeadroomLayer(headroom: CGFloat) -> CALayer {
        let colorSpace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
            ?? CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        let value = Float(headroom)
        var pixel: [Float] = [value, value, value, 1]
        let data = Data(bytes: &pixel, count: 16)
        let provider = CGDataProvider(data: data as CFData)!
        let info = CGBitmapInfo(
            rawValue: CGBitmapInfo.floatComponents.rawValue
                | CGImageAlphaInfo.premultipliedLast.rawValue
        )
        let image = CGImage(
            width: 1,
            height: 1,
            bitsPerComponent: 32,
            bitsPerPixel: 128,
            bytesPerRow: 16,
            space: colorSpace,
            bitmapInfo: info,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )

        let layer = CALayer()
        layer.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        layer.contentsFormat = .RGBA16Float
        // 实测：macOS 26 上 preferredDynamicRange = .high 不会抬升
        // NSScreen.maximumExtendedDynamicRangeColorComponentValue（仍是 1.2），
        // 而 wantsExtendedDynamicRangeContent = true 会把它抬到 ~2.57。
        // 因此这里保留已废弃但有效的 API，才能真正解锁头空间。
        layer.wantsExtendedDynamicRangeContent = true
        layer.contents = image
        return layer
    }
}
