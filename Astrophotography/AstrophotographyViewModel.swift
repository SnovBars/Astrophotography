import SwiftUI
import AVFoundation
import Photos
import Combine

@MainActor
final class AstrophotographyViewModel: ObservableObject {
    // MARK: - Published
    @Published var iso: Float = 32.0
    @Published var shutterSpeedSeconds: Double = 0.1
    @Published var focus: Float = 0.5
    @Published var whiteBalanceKelvin: Float = 5000
    @Published var isCapturing: Bool = false
    @Published var previewLayer: AVCaptureVideoPreviewLayer?
    @Published var isSessionRunning: Bool = false

    // MARK: - Dependencies
    private(set) var cameraManager = CameraManager()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed
    var shutterSpeedCMTime: CMTime {
        CMTime(seconds: shutterSpeedSeconds, preferredTimescale: 1000)
    }

    init() {
        cameraManager.$previewLayer
            .receive(on: DispatchQueue.main)
            .sink { [weak self] layer in
                self?.previewLayer = layer
            }
            .store(in: &cancellables)

        cameraManager.$isSessionRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] running in
                self?.isSessionRunning = running
            }
            .store(in: &cancellables)
    }

    // MARK: - Camera lifecycle
    func prepareCamera() async throws {
        let granted = await CameraManager.requestCameraPermission()
        guard granted else {
            let status = CameraManager.currentCameraPermission()
            if status == .restricted {
                throw CameraError.permissionRestricted
            }
            throw CameraError.permissionDenied
        }

        if cameraManager.isSessionConfigured {
            await cameraManager.startSession()
        } else {
            try await cameraManager.configureSession()
            await cameraManager.startSession()
        }

        cameraManager.setManualExposure(iso: iso, shutterSpeed: shutterSpeedCMTime)
    }

    func stopSession() {
        cameraManager.stopSession()
    }

    // MARK: - Exposure
    func updateExposure() {
        cameraManager.setManualExposure(iso: iso, shutterSpeed: shutterSpeedCMTime)
    }

    // MARK: - Capture
    func capturePhoto() async throws {
        guard !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }

        let image = try await cameraManager.capturePhoto()
        try await saveToPhotoLibrary(image)
    }

    // MARK: - Save
    private func saveToPhotoLibrary(_ image: UIImage) async throws {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        let granted: Bool

        switch currentStatus {
        case .authorized, .limited:
            granted = true
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            granted = (newStatus == .authorized || newStatus == .limited)
        default:
            granted = false
        }

        guard granted else {
            throw CameraError.saveFailed(
                "Нет доступа к Фото. Разрешите сохранение снимков в Настройках iPhone."
            )
        }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }
}