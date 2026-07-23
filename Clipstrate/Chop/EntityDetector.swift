import Foundation

/// Two-level offline entity detector: system data detection plus custom rules.
struct EntityDetector: Sendable {
    private let rules: [EntityRule]

    init(rules: [EntityRule] = EntityRule.p0Rules) {
        self.rules = rules
    }

    func entities(in text: String) -> [DetectedEntity] {
        guard !text.isEmpty else { return [] }

        var candidates = dataDetectorEntities(in: text)
        candidates.append(contentsOf: ruleEntities(in: text))

        let unique = deduplicated(candidates)
        let nonOverlapping = resolveOverlaps(unique)

        return Array(
            nonOverlapping
                .sorted(by: finalOrdering)
                .prefix(9)
        )
    }

    private func dataDetectorEntities(in text: String) -> [DetectedEntity] {
        let checkingTypes = NSTextCheckingResult.CheckingType.link.rawValue
            | NSTextCheckingResult.CheckingType.phoneNumber.rawValue
        guard let detector = try? NSDataDetector(types: checkingTypes) else { return [] }

        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let source = text as NSString

        return detector.matches(in: text, options: [], range: fullRange).compactMap { match in
            switch match.resultType {
            case .link:
                guard match.url?.scheme?.lowercased() != "mailto" else { return nil }
                return entity(
                    kind: .url,
                    value: source.substring(with: match.range),
                    range: match.range,
                    priority: 300
                )

            case .phoneNumber:
                let value = source.substring(with: match.range)
                guard isChinaMobile(value) else { return nil }
                return entity(kind: .phone, value: value, range: match.range, priority: 350)

            default:
                return nil
            }
        }
    }

    private func ruleEntities(in text: String) -> [DetectedEntity] {
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let source = text as NSString

        return rules.flatMap { rule -> [DetectedEntity] in
            let options: NSRegularExpression.Options = rule.caseInsensitive ? [.caseInsensitive] : []
            guard let expression = try? NSRegularExpression(pattern: rule.pattern, options: options) else {
                assertionFailure("Invalid entity rule: \(rule.id)")
                return []
            }

            return expression.matches(in: text, options: [], range: fullRange).compactMap { match in
                let captures = (0..<match.numberOfRanges).map { index -> String in
                    let range = match.range(at: index)
                    return range.location == NSNotFound ? "" : source.substring(with: range)
                }
                guard rule.validator(captures), rule.valueCaptureGroup < match.numberOfRanges else {
                    return nil
                }

                let valueRange = match.range(at: rule.valueCaptureGroup)
                guard valueRange.location != NSNotFound else { return nil }
                return entity(
                    kind: rule.kind,
                    value: source.substring(with: valueRange),
                    range: valueRange,
                    icon: rule.icon,
                    priority: rule.priority
                )
            }
        }
    }

    private func deduplicated(_ candidates: [DetectedEntity]) -> [DetectedEntity] {
        var byIdentity: [String: DetectedEntity] = [:]
        for candidate in candidates {
            let key = "\(candidate.kind.rawValue):\(candidate.sourceRange.location):\(candidate.sourceRange.length)"
            if let current = byIdentity[key], current.priority >= candidate.priority {
                continue
            }
            byIdentity[key] = candidate
        }
        return Array(byIdentity.values)
    }

    /// Overlap resolution is intentionally independent of display priority:
    /// the longest source match wins first, as required by 01 §4.4.
    private func resolveOverlaps(_ candidates: [DetectedEntity]) -> [DetectedEntity] {
        let longestFirst = candidates.sorted { lhs, rhs in
            if lhs.sourceRange.length != rhs.sourceRange.length {
                return lhs.sourceRange.length > rhs.sourceRange.length
            }
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            if lhs.sourceRange.location != rhs.sourceRange.location {
                return lhs.sourceRange.location < rhs.sourceRange.location
            }
            return lhs.kind.rawValue < rhs.kind.rawValue
        }

        var accepted: [DetectedEntity] = []
        for candidate in longestFirst {
            let overlaps = accepted.contains {
                NSIntersectionRange($0.sourceRange, candidate.sourceRange).length > 0
            }
            if !overlaps { accepted.append(candidate) }
        }
        return accepted
    }

    private func finalOrdering(_ lhs: DetectedEntity, _ rhs: DetectedEntity) -> Bool {
        if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
        if lhs.sourceRange.location != rhs.sourceRange.location {
            return lhs.sourceRange.location < rhs.sourceRange.location
        }
        if lhs.sourceRange.length != rhs.sourceRange.length {
            return lhs.sourceRange.length > rhs.sourceRange.length
        }
        return lhs.kind.rawValue < rhs.kind.rawValue
    }

    private func entity(
        kind: EntityKind,
        value: String,
        range: NSRange,
        icon: String? = nil,
        priority: Int
    ) -> DetectedEntity {
        DetectedEntity(
            kind: kind,
            value: value,
            sourceRange: range,
            icon: icon ?? kind.icon,
            priority: priority
        )
    }

    private func isChinaMobile(_ value: String) -> Bool {
        let digits = value.unicodeScalars.filter(CharacterSet.decimalDigits.contains)
        guard digits.count == 11, digits.first == "1" else { return false }
        return "3456789".unicodeScalars.contains(digits[digits.index(after: digits.startIndex)])
    }
}
