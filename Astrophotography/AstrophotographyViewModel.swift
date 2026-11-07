import SwiftUI
import AVFoundation
import Photos
import Combine

@MainActor
final class AstrophotographyViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var iso: Float = 32.0
    @Published var shutterSpeedSeconds: Double = 0.1
    @Published var previewLayer: AVCaptureVideoPreviewLayer?
    @Published var isSessionRunning: Bool = false
    
    @Published var burstCount: Double = 10
    @Published var isBursting: Bool = false
    @Published var burstProgress: Int = 0
    
    // ✅ Новая переменная для названия сессии
    @Published var sessionName: String = ""

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

    func updateExposure() {
        cameraManager.setManualExposure(iso: iso, shutterSpeed: shutterSpeedCMTime)
    }

    // MARK: - Burst Capture (с созданием папки)
    func startBurstCapture() async {
        guard !isBursting else { return }
        isBursting = true
        burstProgress = 0
        
        // ✅ Определяем имя папки: либо введённое, либо дата/время
        let trimmedName = sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let folderName: String
        
        if trimmedName.isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            folderName = "Session_\(formatter.string(from: Date()))"
        } else {
            // Очищаем от недопустимых символов
            let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
            folderName = trimmedName.components(separatedBy: invalidCharacters).joined(separator: "_")
        }
        
        let totalShots = Int(burstCount)
        
        for i in 1...totalShots {
            do {
                let rawData = try await cameraManager.capturePhoto()
                // ✅ Передаём имя папки в функцию сохранения
                try saveRawToDocuments(rawData, index: i, folderName: folderName)
                burstProgress = i
                try await Task.sleep(nanoseconds: 300_000_000)
            } catch {
                print("Ошибка при серии: \(error)")
                break
            }
        }
        isBursting = false
    }

    // ✅ Обновлённая функция сохранения (создаёт папку)
    private func saveRawToDocuments(_ data: Data, index: Int, folderName: String) throws {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folderURL = documentsURL.appendingPathComponent(folderName, isDirectory: true)
        
        // Создаём папку, если её ещё нет (согласно документации Apple)
        // withIntermediateDirectories: true создаёт все промежуточные папки, если нужно
        if !FileManager.default.fileExists(atPath: folderURL.path) {
            try FileManager.default.createDirectory(
                at: folderURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
        
        let fileName = String(format: "astro_%03d.dng", index)
        let fileURL = folderURL.appendingPathComponent(fileName)
        try data.write(to: fileURL)
        print("Сохранено: \(folderName)/\(fileName)")
    }
}