import Foundation
import GymNetoKit
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Shares the latest `NetGlance` between the watch app and its watch face widget
/// through an App Group.
enum GlanceStore {
    static let appGroup = "group.com.gymneto.app"
    private static let key = "gymneto.glance"
    private static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    static func load() -> NetGlance {
        guard let data = defaults.data(forKey: key),
              let glance = try? JSONDecoder().decode(NetGlance.self, from: data) else { return NetGlance() }
        return glance
    }

    static func save(_ glance: NetGlance, reloadWidgets: Bool) {
        if let data = try? JSONEncoder().encode(glance) {
            defaults.set(data, forKey: key)
        }
        #if canImport(WidgetKit)
        if reloadWidgets { WidgetCenter.shared.reloadAllTimelines() }
        #endif
    }
}
