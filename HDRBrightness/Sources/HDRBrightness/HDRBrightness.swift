import CoreGraphics
import Foundation

/// HDR 增亮核心模块（不依赖 AppKit / SwiftUI）。
///
/// 原理：把显示器的 gamma 传输表整体乘以 `1 + 0.00535 × 档位`，
/// 再用 `CGSetDisplayTransferByTable` 以 **256 采样**写回。
/// 256 是关键：传 1024 时系统会把大于 1.0 的项截断成 1.0，增亮完全失效。
///
/// 该增益只改内容信号、不改系统亮度状态，所以键盘亮度键仍然照常工作：
/// 背光 0–100% × 固定增益，最大亮度就是 HDR 区间。
///
/// gamma 表绑定在设置它的进程连接上，进程退出（包括崩溃）会自动还原。
public enum HDRBrightnessConstants {
    /// 每 1 档对应的 gamma 增益。100 档 = 1.535 倍。
    public static let gainPerPercent: Double = 0.00535
    /// 固定采样数，必须 <= 256，见类型注释。
    public static let sampleCount = 256
    /// 系统 gamma 表容量（macOS 当前实现为 1024）。
    public static let systemTableCapacity = 1024
}

public enum HDRBrightnessError: Error, CustomStringConvertible {
    case noDisplay
    case readTableFailed(CGDirectDisplayID, CGError)
    case writeTableFailed(CGDirectDisplayID, CGError)

    public var description: String {
        switch self {
        case .noDisplay:
            return "没有找到可用的显示器"
        case let .readTableFailed(id, error):
            return "读取显示器 \(id) 的 gamma 表失败（\(error.rawValue)）"
        case let .writeTableFailed(id, error):
            return "写入显示器 \(id) 的 gamma 表失败（\(error.rawValue)）"
        }
    }
}

public final class HDRBrightnessController {
    /// 每个显示器的原始 256 采样表，首次接触时读取，用于无损还原。
    private var originalTables: [CGDirectDisplayID: [CGGammaValue]] = [:]

    public init() {}

    /// 亮度键仍然控制 0–100% 背光；这里只负责叠加 HDR 增益。
    public static func gain(forLevel level: Int) -> CGGammaValue {
        let clamped = min(max(level, 0), 100)
        return CGGammaValue(1) + CGGammaValue(HDRBrightnessConstants.gainPerPercent * Double(clamped))
    }

    /// 需要增亮的目标显示器：优先内置 XDR 屏，无内置屏时退回主屏。
    public static func targetDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else {
            return []
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else {
            return []
        }
        let builtIn = ids.filter { CGDisplayIsBuiltin($0) != 0 }
        return builtIn.isEmpty ? [CGMainDisplayID()] : builtIn
    }

    /// 读取当前实际增亮档位（0–100）。读不到时返回 nil。
    public static func currentLevel() -> Double? {
        guard let id = targetDisplays().first,
              let table = readTable(id, capacity: Int(CGDisplayGammaTableCapacity(id))),
              let top = table.last else {
            return nil
        }
        return (Double(top) - 1) / HDRBrightnessConstants.gainPerPercent
    }

    /// 读取当前 gamma 表末项（即实际生效的增益）。
    public static func currentGain() -> Double? {
        guard let id = targetDisplays().first,
              let table = readTable(id, capacity: Int(CGDisplayGammaTableCapacity(id))),
              let top = table.last else {
            return nil
        }
        return Double(top)
    }

    /// 检查系统 gamma 表是否被外部改掉（显示器重配置、其它 App 覆盖等）。
    /// 借鉴 BrightIntosh 的漂移检测：期望值与实际值差超过 tolerance 即视为漂移。
    public func needsReapply(level: Int, tolerance: Double = 0.01) -> Bool {
        guard level > 0, let current = Self.currentGain() else { return false }
        let expected = Double(Self.gain(forLevel: level))
        return abs(current - expected) > tolerance
    }

    /// 施加增亮。level = 0 等价于还原。
    @discardableResult
    public func apply(level: Int) -> Result<Void, HDRBrightnessError> {
        let clamped = min(max(level, 0), 100)
        let displays = Self.targetDisplays()
        guard !displays.isEmpty else { return .failure(.noDisplay) }

        let gain = Self.gain(forLevel: clamped)
        for id in displays {
            guard let base = baseTable(for: id) else {
                return .failure(.readTableFailed(id, .failure))
            }
            var red = base.map { $0 * gain }
            var green = red
            var blue = red
            let error = CGSetDisplayTransferByTable(
                id,
                UInt32(HDRBrightnessConstants.sampleCount),
                &red,
                &green,
                &blue
            )
            guard error == .success else {
                return .failure(.writeTableFailed(id, error))
            }
        }
        return .success(())
    }

    /// 还原到首次接触时的原始 gamma 表。
    @discardableResult
    public func restore() -> Result<Void, HDRBrightnessError> {
        let displays = Self.targetDisplays()
        guard !displays.isEmpty else { return .failure(.noDisplay) }
        for id in displays {
            guard let base = baseTable(for: id) else {
                return .failure(.readTableFailed(id, .failure))
            }
            var red = base
            var green = red
            var blue = red
            let error = CGSetDisplayTransferByTable(
                id,
                UInt32(HDRBrightnessConstants.sampleCount),
                &red,
                &green,
                &blue
            )
            guard error == .success else {
                return .failure(.writeTableFailed(id, error))
            }
        }
        return .success(())
    }

    // MARK: - 内部

    private func baseTable(for id: CGDirectDisplayID) -> [CGGammaValue]? {
        if let cached = originalTables[id] {
            return cached
        }
        guard let full = Self.readTable(id, capacity: Int(CGDisplayGammaTableCapacity(id))) else {
            return nil
        }
        let resampled = Self.resample(full, to: HDRBrightnessConstants.sampleCount)
        // 归一化：如果首次读到的表已经带着增益（例如上一个实例/别的工具留下的 >1），
        // 先除掉，避免之后再次叠加导致过曝。
        let top = resampled.last ?? 1
        let normalized = top > 1.001 ? resampled.map { $0 / top } : resampled
        originalTables[id] = normalized
        return normalized
    }

    private static func readTable(_ id: CGDirectDisplayID, capacity: Int) -> [CGGammaValue]? {
        guard capacity > 0 else { return nil }
        var red = [CGGammaValue](repeating: 0, count: capacity)
        var green = red
        var blue = red
        var samples: UInt32 = 0
        let error = CGGetDisplayTransferByTable(
            id,
            UInt32(capacity),
            &red,
            &green,
            &blue,
            &samples
        )
        guard error == .success, samples > 0 else { return nil }
        return Array(red.prefix(Int(samples)))
    }

    /// 线性重采样，保证写入的 256 点斜坡与系统原表比例一致。
    static func resample(_ table: [CGGammaValue], to count: Int) -> [CGGammaValue] {
        guard !table.isEmpty, count > 0 else { return [] }
        if table.count == count { return table }
        return (0..<count).map { index in
            let position = Double(index) / Double(max(count - 1, 1))
            let source = position * Double(table.count - 1)
            let lower = min(Int(source), table.count - 1)
            let upper = min(lower + 1, table.count - 1)
            let fraction = CGGammaValue(source - Double(lower))
            return table[lower] * (1 - fraction) + table[upper] * fraction
        }
    }
}
