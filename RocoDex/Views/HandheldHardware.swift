import SwiftUI

enum DeckPalette {
    static let red = Color(red: 0.83, green: 0.054, blue: 0.13)
    static let edge = Color(red: 0.17, green: 0.018, blue: 0.035)
    static let lcd = Color(red: 0.055, green: 0.082, blue: 0.076)
}

struct DeckRedPanel: View {
    let isRight: Bool

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.96, green: 0.10, blue: 0.17),
                             DeckPalette.red, Color(red: 0.72, green: 0.035, blue: 0.105)],
                    startPoint: isRight ? .topTrailing : .topLeading, endPoint: .bottom
                )
                Path { path in
                    let low = h * 0.167
                    let high = h * 0.110
                    if isRight {
                        path.move(to: CGPoint(x: 0, y: high))
                        path.addLine(to: CGPoint(x: w * 0.26, y: high))
                        path.addLine(to: CGPoint(x: w * 0.38, y: low))
                        path.addLine(to: CGPoint(x: w, y: low))
                    } else {
                        path.move(to: CGPoint(x: 0, y: low))
                        path.addLine(to: CGPoint(x: w * 0.47, y: low))
                        path.addLine(to: CGPoint(x: w * 0.60, y: high))
                        path.addLine(to: CGPoint(x: w, y: high))
                    }
                }
                .stroke(DeckPalette.edge.opacity(0.47), style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
                .shadow(color: .white.opacity(0.23), radius: 0.2, y: 1.5)
                RoundedRectangle(cornerRadius: 5)
                    .inset(by: 1.8)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
        }
    }
}

struct DeckLens: View {
    let scanning: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { proxy in
            let d = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle().fill(DeckPalette.edge)
                Circle().inset(by: d * 0.028)
                    .fill(LinearGradient(colors: [.white, .gray, .white], startPoint: .topLeading, endPoint: .bottomTrailing))
                Circle().inset(by: d * 0.096)
                    .fill(RadialGradient(colors: [Color(red: 0.40, green: 0.95, blue: 1.0),
                                                  Color(red: 0, green: 0.59, blue: 0.96),
                                                  Color(red: 0.015, green: 0.17, blue: 0.48)],
                                         center: UnitPoint(x: 0.31, y: 0.24),
                                         startRadius: d * 0.02, endRadius: d * 0.70))
                if scanning {
                    Circle().inset(by: d * 0.10).fill(.cyan.opacity(0.35))
                        .phaseAnimator([false,true]) { light, on in
                            light.opacity(reduceMotion || on ? 1 : 0.18)
                                .shadow(color:.cyan.opacity(0.85), radius: on ? 8 : 2)
                        } animation: { _ in .easeInOut(duration:0.6) }
                }
                Ellipse().fill(.white.opacity(0.84))
                    .frame(width: d * 0.21, height: d * 0.13)
                    .rotationEffect(.degrees(-38))
                    .offset(x: -d * 0.13, y: -d * 0.18)
            }
            .shadow(color: .black.opacity(0.45), radius: 1, y: 2)
        }
        .accessibilityHidden(true)
    }
}

struct DeckStatusLights: View {
    var body: some View {
        HStack(spacing: 9) {
            Circle().fill(Color(red: 0.025, green: 0.14, blue: 0.11))
                .overlay { Circle().strokeBorder(.black.opacity(0.7)) }
                .aspectRatio(1, contentMode: .fit)
            Capsule().fill(Color(red: 0.49, green: 0.03, blue: 0.09)).frame(height: 3)
            Capsule().fill(Color(red: 0.12, green: 0.47, blue: 0.63)).frame(height: 3.5)
        }
        .accessibilityHidden(true)
    }
}

struct DeckHinge: View {
    var body: some View {
        GeometryReader { proxy in
            let h = proxy.size.height
            let band = LinearGradient(
                stops: [
                    .init(color: DeckPalette.edge, location: 0),
                    .init(color: DeckPalette.red, location: 0.17),
                    .init(color: Color(red: 0.97, green: 0.14, blue: 0.21), location: 0.32),
                    .init(color: Color(red: 0.71, green: 0.036, blue: 0.105), location: 0.77),
                    .init(color: DeckPalette.edge, location: 1)
                ], startPoint: .leading, endPoint: .trailing
            )
            VStack(spacing: 1.6) {
                RoundedRectangle(cornerRadius: 3).fill(band).frame(height: h * 0.10)
                RoundedRectangle(cornerRadius: 3).fill(band)
                RoundedRectangle(cornerRadius: 3).fill(band).frame(height: h * 0.095)
            }
            .background(DeckPalette.edge)
        }
    }
}

struct DeckBezelShape: Shape {
    func path(in r: CGRect) -> Path {
        let s: CGFloat = 8
        let cut = min(r.height * 0.054, r.width * 0.064)
        var p = Path()
        p.move(to: CGPoint(x: s, y: 0))
        p.addLine(to: CGPoint(x: r.maxX - s, y: 0))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: s), control: CGPoint(x: r.maxX, y: 0))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - s))
        p.addQuadCurve(to: CGPoint(x: r.maxX - s, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: cut, y: r.maxY))
        p.addLine(to: CGPoint(x: 0, y: r.maxY - cut))
        p.addLine(to: CGPoint(x: 0, y: s))
        p.addQuadCurve(to: CGPoint(x: s, y: 0), control: .zero)
        p.closeSubpath()
        return p
    }
}

enum DeckButtonColor {
    case blue, green, cream, scanner

    var top: Color {
        switch self {
        case .blue: Color(red: 0.48, green: 0.81, blue: 1.0)
        case .green: Color(red: 0.12, green: 0.50, blue: 0.27)
        case .cream: Color(red: 1.0, green: 0.96, blue: 0.88)
        case .scanner: Color(red: 0.69, green: 0.95, blue: 0.22)
        }
    }

    var bottom: Color {
        switch self {
        case .blue: Color(red: 0.22, green: 0.56, blue: 0.86)
        case .green: Color(red: 0.068, green: 0.37, blue: 0.21)
        case .cream: Color(red: 0.84, green: 0.78, blue: 0.73)
        case .scanner: Color(red: 0.42, green: 0.73, blue: 0.11)
        }
    }

    var label: Color {
        switch self {
        case .blue: Color(red: 0.045, green: 0.12, blue: 0.23)
        case .green: .white
        case .cream, .scanner: Color(red: 0.16, green: 0.16, blue: 0.14)
        }
    }
}

struct DeckKeyStyle: ButtonStyle {
    let color: DeckButtonColor
    init(_ color: DeckButtonColor) { self.color = color }

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        configuration.label
            .foregroundStyle(color.label)
            .background {
                shape.fill(LinearGradient(colors: [color.top, color.bottom], startPoint: .top, endPoint: .bottom))
            }
            .overlay {
                shape.inset(by: 1.6)
                    .strokeBorder(.white.opacity(configuration.isPressed ? 0.1 : 0.33), lineWidth: 0.9)
            }
            .overlay { shape.strokeBorder(.black.opacity(0.85), lineWidth: 1.4) }
            .shadow(color: .black.opacity(configuration.isPressed ? 0.12 : 0.48), radius: 0.5, y: configuration.isPressed ? 0 : 2)
            .brightness(configuration.isPressed ? -0.055 : 0)
            .offset(y: configuration.isPressed ? 1 : 0)
            .contentShape(Rectangle())
    }
}

struct DeckDirectionPad: View {
    let action: (DeckKey) -> Void

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                DPadOutline()
                    .fill(LinearGradient(colors: [Color(red: 0.15, green: 0.18, blue: 0.17),
                                                  Color(red: 0.055, green: 0.076, blue: 0.067)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay { DPadOutline().stroke(Color.black.opacity(0.95), lineWidth: 2.0) }
                    .shadow(color: .black.opacity(0.56), radius: 1.2, y: 2)
                Circle()
                    .fill(.black.opacity(0.17))
                    .overlay { Circle().strokeBorder(.white.opacity(0.07)) }
                    .frame(width: side * 0.21, height: side * 0.21)
                // Each quadrant uses the entire corner of the pad as a touch target.
                arrow(.up, icon: "arrowtriangle.up.fill", label: "向上", point: CGPoint(x: 0.5, y: 0.14), side: side)
                arrow(.down, icon: "arrowtriangle.down.fill", label: "向下", point: CGPoint(x: 0.5, y: 0.86), side: side)
                arrow(.left, icon: "arrowtriangle.left.fill", label: "向左", point: CGPoint(x: 0.14, y: 0.5), side: side)
                arrow(.right, icon: "arrowtriangle.right.fill", label: "向右", point: CGPoint(x: 0.86, y: 0.5), side: side)
            }
            .frame(width: side, height: side)
            .accessibilityElement(children: .contain)
        }
    }

    private func arrow(_ key: DeckKey, icon: String, label: String, point: CGPoint, side: CGFloat) -> some View {
        let fullTarget = max(30, min(50, side * 0.47))
        return Button { action(key) } label: {
            Image(systemName: icon)
                .font(.system(size: min(10, side * 0.09), weight: .semibold))
                .foregroundStyle(Color(red: 0.43, green: 0.47, blue: 0.43))
                .frame(width: fullTarget, height: fullTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .position(x: point.x * side, y: point.y * side)
    }
}

private struct DPadOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let unitPoints: [CGPoint] = [
            .init(x: 0.34, y: 0), .init(x: 0.66, y: 0), .init(x: 0.66, y: 0.34),
            .init(x: 1, y: 0.34), .init(x: 1, y: 0.66), .init(x: 0.66, y: 0.66),
            .init(x: 0.66, y: 1), .init(x: 0.34, y: 1), .init(x: 0.34, y: 0.66),
            .init(x: 0, y: 0.66), .init(x: 0, y: 0.34), .init(x: 0.34, y: 0.34)
        ]
        let vertices = unitPoints.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) }
        // Small corner fillets preserve the molded shape at all display sizes.
        let radius = min(rect.width, rect.height) * 0.033
        var path = Path()
        path.move(to: CGPoint(x: (vertices[0].x + vertices.last!.x) / 2,
                              y: (vertices[0].y + vertices.last!.y) / 2))
        for i in vertices.indices {
            path.addArc(tangent1End: vertices[i], tangent2End: vertices[(i + 1) % vertices.count], radius: radius)
        }
        path.closeSubpath()
        return path
    }
}
