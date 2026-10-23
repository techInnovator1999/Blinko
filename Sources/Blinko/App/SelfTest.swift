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

        spectrumChecks()
        return failed
    }

    /// Real visualizer DSP: band mapping, FFT levels, gate, normalisation, smoothing, ring.
    private static func spectrumChecks() {
        let rate = 48_000.0
        let analyzer = SpectrumAnalyzer(size: 2048)
        let bins = analyzer.size / 2
        for count in [4, 24, 32] {
            let r = SpectrumBands.bandRanges(count: count, bins: bins, sampleRate: rate)
            expect(r.count == count, "\(count) bands")
            expect(r.first!.lowerBound >= 1 && r.last!.upperBound < bins, "\(count) bands inside the spectrum")
            expect(zip(r, r.dropFirst()).allSatisfy { $0.upperBound < $1.lowerBound }, "\(count) bands ascend without overlap")
            let hz = { (bin: Int) in Double(bin) * rate / Double(analyzer.size) }
            expect(hz(r.first!.lowerBound) < 70 && hz(r.last!.upperBound) > 12_000, "\(count) bands span bass to treble")
        }
        // Low bands are narrower than high bands (log spacing).
        let r24 = SpectrumBands.bandRanges(count: 24, bins: bins, sampleRate: rate)
        expect(r24[20].count > r24[4].count * 4, "log spacing: treble bands are wider")

        func sine(_ freq: Double, amplitude: Float) -> [Float] {
            (0..<analyzer.size).map { amplitude * Float(sin(2 * .pi * freq * Double($0) / rate)) }
        }
        func feed(_ samples: [Float], into bands: inout SpectrumBands, frames: Int = 1) {
            samples.withUnsafeBufferPointer { analyzer.analyze($0.baseAddress!) }
            for _ in 0..<frames {
                analyzer.power.withUnsafeBufferPointer {
                    bands.ingest(power: $0, peak: analyzer.peak, sampleRate: rate, dt: 1.0 / 30)
                }
                bands.smooth(dt: 1.0 / 30)
            }
        }
        // FFT scaling: a sine of amplitude A reads ≈ A² (−6 dB for A = 0.5) summed around its bin.
        _ = sine(1_000, amplitude: 0.5).withUnsafeBufferPointer { analyzer.analyze($0.baseAddress!) }
        let k = Int((1_000 / rate * Double(analyzer.size)).rounded())
        let local = analyzer.power[(k - 3)...(k + 3)].reduce(0, +)
        let db = 10 * log10(local)
        expect(Swift.abs(db - (-6.02)) < 1.0, "1 kHz sine at 0.5 reads \(db) dB, expected ≈ −6")

        // The band holding a tone is the loudest; a lower tone lands in a lower band.
        var bands = SpectrumBands(count: 24)
        feed(sine(1_000, amplitude: 0.3), into: &bands, frames: 12)
        let kHzBand = bands.levels.indices.max { bands.levels[$0] < bands.levels[$1] }!
        expect(bands.ranges[kHzBand].contains(k), "1 kHz drives band \(kHzBand) \(bands.ranges[kHzBand])")
        expect(bands.levels[kHzBand] > 0.8, "a steady tone fills its bar (\(bands.levels[kHzBand]))")
        expect(bands.levels.enumerated().filter { abs($0.offset - kHzBand) > 2 }.allSatisfy { $0.element < 0.35 },
               "distant bands stay low around a pure tone")
        var low = SpectrumBands(count: 24)
        feed(sine(110, amplitude: 0.3), into: &low, frames: 12)
        let lowBand = low.levels.indices.max { low.levels[$0] < low.levels[$1] }!
        expect(lowBand < kHzBand - 4, "110 Hz band \(lowBand) is well below 1 kHz band \(kHzBand)")

        // Normalisation: a quiet track fills the bars like a loud one once the ceiling adapts.
        var quiet = SpectrumBands(count: 4)
        var loud = SpectrumBands(count: 4)
        feed(sine(440, amplitude: 0.03), into: &quiet, frames: 120)
        feed(sine(440, amplitude: 0.6), into: &loud, frames: 120)
        expect(Swift.abs((quiet.levels.max() ?? 0) - (loud.levels.max() ?? 0)) < 0.15,
               "−26 dB and full-scale tracks normalise alike (\(quiet.levels.max() ?? 0) vs \(loud.levels.max() ?? 0))")

        // Noise gate: digital silence and hiss below −66 dBFS draw nothing.
        var gated = SpectrumBands(count: 4)
        feed([Float](repeating: 0, count: analyzer.size), into: &gated, frames: 5)
        expect(gated.levels.allSatisfy { $0 == 0 }, "silence draws nothing")
        feed((0..<analyzer.size).map { _ in Float.random(in: -0.0003...0.0003) }, into: &gated, frames: 5)
        expect(gated.levels.allSatisfy { $0 == 0 }, "hiss under the gate draws nothing")

        // Smoothing: fast attack, slower decay, frame-rate independent.
        var s = SpectrumBands(count: 4)
        feed(sine(440, amplitude: 0.5), into: &s, frames: 1)
        let rise = s.levels.max() ?? 0
        feed(sine(440, amplitude: 0.5), into: &s, frames: 30)
        let top = s.levels.max() ?? 0
        feed([Float](repeating: 0, count: analyzer.size), into: &s, frames: 1)
        let fall = s.levels.max() ?? 0
        expect(rise > 0.5 * top, "attack reaches \(rise / top) of the peak in one frame")
        expect(fall > 0.7 * top, "decay keeps \(fall / top) after one frame")
        feed([Float](repeating: 0, count: analyzer.size), into: &s, frames: 45)
        expect(s.isSettled, "bars settle within 1.5 s of silence")
        var a = SpectrumBands(count: 1), b = SpectrumBands(count: 1)
        let tone = sine(440, amplitude: 0.5)
        tone.withUnsafeBufferPointer { analyzer.analyze($0.baseAddress!) }
        analyzer.power.withUnsafeBufferPointer {
            a.ingest(power: $0, peak: analyzer.peak, sampleRate: rate, dt: 0.1)
            b.ingest(power: $0, peak: analyzer.peak, sampleRate: rate, dt: 0.1)
        }
        a.smooth(dt: 0.1)
        b.smooth(dt: 0.05); b.smooth(dt: 0.05)
        expect(Swift.abs(a.levels[0] - b.levels[0]) < 0.001, "smoothing is frame-rate independent")

        // Ring: interleaved stereo → mono, newest window, across the wrap point.
        let ring = AudioSampleRing(capacity: 1024)
        let stereo = (0..<1500).flatMap { [Float($0), Float($0) + 2] }
        stereo.withUnsafeBufferPointer { ring.write($0.baseAddress!, frames: 1500, channels: 2, stride: 2) }
        var out = [Float](repeating: 0, count: 8)
        out.withUnsafeMutableBufferPointer { ring.copyLatest(8, into: $0.baseAddress!) }
        expect(out == (1492..<1500).map { Float($0) + 1 }, "ring returns the newest mono samples in order: \(out)")
    }
}
