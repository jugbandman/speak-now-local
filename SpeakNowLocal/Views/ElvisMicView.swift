import SwiftUI

struct ElvisMicShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midX = rect.midX

        // Mic head - large rounded capsule
        let headWidth: CGFloat = rect.width * 0.7
        let headHeight: CGFloat = rect.height * 0.5
        let headRect = CGRect(
            x: midX - headWidth / 2,
            y: rect.minY,
            width: headWidth,
            height: headHeight
        )
        let headCorner = headWidth / 2
        let bottomCorner = headWidth / 4
        path.addRoundedRect(
            in: headRect,
            cornerRadii: RectangleCornerRadii(
                topLeading: headCorner,
                bottomLeading: bottomCorner,
                bottomTrailing: bottomCorner,
                topTrailing: headCorner
            )
        )

        // Neck - tapered connector
        let neckTop = headRect.maxY
        let neckWidth: CGFloat = headWidth * 0.3
        let neckHeight: CGFloat = rect.height * 0.12
        path.addRect(CGRect(x: midX - neckWidth / 2, y: neckTop, width: neckWidth, height: neckHeight))

        // Handle - slightly wider cylinder
        let handleTop = neckTop + neckHeight
        let handleWidth: CGFloat = headWidth * 0.25
        let handleHeight: CGFloat = rect.height * 0.35
        path.addRoundedRect(
            in: CGRect(x: midX - handleWidth / 2, y: handleTop, width: handleWidth, height: handleHeight),
            cornerSize: CGSize(width: 4, height: 4)
        )

        return path
    }
}

struct ElvisMicGrille: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let headWidth = rect.width * 0.7
        let headHeight = rect.height * 0.5
        let midX = rect.midX
        let lineCount = 8

        for i in 1..<lineCount {
            let y = rect.minY + headHeight * CGFloat(i) / CGFloat(lineCount)
            let progress = CGFloat(i) / CGFloat(lineCount)
            let widthAtY: CGFloat
            if progress < 0.3 {
                widthAtY = headWidth * (progress / 0.3)
            } else if progress > 0.8 {
                widthAtY = headWidth * ((1 - progress) / 0.2)
            } else {
                widthAtY = headWidth
            }
            path.move(to: CGPoint(x: midX - widthAtY / 2 + 4, y: y))
            path.addLine(to: CGPoint(x: midX + widthAtY / 2 - 4, y: y))
        }
        return path
    }
}

struct ElvisMicView: View {
    let audioLevel: Float
    var width: CGFloat = 80
    var height: CGFloat = 120
    @AppStorage(Constants.keyTheme) private var appTheme = Constants.defaultTheme
    @State private var shakeOffset: CGSize = .zero
    @State private var shakeTimer: Timer?

    var body: some View {
        ZStack {
            // Glow behind mic
            ElvisMicShape()
                .fill(glowColor.opacity(Double(audioLevel) * 0.6))
                .blur(radius: 12 + CGFloat(audioLevel) * 8)

            // Mic body with metallic gradient
            ElvisMicShape()
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.85), Color(white: 0.6), Color(white: 0.75)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(
                    ElvisMicGrille()
                        .stroke(Color(white: 0.5), lineWidth: 0.5)
                )

            // Mic outline
            ElvisMicShape()
                .stroke(Color(white: 0.4), lineWidth: 1.5)
        }
        .frame(width: width, height: height)
        .scaleEffect(1.0 + CGFloat(audioLevel) * 0.05)
        .offset(shakeOffset)
        .onAppear { startShakeTimer() }
        .onDisappear { stopShakeTimer() }
        .animation(.easeInOut(duration: 0.08), value: shakeOffset)
    }

    private var glowColor: Color {
        appTheme == "taylors" ? .purple : .red
    }

    private func startShakeTimer() {
        shakeTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            let intensity = CGFloat(audioLevel) * 2
            DispatchQueue.main.async {
                shakeOffset = CGSize(
                    width: CGFloat.random(in: -intensity...intensity),
                    height: CGFloat.random(in: -intensity...intensity)
                )
            }
        }
    }

    private func stopShakeTimer() {
        shakeTimer?.invalidate()
        shakeTimer = nil
    }
}
