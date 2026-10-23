import Foundation

/// `Blinko --selftest` runs the pure-logic checks (calculator, fuzzy matcher, parsers,
/// speech meter) and exits with status 1 on any failure. No services, no UI.
@MainActor
enum SelfTest {
    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.contains("--selftest") else { return false }
        let failures = run()
        print(failures == 0 ? "selftest: all checks passed (\(checks))" : "selftest: \(failures) of \(checks) checks FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    private static var checks = 0
    private static var failed = 0

    private static func expect(_ ok: Bool, _ what: @autoclosure () -> String) {
        checks += 1
        if !ok { failed += 1; print("FAIL: \(what())") }
    }

    private static func calc(_ input: String, _ expected: Double, accuracy: Double = 1e-9) {
        do {
            let v = try Calculator.evaluate(input)
            expect(Swift.abs(v - expected) <= accuracy * max(1, Swift.abs(expected)), "\(input) = \(v), expected \(expected)")
        } catch {
            expect(false, "\(input) threw \(error), expected \(expected)")
        }
    }

    private static func calcFails(_ input: String, _ failure: Calculator.Failure) {
        do {
            let v = try Calculator.evaluate(input)
            expect(false, "\(input) = \(v), expected \(failure)")
        } catch let error as Calculator.Failure {
            expect(error == failure, "\(input) threw \(error), expected \(failure)")
        } catch {
            expect(false, "\(input) threw \(error)")
        }
    }

    static func run() -> Int {
        // Calculator: precedence, associativity, unary, functions, constants
        calc("1+2*3", 7)
        calc("(1+2)*3", 9)
        calc("2^3^2", 512)          // right-associative
        calc("-2^2", -4)
        calc("(-2)^2", 4)
        calc("2*-3", -6)
        calc("--3", 3)
        calc("10/4", 2.5)
        calc("10 % 3", 1)            // modulo between operands
        calc("50%", 0.5)             // percent
        calc("200 * 15%", 30)
        calc("sqrt(16) + sqrt 9", 7)
        calc("sin(pi/2)", 1)
        calc("cos(0)", 1)
        calc("ln(e)", 1)
        calc("log(1000)", 3)
        calc("2pi", 2 * .pi)
        calc("3(4+1)", 15)
        calc("5!", 120)
        calc("1,000,000 / 4", 250_000)
        calc("1.5e3 + 1", 1501)
        calc("2 × 3 ÷ 4", 1.5)
        calc("abs(-7.5)", 7.5)
        calc("1e308 * 1", 1e308)
        calc("0.1 + 0.2", 0.3, accuracy: 1e-12)
        // Failures: never crash, always a typed error
        calcFails("1/0", .divisionByZero)
        calcFails("5 % 0", .divisionByZero)
        calcFails("1e308 * 10", .overflow)
        calcFails("10^400", .overflow)
        calcFails("171!", .overflow)
        calcFails("sqrt(-1)", .notANumber)
        calcFails("(-1)^0.5", .notANumber)
        calcFails("2.5!", .notANumber)
        calcFails("1 +", .syntax)
        calcFails("(1 + 2", .syntax)
        calcFails("1 + 2)", .syntax)
        calcFails("", .syntax)
        calcFails("*3", .syntax)
        calcFails("1..2", .syntax)
        calcFails("foo(3)", .syntax)
        calcFails("%%%", .syntax)
        calcFails("1 2", .syntax) // two numbers side by side are a typo, not a product
        calcFails(String(repeating: "(", count: 100) + "1" + String(repeating: ")", count: 100), .tooComplex)
        calcFails(String(repeating: "-", count: 200) + "1", .tooComplex)
        calcFails(String(repeating: "1+", count: 200) + "1", .tooComplex) // > 256 chars
        expect(Calculator.looksLikeExpression("2+2"), "2+2 looks like an expression")
        expect(!Calculator.looksLikeExpression("42"), "42 alone is not an expression")
        expect(!Calculator.looksLikeExpression("e"), "e alone is not an expression")
        expect(!Calculator.looksLikeExpression("safari"), "words are not expressions")
        expect(Calculator.format(1234.5) == "1,234.5", "format 1234.5 → \(Calculator.format(1234.5))")
        expect(Calculator.format(1e21) == "1e+21", "format 1e21 → \(Calculator.format(1e21))")
        expect(Calculator.format(1.0 / 3) == "0.333333333333", "format 1/3 → \(Calculator.format(1.0 / 3))")
        expect(Calculator.format(-0.5) == "-0.5", "format -0.5")

        // Fuzzy matcher
        let s = { (q: String, c: String) in FuzzyMatcher.score(q, in: c) }
        expect(s("safari", "Safari") == 1000, "exact match scores highest")
        expect((s("saf", "Safari") ?? 0) > (s("sfr", "Safari") ?? 0), "prefix beats subsequence")
        expect((s("code", "Visual Studio Code") ?? 0) > 700, "word prefix")
        expect((s("vsc", "Visual Studio Code") ?? 0) >= 690, "acronym")
        expect(s("xyz", "Safari") == nil, "non-subsequence is rejected")
        expect(s("safarii", "Safari") == nil, "longer query is rejected")
        expect(s("cafe", "Café") == 1000, "diacritics ignored")
        expect((s("term", "Terminal") ?? 0) > (s("term", "Activity Monitor Terminal Helper") ?? 0), "shorter candidate wins")
        expect((s("mail", "Mail") ?? 0) > (s("mail", "Mailspring") ?? 0), "exact beats prefix")
        expect(s("", "Anything") == 0, "empty query matches everything neutrally")

        // Durations
        expect(DurationParser.parse("5m") == 300, "5m")
        expect(DurationParser.parse("1h30m") == 5400, "1h30m")
        expect(DurationParser.parse("90s") == 90, "90s")
        expect(DurationParser.parse("25") == 1500, "bare number = minutes")
        expect(DurationParser.parse("1:30") == 90, "m:ss")
        expect(DurationParser.parse("2 hours") == 7200, "2 hours")
        expect(DurationParser.parse("abc") == nil, "garbage")
        expect(DurationParser.parse("0m") == nil, "zero")
        expect(DurationParser.parse("9999h") == nil, "too long")

        // Units
        if let (r, _) = UnitConversion.convert("10 km to mi") {
            expect(Swift.abs(r.value - 6.21371) < 0.001, "10 km → \(r.value) mi")
        } else { expect(false, "10 km to mi parses") }
        if let (r, _) = UnitConversion.convert("212f in c") {
            expect(Swift.abs(r.value - 100) < 0.001, "212 F → \(r.value) C")
        } else { expect(false, "212f in c parses") }
        if let (r, _) = UnitConversion.convert("5 lbs to kg") {
            expect(Swift.abs(r.value - 2.26796) < 0.001, "5 lb → \(r.value) kg")
        } else { expect(false, "5 lbs to kg parses") }
        expect(UnitConversion.convert("10 km to kg") == nil, "incompatible units rejected")
        expect(UnitConversion.convert("km to mi") == nil, "missing number rejected")

        // Currency parsing
        let known: Set<String> = ["USD", "EUR", "GBP", "JPY"]
        expect(CurrencyQuery.parse("100 usd to eur", known: known) == .init(amount: 100, from: "USD", to: "EUR"), "100 usd to eur")
        expect(CurrencyQuery.parse("€50 in $", known: known) == .init(amount: 50, from: "EUR", to: "USD"), "€50 in $")
        expect(CurrencyQuery.parse("50 gbp", known: known) == .init(amount: 50, from: "GBP", to: nil), "50 gbp")
        expect(CurrencyQuery.parse("1,000 dollars in euros", known: known) == .init(amount: 1000, from: "USD", to: "EUR"), "names")
        expect(CurrencyQuery.parse("50 xyz", known: known) == nil, "unknown code")
        expect(CurrencyQuery.parse("5m", known: known) == nil, "5m is not money")
        expect(CurrencyQuery.parse("t 5m", known: known) == nil, "timer is not money")

        // URLs
        expect(CommandBarModel.urlLike("github.com")?.host == "github.com", "bare domain")
        expect(CommandBarModel.urlLike("1.5") == nil, "number is not a URL")
        expect(CommandBarModel.urlLike("hello world") == nil, "words are not a URL")

        // Speech meter: 0.6 s of voice fires once; gaps reset; quiet room never fires.
        let meter = SpeechMeter()
        meter.reset(levelDetection: true)
        var fired = 0
        for _ in 0..<40 { if meter.feed(db: -58, duration: 0.085) { fired += 1 } }
        expect(fired == 0, "silence never fires")
        for _ in 0..<6 { if meter.feed(db: -25, duration: 0.085) { fired += 1 } }
        expect(fired == 0, "0.5 s of voice is not enough")
        for _ in 0..<4 { if meter.feed(db: -25, duration: 0.085) { fired += 1 } }
        expect(fired == 1, "0.6 s of voice fires")
        for _ in 0..<10 { if meter.feed(db: -25, duration: 0.085) { fired += 1 } }
        expect(fired == 1, "fires once per utterance")
        for _ in 0..<4 { _ = meter.feed(db: -60, duration: 0.085) }
        for _ in 0..<8 { if meter.feed(db: -25, duration: 0.085) { fired += 1 } }
        expect(fired == 2, "a new utterance after a pause fires again")

        // Settings search: everyday words find the right control.
        let top = { (q: String) in SettingsSearch.search(q).first?.title ?? "" }
        expect(top("weather") == "Show weather", "search weather → \(top("weather"))")
        expect(SettingsSearch.search("volume").contains { $0.title.contains("volume & brightness HUD") }, "search volume")
        expect(SettingsSearch.search("startup").contains { $0.title == "Launch at login" }, "search startup")
        expect(SettingsSearch.search("airpods").contains { $0.pane == .activities }, "search airpods")
        expect(SettingsSearch.search("zzzz nothing").isEmpty, "search no match")
        expect(SettingsSearch.entries.count > 60, "settings index populated (\(SettingsSearch.entries.count))")

        return failed
    }
}
