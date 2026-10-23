import Foundation

// MARK: - Calculator

/// A small, safe arithmetic parser (recursive descent). Never touches NSExpression, which
/// raises Objective-C exceptions (= crashes) on malformed format strings.
///
/// Grammar:
///   expr    := term (('+' | '-') term)*
///   term    := unary (('*' | '/' | '%' | implicit) unary)*     -- '%' between operands = modulo
///   unary   := ('-' | '+') unary | power
///   power   := postfix ('^' unary)?                             -- right-associative, -2^2 = -4
///   postfix := primary ('%' | '!')*                             -- '%' after an operand = percent
///   primary := number | constant | function '(' expr ')' | function primary | '(' expr ')'
enum Calculator {
    enum Failure: Error, Equatable {
        case syntax, divisionByZero, notANumber, overflow, tooComplex
    }

    static let functions: [String: (Double) -> Double] = [
        "sqrt": { $0.squareRoot() }, "cbrt": { Foundation.cbrt($0) },
        "sin": { Foundation.sin($0) }, "cos": { Foundation.cos($0) }, "tan": { Foundation.tan($0) },
        "asin": { Foundation.asin($0) }, "acos": { Foundation.acos($0) }, "atan": { Foundation.atan($0) },
        "sinh": { Foundation.sinh($0) }, "cosh": { Foundation.cosh($0) }, "tanh": { Foundation.tanh($0) },
        "ln": { Foundation.log($0) }, "log": { Foundation.log10($0) }, "log2": { Foundation.log2($0) },
        "exp": { Foundation.exp($0) }, "abs": { Swift.abs($0) },
        "round": { $0.rounded() }, "floor": { Foundation.floor($0) }, "ceil": { Foundation.ceil($0) },
    ]

    static let constants: [String: Double] = ["pi": .pi, "π": .pi, "tau": 2 * .pi, "e": M_E]

    /// Evaluates `input`. Throws `Failure` for anything that isn't a finite number.
    static func evaluate(_ input: String) throws -> Double {
        guard input.count <= 256 else { throw Failure.tooComplex }
        var parser = Parser(tokens: try tokenize(input))
        let value = try parser.parseExpression()
        guard parser.atEnd else { throw Failure.syntax }
        return try check(value)
    }

    /// True when the text looks like arithmetic rather than a plain number or a word, so the
    /// command bar doesn't offer "42 = 42" or treat "e" as Euler's number.
    static func looksLikeExpression(_ input: String) -> Bool {
        guard let tokens = try? tokenize(input), tokens.count > 1 else { return false }
        return tokens.contains {
            switch $0 {
            case .op, .lparen, .function: true
            default: false
            }
        }
    }

    /// "1,234.5", "1.5e+21", "0.333333333333" — up to 12 significant digits.
    static func format(_ value: Double) -> String {
        if value == 0 { return "0" }
        let magnitude = Swift.abs(value)
        if magnitude >= 1e15 || magnitude < 1e-9 {
            return String(format: "%.10g", value)
        }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesSignificantDigits = true
        f.maximumSignificantDigits = 12
        f.locale = Locale(identifier: "en_US_POSIX")
        f.usesGroupingSeparator = true
        f.groupingSeparator = ","
        f.groupingSize = 3
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }

    // MARK: Tokens

    enum Token: Equatable {
        case number(Double)
        case op(Character)        // + - * / ^ % !
        case lparen, rparen
        case function(String)
        case constant(Double)
    }

    static func tokenize(_ input: String) throws -> [Token] {
        var tokens: [Token] = []
        let chars = Array(input.lowercased())
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace {
                i += 1
                continue
            }
            if c.isNumber || c == "." {
                var j = i
                var text = ""
                while j < chars.count {
                    let ch = chars[j]
                    if ch.isNumber || ch == "." || ch == "_" {
                        if ch != "_" { text.append(ch) }
                    } else if ch == ",", isThousandsSeparator(chars, at: j) {
                        // "1,000,000": skipped
                    } else {
                        break
                    }
                    j += 1
                }
                // Exponent: 1e3, 2.5e-4 (only when digits follow, so "2e" stays 2·e).
                if j < chars.count, chars[j] == "e" {
                    var k = j + 1
                    if k < chars.count, chars[k] == "+" || chars[k] == "-" { k += 1 }
                    if k < chars.count, chars[k].isNumber {
                        text.append("e")
                        text.append(contentsOf: chars[(j + 1)..<k])
                        j = k
                        while j < chars.count, chars[j].isNumber { text.append(chars[j]); j += 1 }
                    }
                }
                guard text.filter({ $0 == "." }).count <= 1, let value = Double(text) else { throw Failure.syntax }
                tokens.append(.number(value))
                i = j
                continue
            }
            if c.isLetter || c == "π" {
                var j = i
                var word = ""
                while j < chars.count, chars[j].isLetter || chars[j].isNumber && !word.isEmpty || chars[j] == "π" {
                    word.append(chars[j])
                    j += 1
                }
                if functions[word] != nil {
                    tokens.append(.function(word))
                } else if let value = constants[word] {
                    tokens.append(.constant(value))
                } else {
                    throw Failure.syntax
                }
                i = j
                continue
            }
            switch c {
            case "+", "-", "*", "/", "^", "%", "!": tokens.append(.op(c))
            case "×", "·", "∙": tokens.append(.op("*"))
            case "÷", ":": tokens.append(.op("/"))
            case "−", "–": tokens.append(.op("-"))
            case "(", "[": tokens.append(.lparen)
            case ")", "]": tokens.append(.rparen)
            default: throw Failure.syntax
            }
            i += 1
        }
        return tokens
    }

    /// A comma followed by exactly three digits ("1,000" but not "1,5" or "max(1,2)").
    private static func isThousandsSeparator(_ chars: [Character], at i: Int) -> Bool {
        guard i > 0, chars[i - 1].isNumber, i + 3 < chars.count + 1 else { return false }
        let digits = chars[(i + 1)...].prefix { $0.isNumber }
        return digits.count == 3
    }

    fileprivate static func check(_ v: Double) throws -> Double {
        if v.isNaN { throw Failure.notANumber }
        if v.isInfinite { throw Failure.overflow }
        return v
    }

    private struct Parser {
        let tokens: [Token]
        var pos = 0
        var depth = 0

        init(tokens: [Token]) { self.tokens = tokens }

        var atEnd: Bool { pos >= tokens.count }
        var peek: Token? { pos < tokens.count ? tokens[pos] : nil }

        mutating func descend() throws {
            depth += 1
            if depth > 64 { throw Failure.tooComplex } // bounded recursion: no stack overflow
        }

        mutating func parseExpression() throws -> Double {
            try descend(); defer { depth -= 1 }
            var value = try parseTerm()
            while let t = peek, case .op(let c) = t, c == "+" || c == "-" {
                pos += 1
                let rhs = try parseTerm()
                value = try check(c == "+" ? value + rhs : value - rhs)
            }
            return value
        }

        mutating func parseTerm() throws -> Double {
            var value = try parseUnary()
            while let t = peek {
                switch t {
                case .op(let c) where c == "*" || c == "/" || c == "%":
                    pos += 1
                    let rhs = try parseUnary()
                    switch c {
                    case "*": value = try check(value * rhs)
                    case "/":
                        guard rhs != 0 else { throw Failure.divisionByZero }
                        value = try check(value / rhs)
                    default:
                        guard rhs != 0 else { throw Failure.divisionByZero }
                        value = try check(fmod(value, rhs))
                    }
                case .constant, .function, .lparen:
                    // Implicit multiplication: 2pi, 3(4+1), 2 sqrt 9 (but "1 2" is a typo).
                    let rhs = try parseUnary()
                    value = try check(value * rhs)
                default:
                    return value
                }
            }
            return value
        }

        mutating func parseUnary() throws -> Double {
            if let t = peek, case .op(let c) = t, c == "-" || c == "+" {
                pos += 1
                try descend(); defer { depth -= 1 }
                let v = try parseUnary()
                return c == "-" ? -v : v
            }
            return try parsePower()
        }

        mutating func parsePower() throws -> Double {
            let base = try parsePostfix()
            if let t = peek, case .op("^") = t {
                pos += 1
                try descend(); defer { depth -= 1 }
                let exponent = try parseUnary()
                return try check(Foundation.pow(base, exponent))
            }
            return base
        }

        mutating func parsePostfix() throws -> Double {
            var value = try parsePrimary()
            while let t = peek, case .op(let c) = t, c == "%" || c == "!" {
                if c == "%" {
                    // Percent only when no operand follows ("50%", "200*15%"); otherwise modulo.
                    let next = pos + 1 < tokens.count ? tokens[pos + 1] : nil
                    switch next {
                    case .number?, .constant?, .function?, .lparen?: return value
                    default: break
                    }
                    pos += 1
                    value /= 100
                } else {
                    pos += 1
                    value = try factorial(value)
                }
            }
            return value
        }

        mutating func parsePrimary() throws -> Double {
            guard let t = peek else { throw Failure.syntax }
            pos += 1
            switch t {
            case .number(let v), .constant(let v):
                return v
            case .lparen:
                let v = try parseExpression()
                guard let close = peek, close == .rparen else { throw Failure.syntax }
                pos += 1
                return v
            case .function(let name):
                try descend(); defer { depth -= 1 }
                let arg: Double
                if let next = peek, next == .lparen {
                    arg = try parsePrimary()
                } else {
                    arg = try parsePostfix() // "sqrt 9"
                }
                return try check(functions[name]!(arg))
            default:
                throw Failure.syntax
            }
        }

        func factorial(_ v: Double) throws -> Double {
            guard v >= 0, v == v.rounded() else { throw Failure.notANumber }
            guard v <= 170 else { throw Failure.overflow }
            return (1...max(1, Int(v))).reduce(1.0) { $0 * Double($1) }
        }
    }
}

// MARK: - Fuzzy matching

/// Ranks a candidate against a query: exact > prefix > word prefix > acronym > subsequence.
/// Returns nil when the query's characters don't all appear in order. Case- and
/// diacritic-insensitive.
enum FuzzyMatcher {
    static func normalize(_ s: String) -> [Character] {
        Array(s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil))
    }

    static func score(_ query: String, in candidate: String) -> Double? {
        let q = normalize(query.trimmingCharacters(in: .whitespaces))
        let c = normalize(candidate)
        guard !q.isEmpty else { return 0 }
        guard q.count <= c.count else { return nil }
        if q == c { return 1000 }
        if c.starts(with: q) { return 900 - Double(c.count - q.count) }

        // Word-prefix ("code" in "Visual Studio Code"; "studio code").
        let words = wordStarts(c)
        let qs = String(q), cs = String(c)
        for start in words where start > 0 {
            if cs[cs.index(cs.startIndex, offsetBy: start)...].hasPrefix(qs) {
                return 800 - Double(start) - Double(c.count - q.count) * 0.5
            }
        }
        // Acronym ("vsc" → Visual Studio Code).
        if q.count >= 2, words.count >= q.count {
            let initials = words.map { c[$0] }
            if initials.starts(with: q) { return 700 - Double(words.count - q.count) }
        }
        // Subsequence with bonuses for consecutive runs and word starts. Too noisy for one or
        // two letters ("sa" would match half the Applications folder).
        guard q.count >= 3 else { return nil }
        var score = 0.0
        var qi = 0
        var previous = -2
        let starts = Set(words)
        for (ci, ch) in c.enumerated() where qi < q.count && ch == q[qi] {
            score += 10
            if ci == previous + 1 { score += 15 }
            if starts.contains(ci) { score += 20 }
            previous = ci
            qi += 1
        }
        guard qi == q.count else { return nil }
        return min(600, score) - Double(c.count) * 0.5
    }

    private static func wordStarts(_ c: [Character]) -> [Int] {
        var starts: [Int] = []
        for i in c.indices {
            let ch = c[i]
            guard ch.isLetter || ch.isNumber else { continue }
            if i == 0 { starts.append(i); continue }
            let prev = c[i - 1]
            if !(prev.isLetter || prev.isNumber) || (prev.isLowercase && ch.isUppercase) { starts.append(i) }
        }
        return starts
    }
}

// MARK: - Durations ("t 5m", "timer 1h30m", "25 min")

enum DurationParser {
    /// Parses "5m", "90s", "1h30m", "1:30" (m:ss), "25 min", "2 hours", a bare number = minutes.
    static func parse(_ text: String) -> TimeInterval? {
        let s = text.lowercased().replacingOccurrences(of: " ", with: "")
        guard !s.isEmpty else { return nil }
        if let v = Double(s), v > 0 { return v * 60 }
        let parts = s.split(separator: ":")
        if parts.count == 2 || parts.count == 3, parts.allSatisfy({ Int($0) != nil }) {
            let n = parts.compactMap { Int($0) }
            let total = parts.count == 2 ? n[0] * 60 + n[1] : n[0] * 3600 + n[1] * 60 + n[2]
            return total > 0 ? TimeInterval(total) : nil
        }
        let units: [(String, Double)] = [("hours", 3600), ("hour", 3600), ("hrs", 3600), ("hr", 3600), ("h", 3600),
                                         ("minutes", 60), ("minute", 60), ("mins", 60), ("min", 60), ("m", 60),
                                         ("seconds", 1), ("second", 1), ("secs", 1), ("sec", 1), ("s", 1)]
        var total = 0.0
        var rest = Substring(s)
        while !rest.isEmpty {
            let digits = rest.prefix { $0.isNumber || $0 == "." }
            guard !digits.isEmpty, let value = Double(digits) else { return nil }
            rest = rest.dropFirst(digits.count)
            guard let (unit, factor) = units.first(where: { rest.hasPrefix($0.0) }) else { return nil }
            rest = rest.dropFirst(unit.count)
            total += value * factor
        }
        return total > 0 && total <= 24 * 3600 * 7 ? total : nil
    }
}

// MARK: - Unit conversion ("10 km to mi", "72f in c")

enum UnitConversion {
    struct Query: Equatable {
        let value: Double
        let from: String
        let to: String
    }

    /// Splits "<number> <unit> (to|in|as|=|→) <unit>". Units may be glued to the number.
    static func split(_ text: String) -> Query? {
        let s = text.trimmingCharacters(in: .whitespaces)
        let separators = [" to ", " in ", " as ", " = ", " → ", " -> ", " into "]
        guard let sep = separators.compactMap({ s.range(of: $0, options: .caseInsensitive) }).first else { return nil }
        let lhs = s[..<sep.lowerBound].trimmingCharacters(in: .whitespaces)
        let to = s[sep.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !to.isEmpty else { return nil }
        var numberEnd = lhs.startIndex
        var seenDigit = false
        for (i, ch) in zip(lhs.indices, lhs) {
            if ch.isNumber || ch == "." || ch == "," || (i == lhs.startIndex && ch == "-") {
                if ch.isNumber { seenDigit = true }
                numberEnd = lhs.index(after: i)
            } else { break }
        }
        guard seenDigit, let value = Double(lhs[..<numberEnd].replacingOccurrences(of: ",", with: "")) else { return nil }
        let from = lhs[numberEnd...].trimmingCharacters(in: .whitespaces)
        guard !from.isEmpty else { return nil }
        return Query(value: value, from: from, to: to)
    }

    static func convert(_ text: String) -> (result: Measurement<Dimension>, from: Measurement<Dimension>)? {
        guard let q = split(text), let from = unit(q.from), let to = unit(q.to),
              type(of: from) == type(of: to), from != to else { return nil }
        let source = Measurement(value: q.value, unit: from)
        return (source.converted(to: to), source)
    }

    static func format(_ m: Measurement<Dimension>) -> String {
        let f = MeasurementFormatter()
        f.unitOptions = .providedUnit
        f.unitStyle = .medium
        f.numberFormatter.maximumFractionDigits = Swift.abs(m.value) < 1 ? 6 : 4
        return f.string(from: m)
    }

    static func unit(_ name: String) -> Dimension? {
        let key = name.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        return table[key] ?? (key.hasSuffix("s") ? table[String(key.dropLast())] : nil)
    }

    private static let table: [String: Dimension] = {
        var t: [String: Dimension] = [:]
        func add(_ unit: Dimension, _ names: String...) { names.forEach { t[$0] = unit } }
        // Length
        add(UnitLength.millimeters, "mm", "millimeter", "millimetre")
        add(UnitLength.centimeters, "cm", "centimeter", "centimetre")
        add(UnitLength.meters, "m", "meter", "metre")
        add(UnitLength.kilometers, "km", "kilometer", "kilometre")
        add(UnitLength.inches, "in", "inch", "inche", "\"")
        add(UnitLength.feet, "ft", "foot", "feet", "'")
        add(UnitLength.yards, "yd", "yard")
        add(UnitLength.miles, "mi", "mile")
        add(UnitLength.nauticalMiles, "nmi", "nautical mile")
        // Mass
        add(UnitMass.milligrams, "mg", "milligram")
        add(UnitMass.grams, "g", "gram", "gr")
        add(UnitMass.kilograms, "kg", "kilo", "kilogram")
        add(UnitMass.metricTons, "t", "tonne", "ton")
        add(UnitMass.ounces, "oz", "ounce")
        add(UnitMass.pounds, "lb", "lbs", "pound")
        add(UnitMass.stones, "st", "stone")
        // Temperature
        add(UnitTemperature.celsius, "c", "°c", "celsius", "degc")
        add(UnitTemperature.fahrenheit, "f", "°f", "fahrenheit", "degf")
        add(UnitTemperature.kelvin, "k", "kelvin")
        // Volume
        add(UnitVolume.milliliters, "ml", "milliliter", "millilitre")
        add(UnitVolume.liters, "l", "liter", "litre")
        add(UnitVolume.cups, "cup")
        add(UnitVolume.fluidOunces, "floz", "fl oz", "fluid ounce")
        add(UnitVolume.gallons, "gal", "gallon")
        add(UnitVolume.pints, "pt", "pint")
        add(UnitVolume.teaspoons, "tsp", "teaspoon")
        add(UnitVolume.tablespoons, "tbsp", "tablespoon")
        // Speed
        add(UnitSpeed.kilometersPerHour, "kmh", "km/h", "kph")
        add(UnitSpeed.milesPerHour, "mph")
        add(UnitSpeed.metersPerSecond, "m/s", "mps")
        add(UnitSpeed.knots, "kn", "knot", "kt")
        // Area
        add(UnitArea.squareMeters, "m2", "m²", "sqm", "square meter")
        add(UnitArea.squareFeet, "ft2", "ft²", "sqft", "square foot", "square feet")
        add(UnitArea.squareKilometers, "km2", "km²")
        add(UnitArea.squareMiles, "mi2", "mi²", "sqmi")
        add(UnitArea.hectares, "ha", "hectare")
        add(UnitArea.acres, "ac", "acre")
        // Time
        add(UnitDuration.seconds, "s", "sec", "second")
        add(UnitDuration.minutes, "min", "minute")
        add(UnitDuration.hours, "h", "hr", "hour")
        // Data
        add(UnitInformationStorage.bytes, "b", "byte")
        add(UnitInformationStorage.kilobytes, "kb", "kilobyte")
        add(UnitInformationStorage.megabytes, "mb", "megabyte")
        add(UnitInformationStorage.gigabytes, "gb", "gigabyte")
        add(UnitInformationStorage.terabytes, "tb", "terabyte")
        add(UnitInformationStorage.kibibytes, "kib")
        add(UnitInformationStorage.mebibytes, "mib")
        add(UnitInformationStorage.gibibytes, "gib")
        // Energy / pressure
        add(UnitEnergy.kilocalories, "kcal", "calorie", "cal")
        add(UnitEnergy.kilojoules, "kj", "kilojoule")
        add(UnitPressure.bars, "bar")
        add(UnitPressure.poundsForcePerSquareInch, "psi")
        return t
    }()
}

// MARK: - Currency ("100 usd to eur", "€50 in $", "50 eur")

enum CurrencyQuery {
    struct Parsed: Equatable {
        let amount: Double
        let from: String
        let to: String?
    }

    static let symbols: [String: String] = ["$": "USD", "€": "EUR", "£": "GBP", "¥": "JPY", "₹": "INR", "₩": "KRW",
                                            "₺": "TRY", "₽": "RUB", "₿": "BTC", "chf": "CHF", "fr": "CHF"]
    /// Common names so "100 dollars in euros" works too.
    static let names: [String: String] = ["dollar": "USD", "dollars": "USD", "euro": "EUR", "euros": "EUR",
                                          "pound": "GBP", "pounds": "GBP", "yen": "JPY", "rupee": "INR", "rupees": "INR",
                                          "franc": "CHF", "francs": "CHF"]

    /// `known` is the set of ISO codes we have rates for (or a default list before the first fetch).
    static func parse(_ text: String, known: Set<String>) -> Parsed? {
        var s = text.trimmingCharacters(in: .whitespaces)
        var target: String?
        for sep in [" to ", " in ", " = ", " → ", " -> ", " into "] {
            if let r = s.range(of: sep, options: .caseInsensitive) {
                target = String(s[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                s = String(s[..<r.lowerBound])
                break
            }
        }
        // Leading or trailing currency, number in between: "€50", "50€", "50 eur", "usd 50".
        let compact = s.replacingOccurrences(of: " ", with: "")
        let numberChars = CharacterSet(charactersIn: "0123456789.,")
        guard let firstDigit = compact.unicodeScalars.firstIndex(where: { CharacterSet.decimalDigits.contains($0) }) else { return nil }
        let prefix = String(compact.unicodeScalars[..<firstDigit])
        let afterPrefix = compact.unicodeScalars[firstDigit...]
        let numberEnd = afterPrefix.firstIndex(where: { !numberChars.contains($0) }) ?? afterPrefix.endIndex
        let numberText = String(afterPrefix[..<numberEnd]).replacingOccurrences(of: ",", with: "")
        let suffix = String(afterPrefix[numberEnd...])
        guard let amount = Double(numberText), prefix.isEmpty != suffix.isEmpty else { return nil }
        guard let from = code(prefix.isEmpty ? suffix : prefix, known: known) else { return nil }
        var to: String?
        if let target {
            guard let t = code(target, known: known) else { return nil }
            to = t
        }
        return Parsed(amount: amount, from: from, to: to)
    }

    static func code(_ token: String, known: Set<String>) -> String? {
        let t = token.trimmingCharacters(in: .whitespaces)
        if let c = symbols[t.lowercased()] ?? symbols[t] { return c }
        if let c = names[t.lowercased()] { return c }
        let upper = t.uppercased()
        return upper.count == 3 && known.contains(upper) ? upper : nil
    }
}
