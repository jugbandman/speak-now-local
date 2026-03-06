import SwiftUI

struct ElvisMicShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midX = rect.midX

        // Shure 55-style: wide spherical grille head, tapered body, short handle

        // Grille head - wide circle/sphere shape (top 40%)
        let headDiameter: CGFloat = rect.width * 0.85
        let headRadius = headDiameter / 2
        let headCenterY = rect.minY + headRadius
        path.addEllipse(in: CGRect(
            x: midX - headRadius,
            y: rect.minY,
            width: headDiameter,
            height: headDiameter
        ))

        // Body - tapers from head width down to handle width (middle 30%)
        let bodyTop = headCenterY + headRadius * 0.7
        let bodyBottom = rect.minY + rect.height * 0.7
        let bodyTopWidth = headDiameter * 0.6
        let bodyBottomWidth = headDiameter * 0.28

        path.move(to: CGPoint(x: midX - bodyTopWidth / 2, y: bodyTop))
        path.addLine(to: CGPoint(x: midX - bodyBottomWidth / 2, y: bodyBottom))
        path.addLine(to: CGPoint(x: midX + bodyBottomWidth / 2, y: bodyBottom))
        path.addLine(to: CGPoint(x: midX + bodyTopWidth / 2, y: bodyTop))
        path.closeSubpath()

        // Handle - narrow cylinder (bottom 30%)
        let handleTop = bodyBottom
        let handleWidth = bodyBottomWidth
        let handleHeight = rect.height * 0.28
        let handleRect = CGRect(
            x: midX - handleWidth / 2,
            y: handleTop,
            width: handleWidth,
            height: handleHeight
        )
        path.addRoundedRect(in: handleRect, cornerSize: CGSize(width: 3, height: 3))

        return path
    }
}

struct ElvisMicGrille: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midX = rect.midX
        let headDiameter = rect.width * 0.85
        let headRadius = headDiameter / 2
        let headCenterX = midX
        let headCenterY = rect.minY + headRadius

        // Horizontal grille lines across the sphere
        let lineCount = 7
        for i in 1...lineCount {
            let fraction = CGFloat(i) / CGFloat(lineCount + 1)
            let y = rect.minY + headDiameter * fraction
            let dy = y - headCenterY
            let halfChord = sqrt(max(0, headRadius * headRadius - dy * dy))
            let inset: CGFloat = 6
            if halfChord > inset {
                path.move(to: CGPoint(x: headCenterX - halfChord + inset, y: y))
                path.addLine(to: CGPoint(x: headCenterX + halfChord - inset, y: y))
            }
        }

        // Vertical grille lines across the sphere
        let vLineCount = 5
        for i in 1...vLineCount {
            let fraction = CGFloat(i) / CGFloat(vLineCount + 1)
            let x = rect.minY + headDiameter * fraction + (midX - headRadius)
            let dx = x - headCenterX
            let halfChord = sqrt(max(0, headRadius * headRadius - dx * dx))
            let inset: CGFloat = 6
            if halfChord > inset {
                path.move(to: CGPoint(x: x, y: headCenterY - halfChord + inset))
                path.addLine(to: CGPoint(x: x, y: headCenterY + halfChord - inset))
            }
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
            // Glow behind mic head
            Circle()
                .fill(glowColor.opacity(Double(audioLevel) * 0.5))
                .frame(width: width * 0.85, height: width * 0.85)
                .blur(radius: 10 + CGFloat(audioLevel) * 10)
                .offset(y: -(height * 0.15))

            // Mic body with metallic gradient
            ElvisMicShape()
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.82), Color(white: 0.55), Color(white: 0.72), Color(white: 0.58)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            // Grille mesh
            ElvisMicGrille()
                .stroke(Color(white: 0.45), lineWidth: 0.7)

            // Outline
            ElvisMicShape()
                .stroke(Color(white: 0.35), lineWidth: 1.5)
        }
        .frame(width: width, height: height)
        .scaleEffect(1.0 + CGFloat(audioLevel) * 0.04)
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
            let intensity = CGFloat(audioLevel) * 1.5
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
