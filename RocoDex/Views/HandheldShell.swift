import SwiftUI

enum DeckKey: Equatable {
    case digit(Int)
    case scan, up, down, left, right, search, cancel, backspace, clear, info
}

/// The compact surface can be driven externally when lookup or scanning completes.
struct HandheldShell<Left: View, Right: View>: View {
    private let scanning: Bool
    private let compactControls: Binding<Bool>?
    private let leftScreen: Left
    private let rightScreen: Right
    private let onKey: (DeckKey) -> Void
    @State private var localControls = false
    @State private var folded = false
    @State private var feedbackTick = 0

    init(
        compactControls: Binding<Bool>? = nil,
        scanning: Bool = false,
        @ViewBuilder leftScreen: () -> Left,
        @ViewBuilder rightScreen: () -> Right,
        onKey: @escaping (DeckKey) -> Void
    ) {
        self.scanning = scanning
        self.compactControls = compactControls
        self.leftScreen = leftScreen()
        self.rightScreen = rightScreen()
        self.onKey = onKey
    }

    private var showingControls: Bool { compactControls?.wrappedValue ?? localControls }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            // A narrow split view gets the same working surface as the outer display.
            let wide = !folded && (size.width >= 610 || (size.width > size.height * 1.3 && size.width >= 545))
            // The outer camera sits at the top of one side. Keep the header controls
            // inside its safe area, but allow the rest of the case to fill the glass.
            let cover = !wide && size.height > size.width
            let safe = proxy.safeAreaInsets
            let headerInsets = cover ? safe : EdgeInsets()
            ZStack {
                DeckPalette.edge.ignoresSafeArea()
                HStack(spacing: 0) {
                    if wide || !showingControls {
                        panel(isRight: false, compact: !wide, headerInsets: headerInsets, homeInset: safe.bottom)
                    }
                    if wide {
                        DeckHinge()
                            .frame(width: min(24, size.width * 0.029))
                            .accessibilityHidden(true)
                    }
                    if wide || showingControls {
                        panel(isRight: true, compact: !wide, headerInsets: headerInsets, homeInset: safe.bottom)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: wide ? 17 : 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: wide ? 17 : 22, style: .continuous)
                        .strokeBorder(.black.opacity(0.55), lineWidth: 1.5)
                        .allowsHitTesting(false)
                }
                .padding(wide ? 3 : 2)
            }
            .ignoresSafeArea(.container, edges: cover ? [.horizontal, .bottom] : .bottom)
        }
        .background {
            if #available(iOS 27.1, *) {
                DeckFoldObserver(folded: $folded).allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .sensoryFeedback(.selection, trigger: feedbackTick)
    }

    private func trigger(_ key: DeckKey) {
        feedbackTick &+= 1
        onKey(key)
    }

    private func changePanel() {
        let next = !showingControls
        if let compactControls {
            compactControls.wrappedValue = next
        } else {
            localControls = next
        }
        feedbackTick &+= 1
    }

    private func panel(isRight: Bool, compact: Bool, headerInsets: EdgeInsets, homeInset: CGFloat) -> some View {
        GeometryReader { geometry in
            let size = geometry.size
            let short = size.height < 370
            let headerFraction: CGFloat = short ? 0.175 : 0.195
            let w = size.width
            let h = size.height
            // Size both leaves, their screens, and the hinge against the whole case.
            // Only the lowest touch targets need to stop above the Home gesture area.
            let touchFloor = h - max(5, homeInset)
            let horizontalPadding = max(12, w * 0.064)
            let contentWidth = w - horizontalPadding * 2
            ZStack(alignment: .topLeading) {
                DeckRedPanel(isRight: isRight)
                    .accessibilityHidden(true)
                header(isRight: isRight, compact: compact, size: size, height: h * headerFraction, insets: headerInsets)
                if isRight {
                    let usableHeight = h * (1 - headerFraction)
                    let headerEnd = h * headerFraction
                    let screenHeight = usableHeight * (compact ? 0.39 : 0.31)
                    let keypadHeight = usableHeight * (compact ? 0.26 : 0.28)
                    let gap = max(4, min(13, usableHeight * 0.027))
                    let functionHeight = usableHeight * (compact ? 0.10 : 0.125)
                    let actionHeight = usableHeight * (compact ? 0.115 : 0.14)
                    let keyboardStart = headerEnd + screenHeight + gap
                    let functionStart = keyboardStart + keypadHeight + gap
                    rightScreen
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(DeckPalette.lcd)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay {
                            RoundedRectangle(cornerRadius: 5).strokeBorder(.black.opacity(0.7), lineWidth: 1.5)
                                .allowsHitTesting(false)
                        }
                        .padding(2)
                        .background(.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 7))
                        .deckFrame(x: horizontalPadding, y: headerEnd, w: contentWidth, h: screenHeight)
                    keypad
                        .deckFrame(x: horizontalPadding, y: keyboardStart, w: contentWidth, h: keypadHeight)
                    functions(compact: compact)
                        .deckFrame(x: horizontalPadding, y: functionStart, w: contentWidth, h: functionHeight)
                    HStack(spacing: max(8, w * 0.035)) {
                        rectButton("查找", label: "按编号查找", key: .search, color: .green)
                        rectButton("取消", label: "取消当前操作", key: .cancel, color: .green)
                    }
                    .deckFrame(x: horizontalPadding, y: min(touchFloor - actionHeight, functionStart + functionHeight + gap), w: contentWidth, h: actionHeight)
                } else {
                    let top = h * headerFraction
                    let screenHeight = h * (compact ? 0.505 : 0.506)
                    let padSize = min(w * 0.305, h * (short ? 0.26 : 0.20))
                    let preferredControlY = top + screenHeight + (h - top - screenHeight) * 0.55
                    let controlY = min(preferredControlY, touchFloor - padSize * 0.61)
                    screenBezel(screenHeight: screenHeight, panelWidth: w)
                        .deckFrame(x: w * 0.064, y: top, w: w * 0.865, h: screenHeight)
                    DeckStatusLights()
                        .deckFrame(x: w * 0.088, y: controlY - padSize * 0.53, w: w * 0.385, h: max(8, min(19, padSize * 0.19)))
                    Button { trigger(.scan) } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "viewfinder")
                            Text("扫描")
                        }
                        .font(.system(size: max(13, min(20, w * 0.043)), weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.10, green: 0.22, blue: 0.045))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .buttonStyle(DeckKeyStyle(.scanner))
                    .accessibilityLabel("扫描精灵")
                    .deckFrame(x: w * 0.11, y: controlY - padSize * 0.12, w: w * 0.34, h: max(34, padSize * 0.50))
                    DeckDirectionPad(action: trigger)
                        .deckFrame(x: w * 0.715 - padSize/2, y: controlY - padSize/2, w: padSize, h: padSize)
                }
            }
            .frame(width: w, height: h)
        }
    }

    private func header(isRight: Bool, compact: Bool, size: CGSize, height: CGFloat, insets: EdgeInsets) -> some View {
        let unit = min(size.width * 0.14, height * 0.64)
        return HStack(alignment: .center, spacing: min(15, size.width * 0.035)) {
            if !isRight {
                DeckLens(scanning: scanning)
                    .frame(width: unit, height: unit)
                HStack(spacing: max(4, unit * 0.10)) {
                    ForEach([Color(red: 0.84, green: 0.07, blue: 0.12), .yellow, .green], id: \.self) { color in
                        Circle().fill(color.gradient)
                            .overlay { Circle().strokeBorder(.black.opacity(0.5), lineWidth: 1) }
                            .frame(width: max(6, unit * 0.15), height: max(6, unit * 0.15))
                    }
                }
                .offset(y: -unit * 0.23)
                Spacer(minLength: 0)
            } else {
                if !compact { Spacer(minLength: 0) }
                VStack(alignment: .trailing, spacing: 2) {
                    Text("洛克王国：世界")
                        .font(.system(size: min(23, max(14, size.width * 0.052)), weight: .heavy, design: .rounded))
                    Text("精  灵  图  鉴")
                        .font(.system(size: min(12, max(9, size.width * 0.028)), weight: .bold))
                }
                .foregroundStyle(Color(red: 0.29, green: 0.015, blue: 0.06))
                .shadow(color: .white.opacity(0.29), radius: 0.3, y: 1)
                if compact { Spacer(minLength: 0) }
            }
            if compact {
                Button(action: changePanel) {
                    Label(isRight ? "看档案" : "查编号", systemImage: isRight ? "book.closed" : "number")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(.black.opacity(0.28), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, max(size.width * 0.064, insets.leading))
        .padding(.trailing, max(size.width * 0.064, insets.trailing))
        .frame(width: size.width, height: height * 0.88)
    }

    private func screenBezel(screenHeight: CGFloat, panelWidth: CGFloat) -> some View {
        let side = min(15, panelWidth * 0.035)
        return VStack(spacing: 0) {
            HStack(spacing: 7) {
                pin(DeckPalette.edge)
                pin(DeckPalette.edge)
            }
            .frame(height: min(18, screenHeight * 0.063))
            leftScreen
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DeckPalette.lcd)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay {
                    RoundedRectangle(cornerRadius: 4).strokeBorder(.black.opacity(0.5), lineWidth: 1)
                        .allowsHitTesting(false)
                }
            HStack {
                Circle().fill(DeckPalette.red)
                    .overlay { Circle().strokeBorder(DeckPalette.edge.opacity(0.6)) }
                    .frame(width: min(11, side * 0.8), height: min(11, side * 0.8))
                Spacer()
                VStack(spacing: 2) {
                    ForEach(0..<3) { _ in
                        Capsule().fill(.black.opacity(0.58)).frame(width: max(16, side * 1.6), height: 1.3)
                    }
                }
            }
            .frame(height: min(23, screenHeight * 0.092))
            .padding(.horizontal, 2)
        }
        .padding(.horizontal, side)
        .background {
            DeckBezelShape()
                .fill(LinearGradient(colors: [Color(red: 1.00, green: 0.965, blue: 0.90), Color(red: 0.90, green: 0.84, blue: 0.79)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 2)
        }
        .overlay { DeckBezelShape().stroke(DeckPalette.edge.opacity(0.68), lineWidth: 1.3).allowsHitTesting(false) }
    }

    private func pin(_ c: Color) -> some View {
        Circle().fill(c).frame(width: 4, height: 4)
    }

    private var keypad: some View {
        VStack(spacing: 3) {
            ForEach(0..<2) { row in
                HStack(spacing: 3) {
                    ForEach(0..<5) { column in
                        let digit = (row * 5 + column + 1) % 10
                        rectButton(String(digit), label: "数字 " + String(digit), key: .digit(digit), color: .blue)
                    }
                }
            }
        }
    }

    private func functions(compact: Bool) -> some View {
        HStack(spacing: 5) {
            utilityButton("delete.left", label: "退一位", key: .backspace)
            utilityButton("xmark", label: "清空编号", key: .clear)
            Spacer(minLength: 8)
            if compact {
                Button { trigger(.scan) } label: {
                    Image(systemName: "viewfinder").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(DeckKeyStyle(.scanner))
                .accessibilityLabel("扫描精灵")
                .frame(maxWidth: 48)
            } else {
                HStack(spacing: 4) {
                    Capsule().fill(.black.opacity(0.55)).frame(width: 14, height: 3)
                    Capsule().fill(.black.opacity(0.55)).frame(width: 14, height: 3)
                }
                .accessibilityHidden(true)
            }
            Button { trigger(.info) } label: {
                Image(systemName: "info").font(.system(size: 15, weight: .bold))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(Color(red: 0.33, green: 0.17, blue: 0.0))
                    .background(Circle().fill(.yellow.gradient))
                    .overlay { Circle().strokeBorder(.black.opacity(0.8), lineWidth: 1.5) }
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("精灵资料")
        }
    }

    private func utilityButton(_ symbol: String, label: String, key: DeckKey) -> some View {
        Button { trigger(key) } label: {
            Image(systemName: symbol).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(DeckKeyStyle(.cream))
        .accessibilityLabel(label)
        .frame(maxWidth: 58)
    }

    private func rectButton(_ text: String, label: String, key: DeckKey, color: DeckButtonColor) -> some View {
        Button { trigger(key) } label: {
            Text(text)
                .font(.system(size: color == .blue ? 20 : 16, weight: color == .blue ? .semibold : .bold, design: .rounded))
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(DeckKeyStyle(color))
        .accessibilityLabel(label)
    }
}

private extension View {
    func deckFrame(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> some View {
        frame(width: max(1, w), height: max(1, h))
            .position(x: x + w/2, y: y + h/2)
    }
}

@available(iOS 27.1, *)
private struct DeckFoldObserver: UIViewRepresentable {
    @Binding var folded: Bool

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let state = $folded
        view.addInteraction(UIHingeInteraction { _, update in
            guard let status = update.hinge?.status, status != .unknown else { return }
            let closed = status == .closed
            if state.wrappedValue != closed { state.wrappedValue = closed }
        })
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {}
}
