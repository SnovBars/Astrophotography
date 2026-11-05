import SwiftUI
import AVFoundation
import CoreMotion

struct CameraView: View {
    @EnvironmentObject var viewModel: AstrophotographyViewModel
    @Binding var appState: AppState
    @StateObject private var motionManager = CoreMotionManager()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraPreviewView(session: viewModel.cameraManager.session)
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
        }
        .onDisappear {
            motionManager.stopUpdates()
            viewModel.stopSession()
        }
        .onChange(of: viewModel.iso) { _, _ in viewModel.updateExposure() }
        .onChange(of: viewModel.shutterSpeedSeconds) { _, _ in viewModel.updateExposure() }
    }

    // MARK: - Overlay
    private var gridAndHorizonOverlay: some View {
        GeometryReader { geo in
            ZStack {
                Path { path in
                    let w = geo.size.width, h = geo.size.height
                    path.move(to: CGPoint(x: w / 3, y: 0))
                    path.addLine(to: CGPoint(x: w / 3, y: h))
                    path.move(to: CGPoint(x: 2 * w / 3, y: 0))
                    path.addLine(to: CGPoint(x: 2 * w / 3, y: h))
                    path.move(to: CGPoint(x: 0, y: h / 3))
                    path.addLine(to: CGPoint(x: w, y: h / 3))
                    path.move(to: CGPoint(x: 0, y: 2 * h / 3))
                    path.addLine(to: CGPoint(x: w, y: 2 * h / 3))
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

    // MARK: - Control Panel
    private var controlPanel: some View {
        VStack(spacing: 12) {
            HStack {
                controlSlider(
                    title: "ISO",
                    value: Binding(
                        get: { Double(viewModel.iso) },
                        set: { viewModel.iso = Float($0) }
                    ),
                    range: 16...800,
                    step: 1,
                    formatter: { String(format: "%.0f", $0) }
                )
                controlSlider(
                    title: "Shutter",
                    value: $viewModel.shutterSpeedSeconds,
                    range: 0.001...1.0,
                    step: 0.001,
                    formatter: { String(format: "%.3f s", $0) }
                )
            }

            Button {
                capture()
            } label: {
                Group {
                    if viewModel.isCapturing {
                        ProgressView().tint(.black)
                    } else {
                        Text("Capture")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .disabled(viewModel.isCapturing)
        }
        .buttonStyle(.bordered)
        .tint(.white)
    }

    private func capture() {
        Task {
            do {
                try await viewModel.capturePhoto()
            } catch {
                let message = (error as? CameraError)?.errorDescription ?? error.localizedDescription
                appState = .error(message)
            }
        }
    }

    // Только Double — без generic, без сюрпризов
    private func controlSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        formatter: @escaping (Double) -> String = { "\($0)" }
    ) -> some View {
        VStack {
            Text("\(title): \(formatter(value.wrappedValue))")
                .font(.caption)
            Slider(value: value, in: range, step: step)
                .tint(.white)
        }
    }
}

// MARK: - Camera Preview
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.attach(session)
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.attach(session)
    }
}

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    func attach(_ session: AVCaptureSession) {
        backgroundColor = .black
        if previewLayer.session !== session {
            previewLayer.session = session
        }
        previewLayer.videoGravity = .resizeAspectFill
    }
}