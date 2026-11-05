import SwiftUI

struct GreetingView: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("🌌")
                .font(.system(size: 90))

            Text("AstroPhoto Camera")
                .font(.largeTitle).bold()
                .foregroundColor(.white)

            Text("Приложение для съёмки ночного неба и звёздных треков в ручном режиме.")
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            Button(action: onStart) {
                Text("Начать работу")
                    .bold()
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }
}