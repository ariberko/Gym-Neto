import Foundation
import WatchConnectivity
import GymNetoKit

/// Watch -> iPhone link: live snapshots (best effort) and finished workouts (guaranteed delivery).
final class PhoneConnector: NSObject, WCSessionDelegate {
    static let shared = PhoneConnector()

    /// Called when the phone pushes new settings.
    var onProfile: (@MainActor (UserProfile) -> Void)?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ message: SyncMessage, reliable: Bool) {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        let payload = message.encoded()
        if reliable {
            session.transferUserInfo(payload)          // queued, survives the phone being away
        } else if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let msg = SyncMessage.decode(session.receivedApplicationContext) { handle(msg) }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let msg = SyncMessage.decode(applicationContext) { handle(msg) }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let msg = SyncMessage.decode(message) { handle(msg) }
    }

    private func handle(_ message: SyncMessage) {
        if case .profile(let profile) = message {
            Task { @MainActor in self.onProfile?(profile) }
        }
    }
}
