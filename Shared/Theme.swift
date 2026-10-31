import SwiftUI
import HealthKit
import GymNetoKit

extension ActivityState {
    var color: Color {
        switch self {
        case .work: return Theme.work
        case .rest: return Theme.rest
        case .garbage: return Theme.garbage
        }
    }

    var symbol: String {
        switch self {
        case .work: return "flame.fill"
        case .rest: return "pause.circle.fill"
        case .garbage: return "trash.fill"
        }
    }
}

enum Theme {
    static let work = Color(red: 0.62, green: 0.98, blue: 0.20)    // neon lime
    static let rest = Color(red: 0.25, green: 0.70, blue: 1.00)    // calm blue
    static let garbage = Color(red: 1.00, green: 0.33, blue: 0.30) // alert red
    static let card = Color.white.opacity(0.08)
}

extension WorkoutKind {
    var activityType: HKWorkoutActivityType {
        switch self {
        case .strength: return .traditionalStrengthTraining
        case .functional: return .functionalStrengthTraining
        case .hiit: return .highIntensityIntervalTraining
        case .cardio: return .mixedCardio
        case .running: return .running
        case .cycling: return .cycling
        case .rowing: return .rowing
        case .boxing: return .boxing
        }
    }

    init(activityType: HKWorkoutActivityType) {
        switch activityType {
        case .functionalStrengthTraining, .crossTraining: self = .functional
        case .highIntensityIntervalTraining: self = .hiit
        case .mixedCardio, .elliptical, .stairClimbing, .stairs: self = .cardio
        case .cycling, .handCycling: self = .cycling
        case .rowing, .paddleSports: self = .rowing
        case .boxing, .kickboxing, .martialArts: self = .boxing
        case .running, .walking: self = .running
        default: self = .strength
        }
    }
}

/// Three-ring style bar: work / rest / garbage proportions.
struct SplitBar: View {
    let totals: Totals
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(ActivityState.allCases, id: \.self) { state in
                    let value = totals[state]
                    if value > 0 {
                        Capsule()
                            .fill(state.color)
                            .frame(width: max(4, geo.size.width * value / max(1, totals.total)))
                    }
                }
            }
        }
        .frame(height: height)
        .background(Capsule().fill(Color.gray.opacity(0.25)))
        .animation(.easeInOut, value: totals)
    }
}

/// Profile persistence shared by both apps.
enum ProfileStore {
    private static let key = "gymneto.profile"

    static func load() -> UserProfile {
        guard let data = UserDefaults.standard.data(forKey: key),
              let profile = try? JSONDecoder().decode(UserProfile.self, from: data) else { return .default }
        return profile
    }

    static func save(_ profile: UserProfile) {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
