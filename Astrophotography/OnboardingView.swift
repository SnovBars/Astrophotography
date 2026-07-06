import SwiftUI

// Модель данных страницы
struct OnboardingPage: Identifiable {
    let id = UUID()
    let imageName: String
    let title: String
    let description: String
}

struct OnboardingView: View {
    let onOnboardingComplete: () -> Void

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            imageName: "star.fill",
            title: "Снимайте звезды",
            description: "Приложение создано для астрофотографии. Делайте снимки звездного неба в высоком качестве."
        ),
        OnboardingPage(
            imageName: "camera.viewfinder",
            title: "Полный контроль",
            description: "Ручные настройки ISO, выдержки, фокуса и баланса белого для идеального кадра."
        ),
        OnboardingPage(
            imageName: "timer",
            title: "Профессиональные режимы",
            description: "Используйте интервалометр, длинную выдержку и таймер для безупречных результатов."
        )
    ]

    @State private var currentPage = 0

    var body: some View {
        VStack {
            // Индикатор страниц
            HStack {
                ForEach(0..<pages.count, id: \.self) { index in
                    Circle()
                        .fill(currentPage == index ? Color.white : Color.gray)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 50)

            // Слайдер с контентом
            TabView(selection: $currentPage) {
                ForEach(0..<pages.count, id: \.self) { index in
                    OnboardingPageView(page: pages[index])
                        .tag(index)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))

            // Кнопка "Далее / Начать"
            Button(action: {
                if currentPage < pages.count - 1 {
                    withAnimation { currentPage += 1 }
                } else {
                    onOnboardingComplete()
                }
            }) {
                Text(currentPage == pages.count - 1 ? "Начать" : "Далее")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(10)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 50)
        }
        .background(Color.black.ignoresSafeArea())
    }
}

// Вспомогательный View для отдельной страницы
struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: page.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .foregroundColor(.yellow)
                .padding(.bottom, 20)

            Text(page.title)
                .font(.largeTitle)
                .bold()
                .foregroundColor(.white)

            Text(page.description)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.gray)
                .padding(.horizontal, 30)
        }
        .padding()
    }
}