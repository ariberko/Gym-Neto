import Foundation
import CoreMotion
import GymNetoKit

/// Reads accelerometer + gyroscope at 25 Hz and pedometer cadence, and boils them down to
/// a few numbers once a second: motion intensity, rotation intensity, posture, cadence.
/// Used on both Apple Watch (wrist) and iPhone (pocket / hand).
final class MotionSampler {

    struct Reading {
        var accelRMS: Double?
        var rotationRMS: Double?
        var posture: DevicePosture?
        var cadence: Double?
    }

    private let motion = CMMotionManager()
    private let pedometer = CMPedometer()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "gymneto.motion"
        q.maxConcurrentOperationCount = 1
        return q
    }()

    private let lock = NSLock()
    private var accel: [Double] = []
    private var rotation: [Double] = []
    private var gravity: CMAcceleration?
    private var cadence: Double?
    private var cadenceDate: Date?
    private let window = 50 // 2 s at 25 Hz

    /// On the watch "screen up" means wrist raised toward the face; on the phone it means held in hand.
    private let isWatch: Bool

    init(isWatch: Bool) {
        self.isWatch = isWatch
    }

    func start() {
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 1.0 / 25.0
            motion.startDeviceMotionUpdates(to: queue) { [weak self] data, _ in
                guard let self, let d = data else { return }
                let a = d.userAcceleration
                let r = d.rotationRate
                let aMag = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
                let rMag = sqrt(r.x * r.x + r.y * r.y + r.z * r.z)
                self.lock.lock()
                self.accel.append(aMag)
                self.rotation.append(rMag)
                if self.accel.count > self.window { self.accel.removeFirst(self.accel.count - self.window) }
                if self.rotation.count > self.window { self.rotation.removeFirst(self.rotation.count - self.window) }
                self.gravity = d.gravity
                self.lock.unlock()
            }
        }
        if CMPedometer.isCadenceAvailable() {
            pedometer.startUpdates(from: Date()) { [weak self] data, _ in
                guard let self, let data else { return }
                self.lock.lock()
                // currentCadence is steps per second.
                self.cadence = (data.currentCadence?.doubleValue ?? 0) * 60
                self.cadenceDate = Date()
                self.lock.unlock()
            }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        pedometer.stopUpdates()
    }

    func read() -> Reading {
        lock.lock()
        defer { lock.unlock() }
        var reading = Reading()
        if !accel.isEmpty {
            reading.accelRMS = sqrt(accel.reduce(0) { $0 + $1 * $1 } / Double(accel.count))
            reading.rotationRMS = sqrt(rotation.reduce(0) { $0 + $1 * $1 } / Double(rotation.count))
        }
        if let g = gravity {
            reading.posture = posture(for: g)
        }
        // Pedometer only pushes while walking; a stale value means "not walking".
        if let date = cadenceDate, Date().timeIntervalSince(date) < 6 {
            reading.cadence = cadence
        } else if CMPedometer.isCadenceAvailable() {
            reading.cadence = 0
        }
        return reading
    }

    private func posture(for g: CMAcceleration) -> DevicePosture {
        if isWatch {
            // Watch face pointing up / toward the eyes: gravity mostly along -z, wrist tilted toward the body.
            return (g.z < -0.70 && g.y < 0.1) ? .screenUp : .other
        } else {
            // Phone held in front of you in portrait: tilted ~30-70 degrees, top of the phone up.
            return (g.y < -0.45 && g.z < -0.25) ? .screenUp : .other
        }
    }
}
