// CameraManager.swift
import AVFoundation
import CoreImage
import UIKit
import Combine

@MainActor
final class CameraManager: NSObject, ObservableObject {
    @Published var isSessionRunning = false
    @Published var currentISO: Float = 0
    @Published var currentExposureDuration: CMTime = .zero
    @Published var currentLensPosition: Float = 0
    @Published var currentWhiteBalanceGains: AVCaptureDevice.WhiteBalanceGains = .init()
    
    // теперь internal (доступен из CameraView)
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var device: AVCaptureDevice?
    
    // Хранилище активных делегатов (исправление зависаний)
    private var activeDelegates: [Int64: any AVCapturePhotoCaptureDelegate] = [:]
    
    // MARK: - Setup
    func setupSession() async -> Bool {
        guard await AVCaptureDevice.requestAccess(for: .video) else { return false }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else { return false }
        if session.canAddInput(input) { session.addInput(input) }
        
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        
        // Настройка максимального разрешения (48MP) через maxPhotoDimensions
        // Используем availablePhotoDimensions для выбора максимального
        if let maxDim = photoOutput.availablePhotoDimensions.max(by: { $0.width < $1.width }) {
            photoOutput.maxPhotoDimensions = maxDim
        }
        
        device = camera
        try? device?.lockForConfiguration()
        // Выбираем формат с максимальным разрешением
        if let maxDim = photoOutput.maxPhotoDimensions as CMVideoDimensions? {
            let desiredFormat = device?.formats.first { format in
                let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                return dims.width == maxDim.width && dims.height == maxDim.height
            }
            device?.activeFormat = desiredFormat ?? device?.activeFormat
        }
        device?.unlockForConfiguration()
        
        updateManualControlRanges()
        session.sessionPreset = .photo
        return true
    }
    
    func startSession() {
        // Запуск в фоне без конфликтов с @MainActor
        Task.detached { [weak self] in
            self?.session.startRunning()
        }
    }
    
    func stopSession() {
        session.stopRunning()
    }
    
    // MARK: - Manual Controls
    func setISO(_ iso: Float) {
        guard let device = device, device.isExposureModeSupported(.custom) else { return }
        try? device.lockForConfiguration()
        device.setExposureModeCustom(duration: device.exposureDuration, iso: iso) { _ in }
        device.unlockForConfiguration()
        currentISO = iso
    }
    
    func setExposureDuration(seconds: Double) {
        guard let device = device, device.isExposureModeSupported(.custom) else { return }
        let duration = CMTime(seconds: seconds, preferredTimescale: 1000)
        try? device.lockForConfiguration()
        device.setExposureModeCustom(duration: duration, iso: device.iso) { _ in }
        device.unlockForConfiguration()
        currentExposureDuration = duration
    }
    
    func setFocus(lensPosition: Float) {
        guard let device = device, device.isLockingFocusWithCustomLensPositionSupported else { return }
        try? device.lockForConfiguration()
        device.setFocusModeLocked(lensPosition: lensPosition) { _ in }
        device.unlockForConfiguration()
        currentLensPosition = lensPosition
    }
    
    func setInfinityFocus() { setFocus(lensPosition: 1.0) }
    
    func setWhiteBalance(tempKelvin: Float) {
        guard let device = device else { return }
        let tempAndTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: tempKelvin, tint: 0)
        let gains = device.deviceWhiteBalanceGains(for: tempAndTint)
        try? device.lockForConfiguration()
        device.setWhiteBalanceModeLocked(with: gains)
        device.unlockForConfiguration()
        currentWhiteBalanceGains = gains
    }
    
    private func updateManualControlRanges() {
        guard let device = device else { return }
        currentISO = device.iso
        currentExposureDuration = device.exposureDuration
        currentLensPosition = device.lensPosition
        currentWhiteBalanceGains = device.deviceWhiteBalanceGains
    }
    
    // MARK: - Capture (Single Photo)
    func capturePhoto(completion: @escaping (Data?) -> Void) {
        var settings = AVCapturePhotoSettings()
        if let maxDim = photoOutput.maxPhotoDimensions as CMVideoDimensions? {
            settings.maxPhotoDimensions = maxDim
            settings.photoQualityPrioritization = .quality
        }
        // Если доступен RAW, используем его
        if let rawFormat = photoOutput.availableRawPhotoPixelFormatTypes.first {
            settings = AVCapturePhotoSettings(rawPixelFormatType: rawFormat)
            if let maxDim = photoOutput.maxPhotoDimensions as CMVideoDimensions? {
                settings.maxPhotoDimensions = maxDim
            }
        } else {
            settings = AVCapturePhotoSettings(format: [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoCompressionPropertiesKey: [AVVideoQualityKey: 1.0]
            ])
            if let maxDim = photoOutput.maxPhotoDimensions as CMVideoDimensions? {
                settings.maxPhotoDimensions = maxDim
            }
            settings.photoQualityPrioritization = .quality
        }
        
        let delegate = PhotoCaptureDelegate(manager: self, uniqueID: settings.uniqueID, completion: completion)
        activeDelegates[settings.uniqueID] = delegate
        photoOutput.capturePhoto(with: settings, delegate: delegate)
    }
    
    // MARK: - Long Exposure (исправлена логика, делегаты сохраняются)
    func startLongExposure(totalDuration: Double, completion: @escaping (Data?) -> Void) {
        guard let device = device else { completion(nil); return }
        let maxFrameDuration = device.activeFormat.maxExposureDuration
        let frameSeconds = maxFrameDuration.seconds
        let requiredFrames = Int(totalDuration / frameSeconds)
        guard requiredFrames > 0 else { completion(nil); return }
        
        Task {
            var accumulatedImage: CIImage?
            var framesCaptured = 0
            
            for _ in 0..<requiredFrames {
                let image = await captureSingleRawFrame()
                guard let ciImage = image else { continue }
                
                if let accumulated = accumulatedImage {
                    let filter = CIFilter(name: "CIAdditionCompositing")
                    filter?.setValue(accumulated, forKey: kCIInputImageKey)
                    filter?.setValue(ciImage, forKey: kCIInputBackgroundImageKey)
                    accumulatedImage = filter?.outputImage
                } else {
                    accumulatedImage = ciImage
                }
                framesCaptured += 1
            }
            
            guard framesCaptured > 0, let accumulated = accumulatedImage else {
                completion(nil)
                return
            }
            
            let scale = 1.0 / Float(framesCaptured)
            let scaleFilter = CIFilter(name: "CIColorMatrix")
            scaleFilter?.setValue(accumulated, forKey: kCIInputImageKey)
            scaleFilter?.setValue(CIVector(x: CGFloat(scale), y: 0, z: 0, w: 0), forKey: "inputRVector")
            scaleFilter?.setValue(CIVector(x: 0, y: CGFloat(scale), z: 0, w: 0), forKey: "inputGVector")
            scaleFilter?.setValue(CIVector(x: 0, y: 0, z: CGFloat(scale), w: 0), forKey: "inputBVector")
            scaleFilter?.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
            guard let averaged = scaleFilter?.outputImage else {
                completion(nil)
                return
            }
            
            let context = CIContext()
            // Исправлен порядок аргументов: colorSpace, format
            let tiffData = context.tiffRepresentation(of: averaged,
                                                       colorSpace: CGColorSpace(name: CGColorSpace.linearGray) ?? CGColorSpaceCreateDeviceRGB(),
                                                       format: .RGBA16)
            completion(tiffData)
        }
    }
    
    private func captureSingleRawFrame() async -> CIImage? {
        await withCheckedContinuation { continuation in
            var settings = AVCapturePhotoSettings()
            if let rawFormat = photoOutput.availableRawPhotoPixelFormatTypes.first {
                settings = AVCapturePhotoSettings(rawPixelFormatType: rawFormat)
            } else {
                settings = AVCapturePhotoSettings()
            }
            if let maxDim = photoOutput.maxPhotoDimensions as CMVideoDimensions? {
                settings.maxPhotoDimensions = maxDim
            }
            
            let delegate = SingleFrameCaptureDelegate(manager: self, uniqueID: settings.uniqueID) { data in
                let ciImage = data.flatMap { CIImage(data: $0) }
                continuation.resume(returning: ciImage)
            }
            activeDelegates[settings.uniqueID] = delegate
            photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }
    
    // MARK: - Intervalometer
    func startIntervalometer(shots: Int, delayBetween: TimeInterval, photoHandler: @escaping (Data?) -> Void) {
        Task {
            for _ in 0..<shots {
                try? await Task.sleep(nanoseconds: UInt64(delayBetween * 1_000_000_000))
                await MainActor.run {
                    self.capturePhoto(completion: photoHandler)
                }
            }
        }
    }
    
    // MARK: - Управление делегатами
    fileprivate func removeDelegate(withID uniqueID: Int64) {
        activeDelegates.removeValue(forKey: uniqueID)
    }
}

// MARK: - Делегаты (исправлены, удаляют себя после завершения)
private class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private weak var manager: CameraManager?
    private let uniqueID: Int64
    private let completion: (Data?) -> Void
    
    init(manager: CameraManager, uniqueID: Int64, completion: @escaping (Data?) -> Void) {
        self.manager = manager
        self.uniqueID = uniqueID
        self.completion = completion
        super.init()
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        completion(data)
        Task { @MainActor in
            self.manager?.removeDelegate(withID: self.uniqueID)
        }
    }
}

private class SingleFrameCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private weak var manager: CameraManager?
    private let uniqueID: Int64
    private let completion: (Data?) -> Void
    
    init(manager: CameraManager, uniqueID: Int64, completion: @escaping (Data?) -> Void) {
        self.manager = manager
        self.uniqueID = uniqueID
        self.completion = completion
        super.init()
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        completion(data)
        Task { @MainActor in
            self.manager?.removeDelegate(withID: self.uniqueID)
        }
    }
}