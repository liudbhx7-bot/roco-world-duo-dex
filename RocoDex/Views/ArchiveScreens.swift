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

struct PortraitLCD: View {
    let spirit: Spirit
    let catalog: Catalog
    let page: ArchivePage
    let found: Bool
    let select: (Int) -> Void
    let openDetails: () -> Void
    let openForms: () -> Void
    let animationURL: URL?
    let isNarrating: Bool
    let toggleNarration: () -> Void
    @AppStorage("prefersAnimatedPortraits") private var animationPreference: Bool?
    @State private var failedAnimation: URL?
    @State private var evolutionRoute = 0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var prefersAnimation: Bool { animationPreference ?? !reduceMotion }

    var body: some View {
        GeometryReader { g in
            let short = g.size.height < 143
            let pad: CGFloat = short ? 6 : 10
            VStack(alignment: .leading, spacing: short ? 3 : 6) {
                HStack {
                    Text("NO. " + spirit.number).font(.system(size: short ? 10 : 12, weight: .bold, design: .monospaced))
                    let forms = catalog.forms(for: spirit)
                    if forms.count > 1 {
                        Button(action: openForms) {
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
                            Text(spirit.type + "系").font(.system(size: short ? 10 : 12,weight:.bold))
                                .padding(.horizontal,6).padding(.vertical,2)
                                .foregroundStyle(.white).background(spirit.ink, in: Capsule())
                            Button(action: openDetails) {
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
                case .skills:
                    ScrollView {
                        VStack(alignment:.leading,spacing:4) {
                            if spirit.skills.isEmpty { Text("尚无技能记录") }
                            ForEach(Array(spirit.skills.enumerated()),id:\.offset) { i, skill in
                                HStack { Text(String(format:"%02d",i+1)).foregroundStyle(spirit.ink); Text(skill); Spacer() }
                                    .padding(.bottom,2).overlay(alignment:.bottom) { Divider() }
                            }
                        }.font(.system(size: short ? 11 : 13,weight:.medium))
                    }
                case .family:
                    let routes = spirit.evolutionPaths ?? []
                    let routeIndex = routes.indices.contains(evolutionRoute) ? evolutionRoute : 0
                    let members = routes.isEmpty ? spirit.evolution : routes[routeIndex]
                    if routes.count > 1 {
                        Menu {
                            ForEach(routes.indices,id:\.self) { index in
                                Button {
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
            Button { select(id) } label: {
                VStack(spacing:2) {
                    if let image = catalog.pictures.thumbnail(id) {
                        Image(uiImage:image).resizable().scaledToFit().frame(maxHeight:.infinity)
                    }
                    Text(one.formattedName).font(.caption.bold()).lineLimit(2).minimumScaleFactor(0.7)
                }.frame(maxWidth:.infinity)
                .foregroundStyle(id == spirit.id ? spirit.ink : Color.primary)
                .padding(2).background(id == spirit.id ? spirit.ink.opacity(0.12) : .clear, in:RoundedRectangle(cornerRadius:4))
            }.buttonStyle(.plain)
        }
    }

    private func portrait(_ art: UIImage, short: Bool) -> some View {
        let availableURL = animationURL == failedAnimation ? nil : animationURL
        return ZStack {
            if prefersAnimation, let url = availableURL {
                SpriteAnimationViewport(url: url, name: spirit.name, placeholder: art, active: scenePhase == .active) {
                    failedAnimation = url
                }
                .id(url)
            } else {
                Image(uiImage: art).resizable().scaledToFit()
                    .accessibilityLabel(spirit.name + "立绘")
                    .accessibilityIdentifier("staticPortrait")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .overlay(alignment: .bottomTrailing) {
            if availableURL != nil {
                Button { animationPreference = !prefersAnimation } label: {
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

struct StatusLCD: View {
    let spirit: Spirit
    let headline: String?
    let message: String
    private let colors: [Color] = [.green,.orange,.yellow,.cyan,.mint,.purple]
    var body: some View {
        GeometryReader { g in
            let compact = g.size.height < 89
            VStack(alignment:.leading,spacing:compact ? 2 : 5) {
                if let headline {
                    Text(headline).font(.system(size:compact ? 14 : 18,weight:.bold,design:.monospaced))
                    Text(message).font(.system(size:compact ? 10 : 12)).lineLimit(3).minimumScaleFactor(0.72)
                } else {
                    HStack {
                        Text(spirit.name).font(.system(size:compact ? 12 : 15,weight:.bold))
                        Spacer()
                        Text("总值 " + String(spirit.stats.reduce(0,+))).font(.system(size:compact ? 10 : 12,weight:.bold,design:.monospaced))
                    }
                    ForEach(0..<3,id:\.self) { row in
                        HStack(spacing:9) {
                            ForEach([row,row+3],id:\.self) { i in
                                HStack(spacing:3) {
                                    Text(Spirit.statNames[i]).lineLimit(1).fixedSize()
                                    GeometryReader { b in
                                        ZStack(alignment:.leading) {
                                            Capsule().fill(.white.opacity(0.13))
                                            Capsule().fill(colors[i]).frame(width:b.size.width * min(1,CGFloat(spirit.stats[i])/165))
                                        }
                                    }.frame(height:3)
                                    Text(String(spirit.stats[i]))
                                        .monospacedDigit()
                                        .lineLimit(1)
                                        .fixedSize()
                                        .frame(minWidth: compact ? 21 : 25, alignment: .trailing)
                                }.frame(maxWidth:.infinity)
                            }
                        }.font(.system(size:compact ? 9 : 11,weight:.semibold,design:.rounded))
                    }
                }
            }
            .padding(.horizontal,8).padding(.vertical,compact ? 3 : 6)
            .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.leading)
            .foregroundStyle(Color(red:0.85,green:0.95,blue:0.83))
            .background(Color(red:0.055,green:0.105,blue:0.09))
        }
    }
}
