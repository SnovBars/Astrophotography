import SwiftUI
import AVFoundation

enum AppState: Equatable {
    case onboarding
    case greeting
    case preparing
    case camera
    case error(String)
}

@main
struct AstroCameraApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @StateObject private var viewModel = AstrophotographyViewModel()
    @State private var appState: AppState
    @State private var isPreparingCamera = false

    init() {
        let completed = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        if !completed {
            _appState = State(initialValue: .onboarding)
        } else if status == .authorized {
            _appState = State(initialValue: .preparing)
        } else {
            _appState = State(initialValue: .greeting)
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                Color.black.ignoresSafeArea()

                switch appState {
                case .onboarding:
                    OnboardingView {
                        hasCompletedOnboarding = true
                        appState = .greeting
                    }

                case .greeting:
                    GreetingView {
                        Task { await prepareCamera() }
                    }

                case .preparing:
                    PreparingView()

                case .camera:
                    CameraView(appState: $appState)
                        .environmentObject(viewModel)

                case .error(let message):
                    ErrorView(message: message) {
                        Task { await prepareCamera() }
                    }
                }
            }
            .preferredColorScheme(.dark)
            .animation(.easeInOut(duration: 0.25), value: appState)
            .task {
                if appState == .preparing {
                    await prepareCamera()
                }
            }
        }
    }

    @MainActor
    private func prepareCamera() async {
        guard !isPreparingCamera else { return }
        isPreparingCamera = true
        defer { isPreparingCamera = false }

        withAnimation { appState = .preparing }

        do {
            try await viewModel.prepareCamera()
            withAnimation { appState = .camera }
        } catch {
            let message = (error as? CameraError)?.errorDescription ?? error.localizedDescription
            viewModel.stopSession()
            withAnimation { appState = .error(message) }
        }
    }
}