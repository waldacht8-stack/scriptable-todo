import SwiftUI
import CoreLocation

// 朝のブリーフィングの天気（Open-Meteo：無料・キー不要）。位置は一度だけ取得して保存する。

struct WakeWeather: Codable {
    var fetchedAt: Date
    var code: Int
    var temp: Double
    var high: Double
    var low: Double
    var rain: Int

    var text: String {
        switch code {
        case 0: return "快晴"
        case 1: return "晴れ"
        case 2: return "晴れ時々くもり"
        case 3: return "くもり"
        case 45, 48: return "霧"
        case 51, 53, 55, 56, 57: return "霧雨"
        case 61, 63, 66, 80, 81: return "雨"
        case 65, 67, 82: return "強い雨"
        case 71, 73, 75, 77, 85, 86: return "雪"
        case 95, 96, 99: return "雷雨"
        default: return "―"
        }
    }

    var symbol: String {
        switch code {
        case 0, 1: return "sun.max.fill"
        case 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}

struct WakePlace: Codable {
    var lat: Double
    var lon: Double
}

private struct OpenMeteoResponse: Decodable {
    struct Current: Decodable {
        let temperature: Double
        let code: Int
        enum CodingKeys: String, CodingKey {
            case temperature = "temperature_2m"
            case code = "weather_code"
        }
    }
    struct Daily: Decodable {
        let high: [Double]
        let low: [Double]
        let rain: [Int?]
        enum CodingKeys: String, CodingKey {
            case high = "temperature_2m_max"
            case low = "temperature_2m_min"
            case rain = "precipitation_probability_max"
        }
    }
    let current: Current
    let daily: Daily
}

@MainActor
final class WakeWeatherModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var weather: WakeWeather?
    @Published var needsLocation = false
    @Published var loading = false
    private var manager: CLLocationManager?

    static let weatherFile = "wake-weather.json"
    static let placeFile = "wake-place.json"

    func load(demo: Bool) {
        if demo {
            weather = WakeWeather(fetchedAt: .now, code: 2, temp: 18, high: 23, low: 14, rain: 20)
            return
        }
        weather = SharedStore.load(WakeWeather.self, from: Self.weatherFile)
        if let w = weather, Date().timeIntervalSince(w.fetchedAt) < 3600 { return }
        if let place = SharedStore.load(WakePlace.self, from: Self.placeFile) {
            Task { await fetch(place) }
        } else {
            needsLocation = true
        }
    }

    /// 位置情報の許可を求めて一度だけ取得する
    func locate() {
        let m = CLLocationManager()
        m.delegate = self
        m.desiredAccuracy = kCLLocationAccuracyKilometer
        manager = m
        loading = true
        if m.authorizationStatus == .notDetermined {
            m.requestWhenInUseAuthorization()
        } else {
            m.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.manager?.requestLocation()
            } else if status != .notDetermined {
                self.loading = false
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        // 天気に使うだけなので、細かい位置は保存しない（小数2桁＝約1km）
        let place = WakePlace(lat: (loc.coordinate.latitude * 100).rounded() / 100,
                              lon: (loc.coordinate.longitude * 100).rounded() / 100)
        Task { @MainActor in
            SharedStore.save(place, to: Self.placeFile)
            self.needsLocation = false
            await self.fetch(place)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.loading = false }
    }

    func fetch(_ place: WakePlace) async {
        loading = true
        defer { loading = false }
        let s = "https://api.open-meteo.com/v1/forecast?latitude=\(place.lat)&longitude=\(place.lon)"
            + "&current=temperature_2m,weather_code&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max"
            + "&timezone=auto&forecast_days=1"
        guard let url = URL(string: s) else { return }
        let result = try? await URLSession.shared.data(from: url)
        guard let data = result?.0,
              let r = try? JSONDecoder().decode(OpenMeteoResponse.self, from: data) else { return }
        let w = WakeWeather(fetchedAt: .now, code: r.current.code, temp: r.current.temperature,
                            high: r.daily.high.first ?? r.current.temperature, low: r.daily.low.first ?? r.current.temperature,
                            rain: (r.daily.rain.first ?? nil) ?? 0)
        weather = w
        SharedStore.save(w, to: Self.weatherFile)
    }
}

/// 天気のカード
struct WakeWeatherCard: View {
    @ObservedObject var weather: WakeWeatherModel
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WakeCardTitle(text: "今日の天気", icon: "cloud.sun.fill")
            if let w = weather.weather {
                // 狭い画面でも切れないよう、上段に絵と気温、下段に天気と最高・最低・降水確率
                let temp: String = "\(Int(w.temp.rounded()))°"
                let range: String = "最高 \(Int(w.high.rounded()))°・最低 \(Int(w.low.rounded()))°"
                let rain: String = "降水 \(w.rain)%"
                let rainColor: Color = w.rain >= 50 ? p.overdue : p.accent
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: w.symbol).symbolRenderingMode(.multicolor).font(Font.system(size: 44))
                    Text(temp).font(Font.system(size: 44, weight: .heavy, design: p.fontDesign)).foregroundStyle(p.text)
                    Spacer(minLength: 0)
                    Text(w.text).font(Font.title3.weight(.bold)).foregroundStyle(p.text)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                HStack(spacing: 12) {
                    Text(range).font(Font.subheadline.weight(.semibold)).foregroundStyle(p.sub)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Label(rain, systemImage: "umbrella.fill").font(Font.subheadline.weight(.bold))
                        .foregroundStyle(rainColor).lineLimit(1)
                }
            } else if weather.needsLocation {
                Button { weather.locate() } label: {
                    Label(weather.loading ? "取得中…" : "今いる場所の天気を表示する", systemImage: "location.fill")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(p.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: min(p.radius, 14), style: .continuous))
                        .foregroundStyle(p.accent)
                }
                .buttonStyle(.plain)
            } else {
                Text(weather.loading ? "取得中…" : "天気を取得できませんでした").font(.subheadline).foregroundStyle(p.sub)
            }
        }
        .paletteCard(p)
    }
}
