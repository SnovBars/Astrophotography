import CoreMotion
import Combine

@MainActor
final class CoreMotionManager: ObservableObject {
    @Published var roll: Double = 0
    @Published var pitch: Double = 0

    private let motionManager = CMMotionManager()
    private let queue = OperationQueue()

    func startUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1/30
        motionManager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let motion = motion else { return }
            Task { @MainActor in
                self?.roll = motion.attitude.roll * 180 / .pi
                self?.pitch = motion.attitude.pitch * 180 / .pi
            }
        }
    }

    func stopUpdates() {
        motionManager.stopDeviceMotionUpdates()
    }
}