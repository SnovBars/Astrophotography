import SwiftUI
import AVFoundation

@MainActor
final class AstrophotographyViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var isSessionActive = false
    @Published var iso: Float = 32.0
    @Published var shutterSpeedSeconds: Float = 0.1   // теперь Float
    @Published var focus: Float = 0.5
    @Published var whiteBalanceKelvin: Float = 5000

    // MARK: - Dependencies
    private(set) var cameraManager = CameraManager()

    // MARK: - Computed
    var shutterSpeedCMTime: CMTime {
        CMTime(seconds: Double(shutterSpeedSeconds), preferredTimescale: 1000)
    }

    // MARK: - Public Methods
    func startSession() async {
        cameraManager.startSession()
        isSessionActive = cameraManager.session.isRunning
    }

    func stopSession() {
        cameraManager.stopSession()
        isSessionActive = false
    }

    func updateExposure() {
        cameraManager.setManualExposure(iso: iso, shutterSpeed: shutterSpeedCMTime)
    }

    func capturePhoto() {
        cameraManager.capturePhoto()
    }
<<<<<<< HEAD
}
=======
}
>>>>>>> 2af109eadd0f4ede9e79cb861af0e964588ad74f
