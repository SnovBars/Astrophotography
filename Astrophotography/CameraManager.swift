import AVFoundation
import UIKit
import Combine

// MARK: - Errors
enum CameraError: LocalizedError {
    case permissionDenied
    case permissionRestricted
    case noCamera
    case cannotConfigureSession(String)
    case cannotAddInput
    case cannotAddOutput
    case sessionNotConfigured
    case captureFailed(String)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Доступ к камере отклонён."
        case .permissionRestricted: return "Доступ к камере ограничен."
        case .noCamera: return "Задняя камера не найдена."
        case .cannotConfigureSession(let msg): return "Ошибка настройки: \(msg)"
        case .cannotAddInput: return "Ошибка подключения входа."
        case .cannotAddOutput: return "Ошибка подключения выхода."
        case .sessionNotConfigured: return "Сессия не настроена."
        case .captureFailed(let msg): return "Ошибка съёмки: \(msg)"
        case .saveFailed(let msg): return "Ошибка сохранения: \(msg)"
        }
    }
}

final class CameraManager: NSObject, ObservableObject, @unchecked Sendable {
    @Published private(set) var session = AVCaptureSession()
    @Published private(set) var previewLayer: AVCaptureVideoPreviewLayer?
    @Published private(set) var isSessionConfigured = false
    @Published private(set) var isSessionRunning = false

    private let photoOutput = AVCapturePhotoOutput()
    private var videoDeviceInput: AVCaptureDeviceInput?
    private let sessionQueue = DispatchQueue(label: "com.nikita.camera.sessionQueue")

    private let continuationLock = NSLock()
    private var photoContinuation: CheckedContinuation<Data, Error>?

    // MARK: - Permission
    static func currentCameraPermission() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    static func requestCameraPermission() async -> Bool {
        switch currentCameraPermission() {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted: return false
        @unknown default: return false
        }
    }

    // MARK: - Configure
    func configureSession() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: CameraError.cannotConfigureSession("Manager deallocated"))
                    return
                }

                self.session.beginConfiguration()
                self.session.sessionPreset = .photo

                // Очистка предыдущей конфигурации
                for input in self.session.inputs { self.session.removeInput(input) }
                for output in self.session.outputs { self.session.removeOutput(output) }
                self.videoDeviceInput = nil

                guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                    self.session.commitConfiguration()
                    continuation.resume(throwing: CameraError.noCamera)
                    return
                }

                do {
                    let input = try AVCaptureDeviceInput(device: camera)
                    if self.session.canAddInput(input) {
                        self.session.addInput(input)
                        self.videoDeviceInput = input
                    } else {
                        self.session.commitConfiguration()
                        continuation.resume(throwing: CameraError.cannotAddInput)
                        return
                    }
                } catch {
                    self.session.commitConfiguration()
                    continuation.resume(throwing: CameraError.cannotConfigureSession(error.localizedDescription))
                    return
                }

                if self.session.canAddOutput(self.photoOutput) {
                    self.session.addOutput(self.photoOutput)

                    // ❌ УБРАНО: self.photoOutput.isRawCaptureEnabled = true
                    // ✅ Достаточно того, что мы добавляем photoOutput в сессию.
                    // Формат RAW будет выбран при создании AVCapturePhotoSettings в capturePhoto().

                    if #available(iOS 17.0, *) {
                        if let maxDim = camera.activeFormat.supportedMaxPhotoDimensions.first {
                            self.photoOutput.maxPhotoDimensions = maxDim
                        }
                    }
                } else {
                    self.session.commitConfiguration()
                    continuation.resume(throwing: CameraError.cannotAddOutput)
                    return
                }

                self.session.commitConfiguration()

                DispatchQueue.main.async {
                    let layer = AVCaptureVideoPreviewLayer(session: self.session)
                    layer.videoGravity = .resizeAspectFill
                    self.previewLayer = layer
                    self.isSessionConfigured = true
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Start / Stop
    func startSession() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    DispatchQueue.main.async { continuation.resume() }
                    return
                }
                if !self.session.isRunning {
                    self.session.startRunning()
                }
                let running = self.session.isRunning
                DispatchQueue.main.async {
                    self.isSessionRunning = running
                    continuation.resume()
                }
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            DispatchQueue.main.async {
                self.isSessionRunning = false
            }
        }
    }

    // MARK: - Exposure
    func setManualExposure(iso: Float, shutterSpeed: CMTime) {
        sessionQueue.async { [weak self] in
            guard let self = self, let device = self.videoDeviceInput?.device else { return }
            do {
                try device.lockForConfiguration()
                let minISO = device.activeFormat.minISO
                let maxISO = device.activeFormat.maxISO
                let clampedISO = max(minISO, min(iso, maxISO))
                let minDuration = device.activeFormat.minExposureDuration
                let maxDuration = device.activeFormat.maxExposureDuration
                let clampedDuration = CMTimeMaximum(minDuration, CMTimeMinimum(shutterSpeed, maxDuration))
                device.setExposureModeCustom(duration: clampedDuration, iso: clampedISO, completionHandler: nil)
                device.unlockForConfiguration()
            } catch {
                print("Exposure config error: \(error)")
            }
        }
    }

    // MARK: - Capture
    func capturePhoto() async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            continuationLock.lock()
            let alreadyCapturing = (photoContinuation != nil)
            if !alreadyCapturing { photoContinuation = continuation }
            continuationLock.unlock()

            if alreadyCapturing {
                continuation.resume(throwing: CameraError.captureFailed("Съёмка уже выполняется"))
                return
            }

            sessionQueue.async { [weak self] in
                guard let self = self else { return }
                guard self.isSessionConfigured else {
                    self.finishCapture(with: .failure(CameraError.sessionNotConfigured))
                    return
                }

                if let connection = self.photoOutput.connection(with: .video) {
                    connection.isEnabled = true
                }

                let settings: AVCapturePhotoSettings
                if let rawFormat = self.photoOutput.availableRawPhotoPixelFormatTypes.first {
                    settings = AVCapturePhotoSettings(rawPixelFormatType: rawFormat)
                } else {
                    settings = AVCapturePhotoSettings()
                }

                settings.photoQualityPrioritization = .quality
                if #available(iOS 17.0, *) {
                    settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
                }

                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    private func finishCapture(with result: Result<Data, Error>) {
        continuationLock.lock()
        let continuation = photoContinuation
        photoContinuation = nil
        continuationLock.unlock()

        continuation?.resume(with: result)
    }
}

// MARK: - AVCapturePhotoCaptureDelegate
extension CameraManager: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            finishCapture(with: .failure(CameraError.captureFailed(error.localizedDescription)))
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            finishCapture(with: .failure(CameraError.captureFailed("Не удалось сформировать файл")))
            return
        }
        finishCapture(with: .success(data))
    }
}