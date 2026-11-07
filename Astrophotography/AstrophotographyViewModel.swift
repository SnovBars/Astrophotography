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
    @Published var previewLayer: AVCaptureVideoPreviewLayer?
    @Published var isSessionRunning: Bool = false
    
    // Для серийной съемки
    @Published var burstCount: Double = 10
    @Published var isBursting: Bool = false
    @Published var burstProgress: Int = 0

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
            .sink { [weak self] layer in self?.previewLayer = layer }
            .store(in: &cancellables)

        cameraManager.$isSessionRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] running in self?.isSessionRunning = running }
            .store(in: &cancellables)
    }

    // MARK: - Camera lifecycle
    func prepareCamera() async throws {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        guard granted else {
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            if status == .restricted {
                throw CameraError.permissionRestricted
            }
            throw CameraError.permissionDenied
        }

        let photoStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if photoStatus == .notDetermined {
            _ = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
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

    // MARK: - Burst Capture (Серийная съемка в RAW)
    func startBurstCapture() async {
        guard !isBursting else { return }
        isBursting = true
        burstProgress = 0
        
        let totalShots = Int(burstCount)
        
        for i in 1...totalShots {
            do {
                // 1. Делаем снимок (получаем сырые данные DNG)
                let rawData = try await cameraManager.capturePhoto()
                
                // 2. Сохраняем в папку Documents
                try saveRawToDocuments(rawData, index: i)
                
                burstProgress = i
                
                // 3. Небольшая пауза, чтобы сенсор "остыл" и не завис
                try await Task.sleep(nanoseconds: 300_000_000)
                
            } catch {
                print("Ошибка при серии: \(error)")
                break
            }
        }
        
        isBursting = false
    }

    private func saveRawToDocuments(_ data: Data, index: Int) throws {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = String(format: "astro_%03d.dng", index)
        let fileURL = documentsURL.appendingPathComponent(fileName)
        try data.write(to: fileURL)
        print("Сохранено: \(fileName)")
    }
}