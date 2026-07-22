import Foundation

enum SummonPanelFocus: Equatable, Sendable {
    case card
    case action(Int)
}

enum SummonPanelCommand: Equatable, Sendable {
    case moveLeft
    case moveRight
    case moveUp
    case moveDown
    case activate
    case activatePlainText
    case openChop
    case digit(Int)        // 数字直贴：粘贴第 N 条（1–9）
    case escape
}

/// 粘贴触发来源。决定读「按下后（数字键）」还是「双击/回车」设置（01 §3.5）。
enum SummonPasteSource: Sendable, Equatable {
    case press    // 数字键直贴
    case `return` // ⏎ / 点击选中卡 / 动作胶囊
}

typealias SummonPasteHandler = @MainActor (_ item: ClipItem, _ plainText: Bool, _ source: SummonPasteSource) -> Void

/// keyCode + 修饰键 → 面板命令的纯映射（便于单测）。数字键语义受「数字快捷键修饰键」设置约束：
/// 暂无 = 面板内裸数字；⌘ / ⌥ = 需对应修饰键 + N（01 §3.3）。
enum SummonKeyMap {
    static func command(keyCode: UInt16, option: Bool, command: Bool,
                        digitModifier: DigitModifier) -> SummonPanelCommand? {
        switch keyCode {
        case 123: return .moveLeft
        case 124: return .moveRight
        case 125: return .moveDown
        case 126: return .moveUp
        case 36, 76: return option ? .activatePlainText : .activate
        case 48: return .openChop
        case 53: return .escape
        default:
            guard let value = digit(forKeyCode: keyCode) else { return nil }
            return digitCommand(digit: value, option: option, command: command, modifier: digitModifier)
        }
    }

    /// ANSI 主键区 1–9 的虚拟键码。
    static func digit(forKeyCode keyCode: UInt16) -> Int? {
        switch keyCode {
        case 18: return 1
        case 19: return 2
        case 20: return 3
        case 21: return 4
        case 23: return 5
        case 22: return 6
        case 26: return 7
        case 28: return 8
        case 25: return 9
        default: return nil
        }
    }

    static func digitCommand(digit: Int, option: Bool, command: Bool,
                             modifier: DigitModifier) -> SummonPanelCommand? {
        switch modifier {
        case .none: return (!option && !command) ? .digit(digit) : nil
        case .cmd: return (command && !option) ? .digit(digit) : nil
        case .opt: return (option && !command) ? .digit(digit) : nil
        }
    }
}
