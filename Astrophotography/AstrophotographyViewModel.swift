// AstrophotographyViewModel.swift
import SwiftUI
import Combine

@MainActor
final class AstrophotographyViewModel: ObservableObject {
    @Published var isSessionActive = false
    @Published var iso: Float = 32 { didSet { cameraManager.setISO(iso) } }
    @Published var shutterSpeed: Double = 0.1 { didSet { cameraManager.setExposureDuration(seconds: shutterSpeed) } }
    @Published var focus: Float = 0.5 { didSet { cameraManager.setFocus(lensPosition: focus) } }
    @Published var whiteBalanceKelvin: Float = 5000 { didSet { cameraManager.setWhiteBalance(tempKelvin: whiteBalanceKelvin) } }
    @Published var intervalShots: Int = 10
    @Published var intervalDelay: Double = 2.0
    @Published var shutterDelaySeconds: Double = 2 { didSet { shutterDelay = shutterDelaySeconds } }
    @Published var isLongExposureActive = false
    @Published var longExposureDuration: Double = 60
    
    private let cameraManager = CameraManager()
    private var cancellables = Set<AnyCancellable>()
    private var shutterDelay: Double = 2
    
    init() {
        bindCameraUpdates()
    }
    
    private func bindCameraUpdates() {
        cameraManager.$currentISO.assign(to: &$iso)
        cameraManager.$currentExposureDuration
            .map { $0.seconds }
            .assign(to: &$shutterSpeed)
        cameraManager.$currentLensPosition.assign(to: &$focus)
    }
    
    func startSession() async {
        let success = await cameraManager.setupSession()
        if success {
            cameraManager.startSession()
            isSessionActive = true
        }
    }
    
    func stopSession() { cameraManager.stopSession(); isSessionActive = false }
    
    func captureWithDelay() {
        Task {
            try? await Task.sleep(nanoseconds: UInt64(shutterDelay * 1_000_000_000))
            cameraManager.capturePhoto { data in
                self.savePhoto(data)
            }
        }
    }
    
    func startLongExposure() {
        isLongExposureActive = true
        cameraManager.startLongExposure(totalDuration: longExposureDuration) { data in
            Task { @MainActor in
                self.savePhoto(data)
                self.isLongExposureActive = false
            }
        }
    }
    
    func startIntervalometer() {
        cameraManager.startIntervalometer(shots: intervalShots, delayBetween: intervalDelay) { data in
            self.savePhoto(data)
        }
    }
    
    private func savePhoto(_ data: Data?) {
        guard let data = data else { return }
        let filename = UUID().uuidString + (data.isTIFF ? ".tiff" : ".dng")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? data.write(to: url)
        print("Photo saved: \(url)")
    }
}

extension Data {
    var isTIFF: Bool { self.starts(with: [0x49, 0x49, 0x2A, 0x00]) || self.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) }
}