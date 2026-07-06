import SwiftUI

@main
struct AstrophotographyApp: App {
    @AppStorage("hasLaunchedBefore") private var hasLaunchedBefore: Bool = false
    @StateObject private var viewModel = AstrophotographyViewModel()

    var body: some Scene {
        WindowGroup {
            ZStack {
                if hasLaunchedBefore {
                    CameraView()
                        .environmentObject(viewModel)
                        .task {
                            await viewModel.startSession()
                        }
                } else {
                    OnboardingView(onOnboardingComplete: {
                        withAnimation {
                            hasLaunchedBefore = true
                        }
                    })
                }
            }
            .background(Color.black.ignoresSafeArea())
        }
    }
}