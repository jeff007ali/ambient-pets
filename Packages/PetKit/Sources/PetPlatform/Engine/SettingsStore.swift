import Foundation
import Observation
import PetCore

/// `AppSettings` persisted as JSON in UserDefaults. Observable for SwiftUI.
@MainActor
@Observable
public final class SettingsStore {
    public var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            save()
            onChange?(oldValue, settings)
        }
    }

    @ObservationIgnored public var onChange: ((AppSettings, AppSettings) -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key = "settings.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(AppSettings.self, from: $0) } ?? AppSettings()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: key) }
    }

    public func resetToDefaults() { settings = AppSettings() }
}
