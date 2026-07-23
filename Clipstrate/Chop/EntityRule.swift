import Foundation

enum EntityKind: String, CaseIterable, Sendable {
    case email
    case phone
    case url
    case taobaoCode
    case verificationCode
    case trackingNumber

    var label: String {
        switch self {
        case .email: "邮箱"
        case .phone: "手机号"
        case .url: "链接"
        case .taobaoCode: "淘口令"
        case .verificationCode: "验证码"
        case .trackingNumber: "快递单号"
        }
    }

    var icon: String {
        switch self {
        case .email: "envelope.fill"
        case .phone: "phone.fill"
        case .url: "link"
        case .taobaoCode: "cart.fill"
        case .verificationCode: "key.fill"
        case .trackingNumber: "shippingbox.fill"
        }
    }
}

struct DetectedEntity: Identifiable, Sendable, Hashable {
    let kind: EntityKind
    let value: String
    let sourceRange: NSRange
    let icon: String
    let priority: Int

    var id: String {
        "\(kind.rawValue):\(sourceRange.location):\(sourceRange.length)"
    }

    var typeLabel: String { kind.label }
}

/// Data-driven custom entity rule (01 §4.4).
struct EntityRule: Sendable {
    let id: String
    let kind: EntityKind
    let pattern: String
    let valueCaptureGroup: Int
    let icon: String
    let priority: Int
    let isP0: Bool
    let caseInsensitive: Bool
    let validator: @Sendable ([String]) -> Bool
}

extension EntityRule {
    static let p0Rules: [EntityRule] = [
        EntityRule(
            id: "email",
            kind: .email,
            pattern: #"(?<![A-Za-z0-9._%+\-])([A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,})(?![A-Za-z0-9._%+\-])"#,
            valueCaptureGroup: 1,
            icon: EntityKind.email.icon,
            priority: 400,
            isP0: true,
            caseInsensitive: false,
            validator: { _ in true }
        ),
        EntityRule(
            id: "china-mobile",
            kind: .phone,
            pattern: #"(?<!\d)(1[3-9]\d{9})(?!\d)"#,
            valueCaptureGroup: 1,
            icon: EntityKind.phone.icon,
            priority: 350,
            isP0: true,
            caseInsensitive: false,
            validator: { captures in
                captures.count > 1 && captures[1].count == 11
            }
        ),
        EntityRule(
            id: "taobao-currency",
            kind: .taobaoCode,
            pattern: #"([￥$€£¢₳¤])\s*([0-9A-Za-z]{8,14})\s*\1"#,
            valueCaptureGroup: 0,
            icon: EntityKind.taobaoCode.icon,
            priority: 600,
            isP0: true,
            caseInsensitive: false,
            validator: { captures in
                captures.count > 2 && (8...14).contains(captures[2].count)
            }
        ),
        EntityRule(
            id: "taobao-parentheses",
            kind: .taobaoCode,
            pattern: #"(\(\([0-9A-Za-z ]{8,20}//)"#,
            valueCaptureGroup: 1,
            icon: EntityKind.taobaoCode.icon,
            priority: 600,
            isP0: true,
            caseInsensitive: false,
            validator: { captures in
                captures.count > 1 && (12...24).contains(captures[1].count)
            }
        ),
        EntityRule(
            id: "verification-context",
            kind: .verificationCode,
            pattern: #"(?:验证码|校验码|动态码|code)\D{0,6}(\d{4,8})(?!\d)"#,
            valueCaptureGroup: 1,
            icon: EntityKind.verificationCode.icon,
            priority: 500,
            isP0: true,
            caseInsensitive: true,
            validator: { _ in true }
        ),
        EntityRule(
            id: "verification-standalone",
            kind: .verificationCode,
            pattern: #"(?<!\d)(\d{4,6})(?!\d)"#,
            valueCaptureGroup: 1,
            icon: EntityKind.verificationCode.icon,
            priority: 100,
            isP0: true,
            caseInsensitive: false,
            validator: { _ in true }
        ),
        EntityRule(
            id: "tracking-number",
            kind: .trackingNumber,
            pattern: #"(?<![0-9A-Za-z])((?:SF\d{13}|JD[0-9A-Z]{11,15}|YT\d{15}|7\d{13}|E\w{9}CN))(?![0-9A-Za-z])"#,
            valueCaptureGroup: 1,
            icon: EntityKind.trackingNumber.icon,
            priority: 450,
            isP0: true,
            caseInsensitive: false,
            validator: { _ in true }
        )
    ]
}
