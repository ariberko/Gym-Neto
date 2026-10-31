import Foundation

public enum Format {
    /// 75 -> "1:15", 3725 -> "1:02:05"
    public static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    /// 75 -> "1 min", 3725 -> "1h 2m", 30 -> "30 sec"
    public static func minutes(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded()))
        if s < 60 { return "\(s) sec" }
        let m = s / 60
        if m < 60 { return "\(m) min" }
        return "\(m / 60)h \(m % 60)m"
    }

    public static func percent(_ ratio: Double) -> String {
        "\(Int((ratio * 100).rounded()))%"
    }
}

/// Messages between the watch and the phone (WatchConnectivity payloads).
public enum SyncMessage: Codable, Sendable {
    case live(LiveSnapshot)
    case finished(WorkoutRecord)
    case ended
    case profile(UserProfile)

    public static let key = "gymneto"

    public func encoded() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(self) else { return [:] }
        return [Self.key: data]
    }

    public static func decode(_ dict: [String: Any]) -> SyncMessage? {
        guard let data = dict[key] as? Data else { return nil }
        return try? JSONDecoder().decode(SyncMessage.self, from: data)
    }
}

extension GarbageReason: CodingKeyRepresentable {}
