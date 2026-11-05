import SwiftUI

struct PreparingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.6)

            Text("Подготовка камеры...")
                .foregroundColor(.gray)
                .font(.body)
        }
    }
}