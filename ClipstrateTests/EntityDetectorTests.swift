import XCTest
@testable import Clipstrate

final class EntityDetectorTests: XCTestCase {
    private let detector = EntityDetector()

    func testEmailRuleHasThreePositiveAndTwoNegativeCases() {
        assertPositive(
            .email,
            cases: [
                ("联系 alice@example.com", "alice@example.com"),
                ("foo.bar+tag@sub.example.co.uk", "foo.bar+tag@sub.example.co.uk"),
                ("A_1@test-domain.cn", "A_1@test-domain.cn")
            ]
        )
        assertNegative(.email, cases: ["alice@example", "name at example.com"])
    }

    func testChinaMobileRuleHasThreePositiveAndTwoNegativeCases() {
        assertPositive(
            .phone,
            cases: [
                ("电话 13800138000", "13800138000"),
                ("19912345678", "19912345678"),
                ("联系15100001111即可", "15100001111")
            ]
        )
        assertNegative(.phone, cases: ["12800138000", "138001380000"])
    }

    func testURLRuleHasThreePositiveAndTwoNegativeCases() {
        assertPositive(
            .url,
            cases: [
                ("访问 https://example.com/path?q=1", "https://example.com/path?q=1"),
                ("http://localhost:8080/test", "http://localhost:8080/test"),
                ("网站 www.apple.com", "www.apple.com")
            ]
        )
        assertNegative(.url, cases: ["not a url", "https://"])
    }

    func testTaobaoRulesHaveThreePositiveAndTwoNegativeCases() {
        assertPositive(
            .taobaoCode,
            cases: [
                ("复制 ￥AbCdEf1234￥ 打开", "￥AbCdEf1234￥"),
                ("$ 12345678 $", "$ 12345678 $"),
                ("口令 ((AbCdEf 1234// 快来", "((AbCdEf 1234//")
            ]
        )
        assertNegative(.taobaoCode, cases: ["￥ABC123￥", "￥AbCdEf1234$"])
    }

    func testVerificationRulesHaveThreePositiveAndTwoNegativeCases() {
        assertPositive(
            .verificationCode,
            cases: [
                ("验证码：1234", "1234"),
                ("Your code is 98765432", "98765432"),
                ("请填写 654321", "654321")
            ]
        )
        assertNegative(.verificationCode, cases: ["验证码：123", "动态码 123456789"])
    }

    func testTrackingRuleHasThreePositiveAndTwoNegativeCases() {
        assertPositive(
            .trackingNumber,
            cases: [
                ("顺丰 SF1234567890123", "SF1234567890123"),
                ("京东 JD12345678901", "JD12345678901"),
                ("EMS E123456789CN", "E123456789CN")
            ]
        )
        assertNegative(.trackingNumber, cases: ["SF123456789012", "JD123"])
    }

    func testContextVerificationWinsOverStandaloneDuplicate() throws {
        let entity = try XCTUnwrap(detector.entities(in: "验证码 123456").first)
        XCTAssertEqual(entity.kind, .verificationCode)
        XCTAssertEqual(entity.value, "123456")
        XCTAssertEqual(entity.priority, 500)
    }

    func testLongerOverlappingMatchWinsBeforePriority() {
        let entities = detector.entities(in: "￥ABC12345￥")

        XCTAssertEqual(entities.map(\.kind), [.taobaoCode])
        XCTAssertEqual(entities.map(\.value), ["￥ABC12345￥"])
    }

    func testResultsArePrioritySortedAndLimitedToNine() {
        let emails = (0..<10).map { "user\($0)@example.com" }.joined(separator: " ")
        let entities = detector.entities(in: emails)

        XCTAssertEqual(entities.count, 9)
        XCTAssertEqual(entities.map(\.value), (0..<9).map { "user\($0)@example.com" })
        XCTAssertTrue(zip(entities, entities.dropFirst()).allSatisfy { $0.priority >= $1.priority })
    }

    func testSourceRangeRecoversEntityValue() throws {
        let source = "前缀 ￥AbCdEf1234￥ 后缀"
        let entity = try XCTUnwrap(detector.entities(in: source).first)
        let range = try XCTUnwrap(Range(entity.sourceRange, in: source))
        XCTAssertEqual(String(source[range]), entity.value)
    }

    func testAllCustomRulesAreP0AndDataDriven() {
        XCTAssertFalse(EntityRule.p0Rules.isEmpty)
        XCTAssertTrue(EntityRule.p0Rules.allSatisfy(\.isP0))
        XCTAssertTrue(EntityRule.p0Rules.allSatisfy { !$0.id.isEmpty && !$0.pattern.isEmpty })
        XCTAssertEqual(Set(EntityRule.p0Rules.map(\.kind)), Set(EntityKind.allCases).subtracting([.url]))
    }

    func testEveryCustomRuleHasThreePositiveAndTwoNegativeCases() throws {
        let fixtures: [String: RuleFixture] = [
            "email": RuleFixture(
                positives: [
                    ("alice@example.com", "alice@example.com"),
                    ("foo.bar+tag@sub.example.co.uk", "foo.bar+tag@sub.example.co.uk"),
                    ("A_1@test-domain.cn", "A_1@test-domain.cn")
                ],
                negatives: ["alice@example", "name at example.com"]
            ),
            "china-mobile": RuleFixture(
                positives: [
                    ("13800138000", "13800138000"),
                    ("19912345678", "19912345678"),
                    ("15100001111", "15100001111")
                ],
                negatives: ["12800138000", "138001380000"]
            ),
            "taobao-currency": RuleFixture(
                positives: [
                    ("￥AbCdEf12￥", "￥AbCdEf12￥"),
                    ("€123456789€", "€123456789€"),
                    ("$ ABCDEF12345678 $", "$ ABCDEF12345678 $")
                ],
                negatives: ["￥ABC123￥", "￥AbCdEf1234$"]
            ),
            "taobao-parentheses": RuleFixture(
                positives: [
                    ("((AbCdEf12//", "((AbCdEf12//"),
                    ("((1234 ABCD//", "((1234 ABCD//"),
                    ("((ABCDEFGHIJ1234567890//", "((ABCDEFGHIJ1234567890//")
                ],
                negatives: ["((ABC1234//", "((ABCDEFGHIJ12345678901//"]
            ),
            "verification-context": RuleFixture(
                positives: [
                    ("验证码：1234", "1234"),
                    ("校验码为 876543", "876543"),
                    ("Your CODE is 98765432", "98765432")
                ],
                negatives: ["验证码 123", "动态码 123456789"]
            ),
            "verification-standalone": RuleFixture(
                positives: [
                    ("取件码 1234", "1234"),
                    ("订单 56789", "56789"),
                    ("请填写 654321", "654321")
                ],
                negatives: ["123", "1234567"]
            ),
            "tracking-number": RuleFixture(
                positives: [
                    ("SF1234567890123", "SF1234567890123"),
                    ("JD12345678901", "JD12345678901"),
                    ("E123456789CN", "E123456789CN")
                ],
                negatives: ["SF123456789012", "JD123"]
            )
        ]

        XCTAssertEqual(Set(fixtures.keys), Set(EntityRule.p0Rules.map(\.id)))

        for rule in EntityRule.p0Rules {
            let fixture = try XCTUnwrap(fixtures[rule.id])
            let isolatedDetector = EntityDetector(rules: [rule])
            XCTAssertGreaterThanOrEqual(fixture.positives.count, 3, rule.id)
            XCTAssertGreaterThanOrEqual(fixture.negatives.count, 2, rule.id)

            for positive in fixture.positives {
                XCTAssertTrue(
                    isolatedDetector.entities(in: positive.source).contains {
                        $0.kind == rule.kind && $0.value == positive.value
                    },
                    "\(rule.id) missed \(positive.value)"
                )
            }
            for negative in fixture.negatives {
                XCTAssertFalse(
                    isolatedDetector.entities(in: negative).contains { $0.kind == rule.kind },
                    "\(rule.id) false positive in \(negative)"
                )
            }
        }
    }

    func testDetectorIsSendableAcrossDetachedTask() async {
        let detector = EntityDetector()
        let entities = await Task.detached {
            detector.entities(in: "验证码 123456，联系 13800138000")
        }.value

        XCTAssertEqual(Set(entities.map(\.kind)), [.verificationCode, .phone])
    }

    private func assertPositive(
        _ kind: EntityKind,
        cases: [(source: String, value: String)],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertGreaterThanOrEqual(cases.count, 3, file: file, line: line)
        for testCase in cases {
            let values = detector.entities(in: testCase.source)
                .filter { $0.kind == kind }
                .map(\.value)
            XCTAssertTrue(
                values.contains(testCase.value),
                "\(kind.rawValue) did not detect \(testCase.value) in \(testCase.source); got \(values)",
                file: file,
                line: line
            )
        }
    }

    private func assertNegative(
        _ kind: EntityKind,
        cases: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertGreaterThanOrEqual(cases.count, 2, file: file, line: line)
        for source in cases {
            XCTAssertFalse(
                detector.entities(in: source).contains { $0.kind == kind },
                "\(kind.rawValue) false positive in \(source)",
                file: file,
                line: line
            )
        }
    }
}

private struct RuleFixture {
    let positives: [(source: String, value: String)]
    let negatives: [String]
}
