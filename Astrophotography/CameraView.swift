// CameraView.swift
import SwiftUI
import AVFoundation
import CoreMotion   // <-- явно добавлен для горизонта (хотя используется через менеджер)

struct CameraView: View {
    @StateObject private var viewModel = AstrophotographyViewModel()
    @StateObject private var motionManager = CoreMotionManager()
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            CameraPreviewView()
                .ignoresSafeArea()
                .overlay(alignment: .topLeading) { gridAndHorizonOverlay }
                .environmentObject(viewModel)
                .environmentObject(motionManager)
            
            VStack {
                Spacer()
                controlPanel
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                    .padding(.horizontal)
            }
        }
        .preferredColorScheme(.dark)
        .task { await viewModel.startSession() }
        .onDisappear { viewModel.stopSession(); motionManager.stopUpdates() }
        .onAppear { motionManager.startUpdates() }
    }
    
    private var gridAndHorizonOverlay: some View {
        GeometryReader { geo in
            ZStack {
                // Rule-of-thirds grid
                Path { path in
                    let w = geo.size.width, h = geo.size.height
                    path.move(to: CGPoint(x: w/3, y: 0))
                    path.addLine(to: CGPoint(x: w/3, y: h))
                    path.move(to: CGPoint(x: 2*w/3, y: 0))
                    path.addLine(to: CGPoint(x: 2*w/3, y: h))
                    path.move(to: CGPoint(x: 0, y: h/3))
                    path.addLine(to: CGPoint(x: w, y: h/3))
                    path.move(to: CGPoint(x: 0, y: 2*h/3))
                    path.addLine(to: CGPoint(x: w, y: 2*h/3))
                }
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                
                // Horizon level
                VStack {
                    Text("⏤ \(Int(motionManager.roll))° ⏤")
                        .font(.caption)
                        .foregroundColor(abs(motionManager.roll) < 1 ? .green : .red)
                        .padding(4)
                        .background(.black.opacity(0.6))
                        .cornerRadius(6)
                    Spacer()
                }
                .padding(.top, 50)
            }
        }
    }
    
    private var controlPanel: some View {
        VStack(spacing: 12) {
            HStack {
                controlSlider(title: "ISO", value: $viewModel.iso, range: 16...800, step: 1)
                controlSlider(title: "Shutter", value: $viewModel.shutterSpeed, range: 0.001...1, step: 0.001, formatter: { String(format: "%.3f s", $0) })
            }
            HStack {
                controlSlider(title: "Focus", value: $viewModel.focus, range: 0...1, step: 0.01)
                Button("♾️") { viewModel.focus = 1.0 }
                    .buttonStyle(.borderedProminent)
            }
            controlSlider(title: "WB (K)", value: $viewModel.whiteBalanceKelvin, range: 2000...8000, step: 50, formatter: { "\(Int($0)) K" })
            
            HStack {
                Button("2s") { viewModel.shutterDelaySeconds = 2 }
                Button("5s") { viewModel.shutterDelaySeconds = 5 }
                Button("Capture") { viewModel.captureWithDelay() }
                    .buttonStyle(.borderedProminent)
            }
            
            HStack {
                VStack {
                    Text("Intervalometer")
                    HStack {
                        Stepper("Shots: \(viewModel.intervalShots)", value: $viewModel.intervalShots, in: 1...999)
                        Stepper("Delay: \(viewModel.intervalDelay, specifier: "%.1f")s", value: $viewModel.intervalDelay, in: 1...60, step: 0.5)
                    }
                    Button("Start Interval") { viewModel.startIntervalometer() }
                }
                Divider().frame(height: 40)
                VStack {
                    Text("Long Exposure")
                    Stepper("\(viewModel.longExposureDuration, specifier: "%.0f") s", value: $viewModel.longExposureDuration, in: 30...300, step: 10)
                    Button(viewModel.isLongExposureActive ? "Processing..." : "Start LE") {
                        viewModel.startLongExposure()
                    }
                    .disabled(viewModel.isLongExposureActive)
                }
            }
            .font(.caption)
        }
        .buttonStyle(.bordered)
        .tint(.white)
    }
    
    private func controlSlider(title: String, value: Binding<Float>, range: ClosedRange<Float>, step: Float, formatter: @escaping (Float) -> String = { "\($0)" }) -> some View {
        VStack {
            Text("\(title): \(formatter(value.wrappedValue))")
                .font(.caption)
            Slider(value: value, in: range, step: step)
                .tint(.white)
        }
    }
}

// MARK: - UIViewRepresentable for Camera Preview
struct CameraPreviewView: UIViewRepresentable {
    @EnvironmentObject var viewModel: AstrophotographyViewModel
    
    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.setSession(viewModel.cameraManager?.session)
        return view
    }
    
    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
}

extension AstrophotographyViewModel {
    fileprivate var cameraManager: CameraManager? {
        Mirror(reflecting: self).descendant("cameraManager") as? CameraManager
    }
}

class PreviewUIView: UIView {
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    func setSession(_ session: AVCaptureSession?) {
        previewLayer?.removeFromSuperlayer()
        guard let session = session else { return }
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = bounds
        layer.connection?.videoRotationAngle = 0
        self.layer.addSublayer(layer)
        previewLayer = layer
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}