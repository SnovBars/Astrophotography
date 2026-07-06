import SwiftUI
import AVFoundation
import CoreMotion

struct CameraView: View {
    @EnvironmentObject var viewModel: AstrophotographyViewModel
    @StateObject private var motionManager = CoreMotionManager()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraPreviewView(previewLayer: viewModel.cameraManager.previewLayer)
                .ignoresSafeArea()
                .overlay(alignment: .topLeading) { gridAndHorizonOverlay }

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
        .onAppear {
            motionManager.startUpdates()
            if !viewModel.isSessionActive {
                Task { await viewModel.startSession() }
            }
        }
        .onDisappear {
            motionManager.stopUpdates()
            viewModel.stopSession()
        }
        .onChange(of: viewModel.iso) { viewModel.updateExposure() }
        .onChange(of: viewModel.shutterSpeedSeconds) { viewModel.updateExposure() }
    }

    private var gridAndHorizonOverlay: some View {
        GeometryReader { geo in
            ZStack {
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
                controlSlider(title: "Shutter", value: $viewModel.shutterSpeedSeconds, range: 0.001...1.0, step: 0.001, formatter: { String(format: "%.3f s", $0) })
            }

            Button("Capture") {
                viewModel.capturePhoto()
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
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

// MARK: - Camera Preview (UIViewRepresentable)
struct CameraPreviewView: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer?

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.setPreviewLayer(previewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.setPreviewLayer(previewLayer)
    }
}

class PreviewUIView: UIView {
    private var currentLayer: AVCaptureVideoPreviewLayer?

    func setPreviewLayer(_ layer: AVCaptureVideoPreviewLayer?) {
        currentLayer?.removeFromSuperlayer()
        guard let layer = layer else { return }
        layer.frame = bounds
        layer.videoGravity = .resizeAspectFill
        self.layer.addSublayer(layer)
        currentLayer = layer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        currentLayer?.frame = bounds
    }
}