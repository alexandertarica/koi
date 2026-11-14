import SwiftUI

struct KoiBackground: View {
    var isDoingScreen = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(red: 0x4C / 255, green: 0x66 / 255, blue: 0x88 / 255)
                Image("KoiBackground")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .blur(radius: 5.5)
                    .contrast(1.2)
                    .saturation(1.12)
                    .brightness(-0.045)
                KoiTheme.deepWater.opacity(0.33)
                if isDoingScreen {
                    LinearGradient(colors: [.clear, KoiTheme.deepWater.opacity(0.3), KoiTheme.deepWater.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom)
                }
            }
            .ignoresSafeArea()
        }
        .accessibilityHidden(true)
    }
}
