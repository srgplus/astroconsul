import Foundation

@MainActor
final class CosmicWeatherViewModel: ObservableObject {

    enum State: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var days: [ForecastDay] = []

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    #if DEBUG
    /// Seeds a loaded state for previews and the `-uiPreviewWeather` harness,
    /// so the screens can be checked without an account.
    init(previewDays: [ForecastDay]) {
        self.api = .shared
        self.days = previewDays
        self.state = .loaded
    }
    #endif

    var today: ForecastDay? { days.first }

    /// High and low across the whole forecast window — the closest honest
    /// analogue to Weather's H/L, since the engine yields one TII per day.
    var high: Double? { days.map(\.tii).max() }
    var low: Double? { days.map(\.tii).min() }

    func load(profileId: String, showSpinner: Bool = true) async {
        if showSpinner, days.isEmpty { state = .loading }

        do {
            let response = try await api.fetchForecast(profileId: profileId)
            days = response.days
            state = .loaded
        } catch let error as APIError {
            NSLog("[Weather] forecast failed for \(profileId): \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
        } catch {
            NSLog("[Weather] forecast failed for \(profileId): \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
        }
    }
}
