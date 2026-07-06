import AVFoundation
import UIKit
import Combine

class CameraManager: NSObject, ObservableObject {
    @Published var session = AVCaptureSession()
    @Published var previewLayer: AVCaptureVideoPreviewLayer?
    @Published var isSessionConfigured = false

    private let photoOutput = AVCapturePhotoOutput()
    private var videoDeviceInput: AVCaptureDeviceInput?
    private let sessionQueue = DispatchQueue(label: "com.nikita.camera.sessionQueue")

    override init() {
        super.init()
        configureSession()
    }

    private func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                print("Ошибка: Камера не найдена.")
                self.session.commitConfiguration()
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: camera)
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                    self.videoDeviceInput = input
                } else {
                    self.session.commitConfiguration()
                    return
                }
            } catch {
                print("Ошибка добавления входа: \(error)")
                self.session.commitConfiguration()
                return
            }

            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)

                if #available(iOS 17.0, *) {
                    // Берём первый поддерживаемый размер (обычно 12MP) для совместимости с ручной экспозицией
                    self.photoOutput.maxPhotoDimensions = camera.activeFormat.supportedMaxPhotoDimensions.first ?? .zero
                }
            } else {
                self.session.commitConfiguration()
                return
            }

            self.session.commitConfiguration()

            DispatchQueue.main.async {
                let previewLayer = AVCaptureVideoPreviewLayer(session: self.session)
                previewLayer.videoGravity = .resizeAspectFill
                self.previewLayer = previewLayer
                self.isSessionConfigured = true
                self.startSession()
            }
        }
    }

    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            guard self.isSessionConfigured else { return }
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    // Ручные настройки ISO и выдержки
    func setManualExposure(iso: Float, shutterSpeed: CMTime) {
        guard let device = videoDeviceInput?.device else { return }
        do {
            try device.lockForConfiguration()
            let minISO = device.activeFormat.minISO
            let maxISO = device.activeFormat.maxISO
            let clampedISO = max(minISO, min(iso, maxISO))
            device.setExposureModeCustom(duration: shutterSpeed, iso: clampedISO, completionHandler: nil)
            device.unlockForConfiguration()
        } catch {
            print("Ошибка блокировки конфигурации: \(error)")
        }
    }

    func capturePhoto() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            let settings = AVCapturePhotoSettings()
            // Приоритет скорости позволяет применять ручные ISO и выдержку
            settings.photoQualityPrioritization = .speed

            if #available(iOS 17.0, *) {
                settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
            }

            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate
extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("Ошибка обработки кадра: \(error)")
            return
        }
        guard let imageData = photo.fileDataRepresentation(),
              let uiImage = UIImage(data: imageData) else {
            print("Не удалось сформировать UIImage")
            return
        }
        // Сохранение в галерею (для теста)
        UIImageWriteToSavedPhotosAlbum(uiImage, nil, nil, nil)
        print("Астро-снимок сохранён!")
    }
}