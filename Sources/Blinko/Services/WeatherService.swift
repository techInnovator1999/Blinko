import AppKit
import CoreLocation
import Observation

/// Weather from Open-Meteo (no API key).
///
/// Runs only while the weather module is on: one fetch at start (or the cached result if it
/// is fresh), then a 30-minute timer with generous tolerance, plus a catch-up on wake.
/// Location is a one-shot CoreLocation fix (When In Use), cached for the session; the
/// manual city from Settings is the fallback. Network and JSON decoding stay off main.
@MainActor
@Observable
final class WeatherService: NSObject {
    static let shared = WeatherService()

    struct Hour: Codable, Equatable, Identifiable {
        var date: Date
        var temperature: Double
        var code: Int
        var isDay: Bool
        var id: Date { date }
    }

    struct Report: Codable, Equatable {
        var temperature: Double
        var code: Int
        var isDay: Bool
        var high: Double
        var low: Double
        var hours: [Hour]
        var place: String
        var fetchedAt: Date
    }

    struct City: Identifiable, Equatable {
        var name: String
        var detail: String
        var latitude: Double
        var longitude: Double
        var id: String { "\(latitude),\(longitude)" }
    }

    private(set) var report: Report?
    private(set) var isLoading = false
    private(set) var failed = false
    private(set) var locationStatus: CLAuthorizationStatus = CLLocationManager().authorizationStatus

    /// Hours still ahead of now (the cached report may be up to half an hour old).
    var upcomingHours: [Hour] {
        guard let report else { return [] }
        let now = Date.now.addingTimeInterval(-1800)
        return Array(report.hours.filter { $0.date > now }.prefix(5))
    }

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var manager: CLLocationManager?
    @ObservationIgnored private var fix: CLLocation?
    @ObservationIgnored private var running = false
    @ObservationIgnored private let cacheKey = "weatherCache"
    private static let refreshInterval: TimeInterval = 30 * 60

    func refresh() {
        Preferences.shared.weatherEnabled ? start() : stop()
    }

    private func start() {
        guard !running else { return }
        running = true
        if report == nil, let data = UserDefaults.standard.data(forKey: cacheKey) {
            report = try? JSONDecoder().decode(Report.self, from: data)
        }
        update(force: false)

        let t = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update(force: true) }
        }
        t.tolerance = 5 * 60
        RunLoop.main.add(t, forMode: .common)
        timer = t
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update(force: false) }
        }
    }

    private func stop() {
        guard running else { return }
        running = false
        timer?.invalidate()
        timer = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        manager?.delegate = nil
        manager = nil
    }

    /// Location / city settings changed: drop the cached report and fetch again.
    func locationSettingsChanged() {
        fix = nil
        report = nil
        UserDefaults.standard.removeObject(forKey: cacheKey)
        if running { update(force: true) }
    }

    // MARK: Location

    private func update(force: Bool) {
        if !force, let report, Date().timeIntervalSince(report.fetchedAt) < Self.refreshInterval - 120 { return }
        let prefs = Preferences.shared
        if prefs.weatherUseLocation {
            let status = CLLocationManager().authorizationStatus
            locationStatus = status
            switch status {
            case .authorizedAlways, .authorized:
                if let fix, Date().timeIntervalSince(fix.timestamp) < 3 * 3600 {
                    fetch(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude, place: "")
                } else {
                    requestFix(askPermission: false)
                }
                return
            case .notDetermined:
                requestFix(askPermission: true)
                return
            default:
                break // denied: use the manual city if there is one
            }
        }
        guard prefs.weatherLatitude != 0 || prefs.weatherLongitude != 0 else { return }
        fetch(latitude: prefs.weatherLatitude, longitude: prefs.weatherLongitude, place: prefs.weatherCity)
    }

    private func requestFix(askPermission: Bool) {
        let m = manager ?? CLLocationManager()
        m.delegate = self
        m.desiredAccuracy = kCLLocationAccuracyKilometer
        manager = m
        if askPermission {
            NSApp.activate(ignoringOtherApps: true) // the prompt must be in front
            m.requestWhenInUseAuthorization()
        } else {
            m.requestLocation()
        }
    }

    // MARK: Network

    private func fetch(latitude: Double, longitude: Double, place: String) {
        guard !isLoading else { return }
        isLoading = true
        let fahrenheit = Locale.current.measurementSystem == .us
        // `download` is nonisolated: the request and JSON decoding run off the main actor.
        Task(priority: .utility) { [weak self] in
            let result = await Self.download(latitude: latitude, longitude: longitude, place: place, fahrenheit: fahrenheit)
            guard let self else { return }
            self.isLoading = false
            self.failed = result == nil
            guard let result else { return }
            self.report = result
            if let data = try? JSONEncoder().encode(result) {
                UserDefaults.standard.set(data, forKey: self.cacheKey)
            }
        }
    }

    private nonisolated static func download(latitude: Double, longitude: Double, place: String, fahrenheit: Bool) async -> Report? {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(format: "%.2f", latitude)),
            .init(name: "longitude", value: String(format: "%.2f", longitude)),
            .init(name: "current", value: "temperature_2m,weather_code,is_day"),
            .init(name: "hourly", value: "temperature_2m,weather_code,is_day"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            .init(name: "forecast_days", value: "2"),
            .init(name: "timezone", value: "auto"),
            .init(name: "timeformat", value: "unixtime"),
            .init(name: "temperature_unit", value: fahrenheit ? "fahrenheit" : "celsius"),
        ]
        guard let url = c.url,
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(ForecastResponse.self, from: data)
        else { return nil }

        let h = decoded.hourly
        let count = min(h.time.count, h.temperature_2m.count, h.weather_code.count, h.is_day.count)
        let hours = (0..<count).map {
            Hour(date: Date(timeIntervalSince1970: h.time[$0]), temperature: h.temperature_2m[$0],
                 code: h.weather_code[$0], isDay: h.is_day[$0] != 0)
        }
        return Report(temperature: decoded.current.temperature_2m, code: decoded.current.weather_code,
                      isDay: decoded.current.is_day != 0,
                      high: decoded.daily.temperature_2m_max.first ?? decoded.current.temperature_2m,
                      low: decoded.daily.temperature_2m_min.first ?? decoded.current.temperature_2m,
                      hours: hours, place: place, fetchedAt: .now)
    }

    /// City search for Settings (Open-Meteo geocoding).
    nonisolated static func searchCities(_ query: String) async -> [City] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return [] }
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [.init(name: "name", value: q), .init(name: "count", value: "6"),
                        .init(name: "language", value: Locale.current.language.languageCode?.identifier ?? "en"),
                        .init(name: "format", value: "json")]
        guard let url = c.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let decoded = try? JSONDecoder().decode(GeocodingResponse.self, from: data)
        else { return [] }
        return (decoded.results ?? []).map {
            City(name: $0.name, detail: [$0.admin1, $0.country].compactMap { $0 }.joined(separator: ", "),
                 latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    /// Design-time data for snapshot rendering.
    func injectPreview(_ report: Report) { self.report = report }
}

extension WeatherService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.locationStatus = status
                guard self.running else { return }
                if status == .authorizedAlways || status == .authorized {
                    manager.requestLocation()
                } else if status == .denied || status == .restricted {
                    self.update(force: true) // falls back to the manual city
                }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.fix = location
                self.fetch(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, place: "")
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                // No fix: use the manual city, if any.
                let prefs = Preferences.shared
                guard prefs.weatherLatitude != 0 || prefs.weatherLongitude != 0 else { self.failed = true; return }
                self.fetch(latitude: prefs.weatherLatitude, longitude: prefs.weatherLongitude, place: prefs.weatherCity)
            }
        }
    }
}

// MARK: - Open-Meteo payloads

private struct ForecastResponse: Decodable {
    struct Current: Decodable { var temperature_2m: Double; var weather_code: Int; var is_day: Int }
    struct Hourly: Decodable { var time: [Double]; var temperature_2m: [Double]; var weather_code: [Int]; var is_day: [Int] }
    struct Daily: Decodable { var temperature_2m_max: [Double]; var temperature_2m_min: [Double] }
    var current: Current
    var hourly: Hourly
    var daily: Daily
}

private struct GeocodingResponse: Decodable {
    struct Result: Decodable {
        var name: String
        var latitude: Double
        var longitude: Double
        var country: String?
        var admin1: String?
    }
    var results: [Result]?
}

// MARK: - WMO weather codes

enum WeatherCode {
    static func symbol(_ code: Int, isDay: Bool) -> String {
        switch code {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51, 53, 55, 56, 57: "cloud.drizzle.fill"
        case 65, 67, 82: "cloud.heavyrain.fill"
        case 61, 63, 66, 80, 81: "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: "cloud.snow.fill"
        case 95, 96, 99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    static func description(_ code: Int) -> String {
        switch code {
        case 0: String(localized: "Clear")
        case 1: String(localized: "Mostly Clear")
        case 2: String(localized: "Partly Cloudy")
        case 3: String(localized: "Cloudy")
        case 45, 48: String(localized: "Fog")
        case 51, 53, 55, 56, 57: String(localized: "Drizzle")
        case 61, 63, 66, 80, 81: String(localized: "Rain")
        case 65, 67, 82: String(localized: "Heavy Rain")
        case 71, 73, 75, 77, 85, 86: String(localized: "Snow")
        case 95, 96, 99: String(localized: "Thunderstorm")
        default: String(localized: "Cloudy")
        }
    }
}
