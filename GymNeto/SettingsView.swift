import SwiftUI
import GymNetoKit

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Count short breaks as rest", isOn: bind(\.autoRestEnabled))
                    if model.profile.autoRestEnabled {
                        Stepper("Rest limit: \(Format.clock(model.profile.restAllowance))",
                                value: bind(\.restAllowance), in: 30...300, step: 15)
                    }
                    Stepper("Rest timer: \(Format.clock(model.profile.plannedRestDuration))",
                            value: bind(\.plannedRestDuration), in: 15...300, step: 15)
                } header: {
                    Text("Rest")
                } footer: {
                    Text("A break shorter than the rest limit is healthy rest. Anything longer becomes garbage time. Turn it off if every second off the bar should count as garbage.")
                }

                Section {
                    Stepper(model.profile.nudgeAfter == 0 ? "Nudges off" : "Nudge after \(Format.clock(model.profile.nudgeAfter))",
                            value: bind(\.nudgeAfter), in: 0...180, step: 15)
                    VStack(alignment: .leading) {
                        Text("Strictness")
                        Slider(value: bind(\.strictness), in: 0...1) {
                            Text("Strictness")
                        } minimumValueLabel: { Text("Chill") } maximumValueLabel: { Text("Strict") }
                    }
                } header: {
                    Text("Coaching")
                } footer: {
                    Text("Your watch taps your wrist when garbage time builds up. Strict mode needs more effort before a moment counts as work.")
                }

                Section {
                    Stepper("Resting HR: \(Int(model.profile.restingHeartRate))", value: bind(\.restingHeartRate), in: 35...100)
                    Stepper("Max HR: \(Int(model.profile.maxHeartRate))", value: bind(\.maxHeartRate), in: 140...220)
                } header: {
                    Text("Heart")
                } footer: {
                    Text("Filled in from Apple Health automatically (resting heart rate and age).")
                }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private func bind<T>(_ keyPath: WritableKeyPath<UserProfile, T>) -> Binding<T> {
        Binding(get: { model.profile[keyPath: keyPath] },
                set: { var p = model.profile; p[keyPath: keyPath] = $0; model.updateProfile(p) })
    }
}
