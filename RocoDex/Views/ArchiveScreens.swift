import SwiftUI

extension Spirit {
    var ink: Color {
        let primary = type.components(separatedBy: CharacterSet(charactersIn: "·・/、 +／")).first ?? type
        switch primary {
        case "水": return Color(red: 0.06, green: 0.37, blue: 0.52)
        case "草": return Color(red: 0.19, green: 0.38, blue: 0.16)
        case "火", "武": return Color(red: 0.60, green: 0.21, blue: 0.12)
        case "电", "光", "地": return Color(red: 0.45, green: 0.32, blue: 0.07)
        case "冰", "翼": return Color(red: 0.09, green: 0.39, blue: 0.42)
        case "幻", "毒", "幽", "龙": return Color(red: 0.37, green: 0.23, blue: 0.46)
        case "萌": return Color(red: 0.52, green: 0.22, blue: 0.37)
        case "虫": return Color(red: 0.30, green: 0.37, blue: 0.11)
        default: return Color(red: 0.25, green: 0.29, blue: 0.32)
        }
    }
}

struct DisplayGrid: View {
    var body: some View {
        Canvas { context, size in
            var grid = Path()
            for x in stride(from: 0.0, to: size.width, by: 14) {
                grid.move(to: CGPoint(x:x,y:0)); grid.addLine(to: CGPoint(x:x,y:size.height))
            }
            for y in stride(from: 0.0, to: size.height, by: 14) {
                grid.move(to: CGPoint(x:0,y:y)); grid.addLine(to: CGPoint(x:size.width,y:y))
            }
            context.stroke(grid, with: .color(.black.opacity(0.045)), lineWidth: 0.6)
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

// Keep the current selection's manual choice when moving between pages or folding Duo.
@Observable final class PortraitPlayback {
    var animationPreference: Bool?
    var didStartEntry = false
    var failed = false
}

struct PortraitLCD: View {
    let spirit: Spirit
    let catalog: Catalog
    let page: ArchivePage
    let found: Bool
    let select: (Int) -> Void
    let openDetails: () -> Void
    let openForms: () -> Void
    let animation: SpiritAnimation?
    let playback: PortraitPlayback
    let isNarrating: Bool
    let toggleNarration: () -> Void
    @State private var evolutionRoute = 0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var prefersAnimation: Bool { playback.animationPreference ?? !reduceMotion }

    var body: some View {
        GeometryReader { g in
            let short = g.size.height < 143
            let pad: CGFloat = short ? 6 : 10
            VStack(alignment: .leading, spacing: short ? 3 : 6) {
                HStack {
                    Text("NO. " + spirit.number).font(.system(size: short ? 10 : 12, weight: .bold, design: .monospaced))
                    let forms = catalog.forms(for: spirit)
                    if forms.count > 1 {
                        Button(feedback: .key, action: openForms) {
                            HStack(spacing: 2) { Text("\(forms.count) 个形态"); Image(systemName:"chevron.down") }
                                .padding(.horizontal,5).padding(.vertical,2)
                                .background(spirit.ink.opacity(0.11), in: Capsule())
                        }.buttonStyle(.plain).accessibilityIdentifier("chooseForm")
                    }
                    Spacer()
                    Image(systemName: found ? "checkmark.circle.fill" : "book.closed")
                    Text(found ? "已发现" : "资料库")
                }
                .font(.system(size: short ? 9 : 10,weight:.semibold)).foregroundStyle(spirit.ink)
                switch page {
                case .profile:
                    HStack(spacing: 6) {
                        if let art = catalog.pictures[spirit.id] {
                            portrait(art, short: short)
                        }
                        VStack(alignment: .leading, spacing: short ? 3 : 6) {
                            Text(spirit.name).font(.system(size: short ? 17 : 23,weight:.heavy))
                                .minimumScaleFactor(0.65).lineLimit(1)
                            if let form = spirit.distinctForm {
                                Text(form).font(.system(size:short ? 9 : 11, weight:.medium)).foregroundStyle(spirit.ink)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                            }
                            GameTypeIcons(types: spirit.type, size: short ? 16 : 21)
                            Button(feedback: .key, action: openDetails) {
                                HStack(spacing: 2) { Text(spirit.trait); Image(systemName: "chevron.right") }
                            }
                            .font(.system(size: short ? 10 : 12,weight:.medium)).buttonStyle(.plain)
                            .accessibilityLabel("查看特性和完整档案")
                            Button(action: toggleNarration) {
                                Label(isNarrating ? "停止介绍" : "播放介绍",
                                      systemImage: isNarrating ? "stop.fill" : "speaker.wave.2.fill")
                                    .font(.system(size: short ? 10 : 12, weight: .semibold))
                                    .lineLimit(1).minimumScaleFactor(0.8)
                                    .padding(.horizontal, short ? 4 : 7).padding(.vertical, short ? 2 : 5)
                                    .foregroundStyle(spirit.ink)
                                    .background(spirit.ink.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("portraitNarration")
                        }
                        .frame(width: max(55, g.size.width * 0.35),alignment:.leading)
                    }
                    if g.size.height > 175 {
                        Text(spirit.summary).lineLimit(g.size.height > 230 ? 3 : 2)
                            .font(.system(size:12)).fixedSize(horizontal:false,vertical:true)
                    }
                case .family:
                    let routes = spirit.evolutionPaths ?? []
                    let routeIndex = routes.indices.contains(evolutionRoute) ? evolutionRoute : 0
                    let members = routes.isEmpty ? spirit.evolution : routes[routeIndex]
                    if routes.count > 1 {
                        Menu {
                            ForEach(routes.indices,id:\.self) { index in
                                Button(feedback: .page) {
                                    evolutionRoute = index
                                } label: {
                                    let names = routes[index].compactMap { id in
                                        catalog.entries.first(where: { $0.id == id })?.formattedName
                                    }
                                    Text(names.joined(separator:" → "))
                                }
                            }
                        } label: {
                            Label("进化路线 \(routeIndex + 1) / \(routes.count)", systemImage:"arrow.triangle.branch")
                                .font(.caption.bold()).foregroundStyle(spirit.ink)
                        }
                    }
                    if members.count > 3 {
                        ScrollView(.horizontal) {
                            HStack(spacing:2) {
                                ForEach(members,id:\.self) { id in
                                    familyMember(id).frame(width: (g.size.width - 2 * pad) / 3.3)
                                }
                            }
                        }
                    } else if members.isEmpty {
                        Text("尚无进化记录").font(.caption)
                    } else {
                        HStack(spacing:2) {
                            ForEach(members,id:\.self) { id in familyMember(id) }
                        }
                    }
                case .habitat:
                    HabitatInfoPanel(spirit: spirit)
                }
                Spacer(minLength:0)
                HStack {
                    Text(page.title)
                    Spacer()
                    ForEach(ArchivePage.allCases,id:\.rawValue) { p in
                        Capsule().fill(p == page ? spirit.ink : spirit.ink.opacity(0.25)).frame(width:p == page ? 15 : 5,height:3)
                    }
                }.font(.system(size:9,weight:.semibold)).foregroundStyle(spirit.ink)
            }
            .padding(pad)
            .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
            .foregroundStyle(Color(red:0.07,green:0.15,blue:0.15))
            .background {
                ZStack {
                    LinearGradient(colors:[Color(red:0.93,green:0.95,blue:0.89),Color(red:0.80,green:0.86,blue:0.77)],startPoint:.topLeading,endPoint:.bottomTrailing)
                    DisplayGrid()
                }
            }
        }.environment(\.colorScheme,.light)
            .onChange(of:spirit.id) { _, _ in evolutionRoute = 0 }
    }

    @ViewBuilder private func familyMember(_ id: Int) -> some View {
        if let one = catalog.entries.first(where: { $0.id == id }) {
            Button(feedback: .page) { select(id) } label: {
                VStack(spacing:2) {
                    if let image = catalog.pictures[id] {
                        Image(uiImage:image).resizable().interpolation(.high).scaledToFit().frame(maxWidth:.infinity,maxHeight:.infinity)
                    }
                    Text(one.formattedName).font(.caption.bold()).lineLimit(2).minimumScaleFactor(0.7)
                }.frame(maxWidth:.infinity)
                .foregroundStyle(id == spirit.id ? spirit.ink : Color.primary)
                .padding(2).background(id == spirit.id ? spirit.ink.opacity(0.12) : .clear, in:RoundedRectangle(cornerRadius:4))
            }.buttonStyle(.plain)
        }
    }

    private func portrait(_ art: UIImage, short: Bool) -> some View {
        let available = playback.failed ? nil : animation
        return ZStack {
            if prefersAnimation, let available {
                SpriteAnimationViewport(animation: available, playback: playback, name: spirit.formattedName,
                                        placeholder: art, active: scenePhase == .active)
                    .id(ObjectIdentifier(playback))
            } else {
                Image(uiImage: art).resizable().scaledToFit()
                    .accessibilityLabel(spirit.name + "立绘")
                    .accessibilityIdentifier("staticPortrait")
            }
        }
        .padding(.vertical, 3)
        .modifier(PortraitFloat(enabled: !reduceMotion && scenePhase == .active))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .overlay(alignment: .bottomTrailing) {
            if available != nil {
                Button(feedback: .key) {
                    playback.didStartEntry = false
                    playback.animationPreference = !prefersAnimation
                } label: {
                    Label(prefersAnimation ? "看静图" : "看动图",
                          systemImage: prefersAnimation ? "photo" : "play.rectangle")
                        .font(.system(size: short ? 9 : 11, weight: .bold, design: .rounded))
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .foregroundStyle(.white).background(spirit.ink, in: Capsule())
                        .padding(.leading, 6).padding(.top, 5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(prefersAnimation ? "切换为静图" : "切换为动图")
                .accessibilityValue(prefersAnimation ? "动图" : "静图")
                .accessibilityIdentifier("portraitMediaToggle")
            }
        }
    }
}

private struct PortraitFloat: ViewModifier {
    let enabled: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if enabled {
            content.phaseAnimator([false, true]) { media, rising in
                media.offset(y: rising ? -2.5 : 2.5)
            } animation: { _ in .easeInOut(duration: 1.65) }
        } else {
            content
        }
    }
}

struct StatusLCD: View {
    let headline: String?
    let message: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(headline ?? "图鉴编号", systemImage: "number")
                .font(.headline.monospacedDigit())
            Text(message.isEmpty ? "输入编号后按查找，或直接按查找浏览名册。" : message)
                .font(.callout)
        }
        .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .foregroundStyle(Color(red: 0.85, green: 0.95, blue: 0.83))
        .background(Color(red: 0.055, green: 0.105, blue: 0.09))
    }
}
