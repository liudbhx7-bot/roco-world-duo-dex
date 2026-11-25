import SwiftUI

struct HabitatInfoPanel: View {
    let spirit: Spirit
    private let catalog = HabitatCatalog.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 7) {
                if let entry = catalog.entry(for: spirit) {
                    if !entry.areas.isEmpty {
                        label("大世界分布", symbol: "map")
                        Text(entry.areas.joined(separator: "、"))
                    }
                    let markers = entry.points.compactMap { catalog.point($0) }
                    if entry.areas.isEmpty {
                        let regions = Set(markers.filter(\.isHabitat).map(\.region)).sorted()
                        if !regions.isEmpty {
                            label("地图栖息地", symbol: "mappin.and.ellipse")
                            Text(regions.joined(separator: "、"))
                        }
                    }
                    ForEach(["精灵首领", "传说挑战"], id: \.self) { kind in
                        let regions = Set(markers.filter { $0.kind == kind }.map(\.region)).sorted()
                        if !regions.isEmpty {
                            label(kind, symbol: "flag.fill")
                            Text(regions.joined(separator: "、"))
                        }
                    }
                    if !entry.habitat.isEmpty {
                        label("栖息记录", symbol: "leaf")
                        Text(entry.habitat)
                    }
                    ForEach(["野外捕捉", "进化", "精灵果实", "特殊精灵蛋", "限时获取"], id: \.self) { kind in
                        let rows = entry.sources.filter { $0.kind == kind }
                        if !rows.isEmpty {
                            label(kind, symbol: sourceSymbol(kind))
                            ForEach(rows.indices, id: \.self) { i in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(rows[i].name).fontWeight(.semibold)
                                    if !rows[i].detail.isEmpty {
                                        Text(rows[i].detail).foregroundStyle(.secondary)
                                    }
                                    if let reference = rows[i].reference {
                                        Link("查看官方公告", destination: reference).font(.caption)
                                    }
                                }
                            }
                        }
                    }
                    if entry.sources.isEmpty && entry.areas.isEmpty && entry.points.isEmpty {
                        Text("图鉴尚未列出获取途径。").foregroundStyle(.secondary)
                    }
                } else {
                    Text("生态资料未载入")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(.system(size: 12))
            .padding(.vertical, 2)
        }
        .id(spirit.id)
        .accessibilityIdentifier("habitatInfo")
    }

    private func label(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(spirit.ink)
            .accessibilityAddTraits(.isHeader)
    }

    private func sourceSymbol(_ kind: String) -> String {
        switch kind {
        case "野外捕捉": return "binoculars"
        case "进化": return "arrow.triangle.branch"
        case "精灵果实": return "leaf.fill"
        case "限时获取": return "calendar"
        default: return "oval"
        }
    }
}

private struct FieldLocation {
    let id: String
    let point: HabitatPoint
}

private struct MapContent {
    let mapID: String
    let locations: [FieldLocation]
    let areas: [HabitatRegion]

    init(mapID: String, entry: HabitatEntry) {
        self.mapID = mapID
        let catalog = HabitatCatalog.shared
        self.locations = entry.points.compactMap { id in
            guard let p = catalog.point(id), p.map == mapID else { return nil }
            return FieldLocation(id: id, point: p)
        }
        self.areas = entry.regions.compactMap { catalog.region($0) }.filter { $0.map == mapID }
    }

    var extent: CGRect? {
        var extent = CGRect.null
        for region in areas {
            for pair in region.polygon where pair.count == 2 {
                extent = extent.union(CGRect(x: pair[0], y: pair[1], width: 0, height: 0))
            }
        }
        for item in locations {
            extent = extent.union(CGRect(x: item.point.x, y: item.point.y, width: 0, height: 0))
        }
        return extent.isNull ? nil : extent
    }
}

private struct FieldCamera {
    var center = CGPoint(x: 0.5, y: 0.5)
    var zoom: CGFloat = 1

    static func overview(_ content: MapContent, size: CGSize) -> FieldCamera {
        guard let extent = content.extent else {
            let shortest = max(1, min(size.width, size.height))
            return FieldCamera(zoom: min(1.6, max(size.width, size.height) / shortest))
        }
        let shortest = max(1, min(size.width, size.height))
        let fitX = (size.width / shortest) / max(0.18, extent.width + 0.08)
        let fitY = (size.height / shortest) / max(0.18, extent.height + 0.08)
        return FieldCamera(center: CGPoint(x: extent.midX, y: extent.midY), zoom: min(5, max(1, min(fitX, fitY))))
    }

    func side(_ size: CGSize) -> CGFloat { max(1, min(size.width, size.height) * zoom) }

    func constrained(to size: CGSize) -> FieldCamera {
        let length = side(size)
        func clamp(_ value: CGFloat, _ dimension: CGFloat) -> CGFloat {
            let inset = min(0.5, dimension / (2 * length))
            return min(1 - inset, max(inset, value))
        }
        return FieldCamera(center: CGPoint(x: clamp(center.x, size.width), y: clamp(center.y, size.height)), zoom: zoom)
    }
}

private struct FieldDrawing: View {
    let content: MapContent
    let camera: FieldCamera
    var selected: String? = nil

    var body: some View {
        let picture = HabitatCatalog.shared.image(for: content.mapID)
        Canvas { context, size in
            let constrained = camera.constrained(to: size)
            let length = constrained.side(size)
            let origin = CGPoint(x: size.width / 2 - constrained.center.x * length,
                                 y: size.height / 2 - constrained.center.y * length)
            let rect = CGRect(origin: origin, size: CGSize(width: length, height: length))
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.10, green: 0.20, blue: 0.20)))
            if let picture { context.draw(Image(uiImage: picture), in: rect) }
            func xy(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: origin.x + x * length, y: origin.y + y * length)
            }
            for area in content.areas {
                var path = Path()
                for (index, pair) in area.polygon.enumerated() where pair.count == 2 {
                    let coordinate = xy(pair[0], pair[1])
                    if index == 0 { path.move(to: coordinate) } else { path.addLine(to: coordinate) }
                }
                path.closeSubpath()
                context.fill(path, with: .color(Color.cyan.opacity(0.20)))
                context.stroke(path, with: .color(Color(red: 0.02, green: 0.42, blue: 0.49)), lineWidth: selected == area.name ? 3 : 1.3)
            }
            for location in content.locations {
                let p = location.point
                let at = xy(p.x, p.y)
                let active = location.id == selected
                let radius: CGFloat = active ? 7 : 4.2
                let mark = Path(ellipseIn: CGRect(x: at.x - radius, y: at.y - radius, width: 2 * radius, height: 2 * radius))
                context.fill(mark, with: .color(p.isHabitat ? Color(red: 0.75, green: 0.12, blue: 0.10) : Color(red: 0.34, green: 0.10, blue: 0.56)))
                context.stroke(mark, with: .color(.white), lineWidth: active ? 2.5 : 1.5)
            }
        }.accessibilityHidden(true)
    }
}

struct HabitatMapPanel: View {
    let spirit: Spirit
    @State private var expanded = false
    private let catalog = HabitatCatalog.shared

    var body: some View {
        if let entry = catalog.entry(for: spirit) {
            let content = MapContent(mapID: "mainland", entry: entry)
            Button(feedback: .key) { expanded = true } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Label("分布地图", systemImage: "map")
                        Spacer()
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .font(.subheadline.bold()).foregroundStyle(Color(red: 0.71, green: 0.87, blue: 0.96))
                    GeometryReader { g in
                        FieldDrawing(content: content, camera: .overview(content, size: g.size))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    Text(coverage(entry, content: content))
                        .font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.88)).lineLimit(2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开\(spirit.formattedName)的分布地图")
            .accessibilityIdentifier("expandHabitatMap")
            .sheet(isPresented: $expanded) {
                FieldMapSheet(spirit: spirit, entry: entry)
                    .id(spirit.id)
            }
        } else {
            Text("地图资料未载入")
        }
    }

    private func coverage(_ entry: HabitatEntry, content: MapContent) -> String {
        if !content.locations.isEmpty { return "\(content.locations.count) 个地图标记 · 点按放大" }
        if !content.areas.isEmpty { return "已标出分布区域 · 点按放大" }
        if !entry.areas.isEmpty { return "有地点记录，地图暂缺定位" }
        return "该形态尚无野外坐标"
    }
}

private struct FieldMapSheet: View {
    let spirit: Spirit
    let entry: HabitatEntry
    @Environment(\.dismiss) private var dismiss
    @State private var mapID = "mainland"
    @State private var camera: FieldCamera?
    @State private var selected: String?
    @GestureState private var drag: CGSize = .zero
    @GestureState private var magnification: CGFloat = 1

    private var content: MapContent { MapContent(mapID: mapID, entry: entry) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(spirit.formattedName + " · 分布地图")
                    .font(.headline).lineLimit(1).minimumScaleFactor(0.75)
                Spacer()
                Button(feedback: .key) { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").font(.title2).frame(width: 40, height: 38)
                }
                .accessibilityLabel("关闭地图").accessibilityIdentifier("closeHabitatMap")
            }
            Picker("地图", selection: $mapID) {
                ForEach(["mainland", "academy"], id: \.self) { id in
                    Text(HabitatCatalog.shared.map(id)?.name ?? id).tag(id)
                }
            }
            .pickerStyle(.segmented)
            GeometryReader { geo in
                let size = geo.size
                let base = camera ?? FieldCamera.overview(content, size: size)
                let displayed = adjusted(base, scale: magnification, delta: drag, size: size)
                ZStack(alignment: .bottomTrailing) {
                    FieldDrawing(content: content, camera: displayed, selected: selected)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 4)
                                .updating($drag) { value, state, _ in state = value.translation }
                                .onEnded { value in
                                    camera = adjusted(camera ?? base, scale: 1, delta: value.translation, size: size)
                                }
                                .simultaneously(with: MagnifyGesture()
                                    .updating($magnification) { value, state, _ in state = value.magnification }
                                    .onEnded { value in
                                        camera = adjusted(camera ?? base, scale: value.magnification, delta: .zero, size: size)
                                    })
                        )
                        .onTapGesture(coordinateSpace: .local) { position in
                            focusNear(position, base: displayed, size: size)
                        }
                    HStack(spacing: 1) {
                        mapControl("minus.magnifyingglass", "缩小地图") {
                            camera = adjusted(base, scale: 1 / 1.6, delta: .zero, size: size)
                        }
                        mapControl("plus.magnifyingglass", "放大地图") {
                            camera = adjusted(base, scale: 1.6, delta: .zero, size: size)
                        }
                        mapControl("scope", "重置视角") { camera = nil; selected = nil }
                    }
                    .background(.ultraThinMaterial, in: Capsule()).padding(6)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            let regionNames = Set(content.areas.map(\.name))
                .subtracting(content.locations.map { $0.point.region }).sorted()
            if !content.locations.isEmpty || !regionNames.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 7) {
                        ForEach(content.locations, id: \.id) { location in
                            Button {
                                focus(location)
                            } label: {
                                Label(location.point.label, systemImage: location.point.isHabitat ? "mappin.circle" : "flag")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 9).padding(.vertical, 6)
                                    .background(location.id == selected ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.11), in: Capsule())
                            }.buttonStyle(.plain)
                        }
                        ForEach(regionNames, id: \.self) { name in
                            Button(feedback: .key) {
                                selected = name
                                var extent = CGRect.null
                                for area in content.areas where area.name == name {
                                    for pair in area.polygon where pair.count == 2 {
                                        extent = extent.union(CGRect(x: pair[0], y: pair[1], width: 0, height: 0))
                                    }
                                }
                                if !extent.isNull {
                                    camera = FieldCamera(center: CGPoint(x: extent.midX, y: extent.midY),
                                                         zoom: min(8, 1 / max(0.15, max(extent.width, extent.height) + 0.08)))
                                }
                            } label: {
                                Label(name, systemImage: "map")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 9).padding(.vertical, 6)
                                    .background(name == selected ? Color.cyan.opacity(0.22) : Color.secondary.opacity(0.11), in: Capsule())
                            }.buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                if let select = selected, let point = HabitatCatalog.shared.point(select) {
                    Text([point.kind, point.province, point.region, point.level].filter { !$0.isEmpty }
                        .reduce(into: [String]()) { result, part in if !result.contains(part) { result.append(part) } }.joined(separator: " · "))
                        .font(.caption).lineLimit(2)
                }
            }
            Text(legend).font(.caption).foregroundStyle(.secondary).lineLimit(3)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .onChange(of: mapID) { _, _ in DeckSound.page.play(); camera = nil; selected = nil }
        .presentationDragIndicator(.visible)
        .presentationDetents([.large])
    }

    private var legend: String {
        var items: [String] = []
        if content.locations.contains(where: { $0.point.isHabitat }) { items.append("红点为区域栖息地") }
        if content.locations.contains(where: { !$0.point.isHabitat }) { items.append("紫点为首领或传说挑战") }
        if !content.areas.isEmpty { items.append("青色范围为图鉴分布区") }
        if items.isEmpty { return "当前地图尚未收录该形态的野外定位。" }
        return items.joined(separator: " · ")
    }

    private func mapControl(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(feedback: .key, action: action) { Image(systemName: symbol).frame(width: 38, height: 36) }
            .accessibilityLabel(label)
    }

    private func adjusted(_ base: FieldCamera, scale: CGFloat, delta: CGSize, size: CGSize) -> FieldCamera {
        var result = base.constrained(to: size)
        result.zoom = max(1, min(14, result.zoom * scale))
        let side = result.side(size)
        result.center.x -= delta.width / side
        result.center.y -= delta.height / side
        return result.constrained(to: size)
    }

    private func focus(_ location: FieldLocation) {
        DeckSound.key.play()
        selected = location.id
        camera = FieldCamera(center: CGPoint(x: location.point.x, y: location.point.y), zoom: max(5, camera?.zoom ?? 1))
    }

    private func focusNear(_ tap: CGPoint, base: FieldCamera, size: CGSize) {
        let cam = base.constrained(to: size)
        let side = cam.side(size)
        let origin = CGPoint(x: size.width / 2 - cam.center.x * side, y: size.height / 2 - cam.center.y * side)
        let distances = content.locations.map { location in
            (location, hypot(location.point.x * side + origin.x - tap.x, location.point.y * side + origin.y - tap.y))
        }
        if let (location, distance) = distances.min(by: { $0.1 < $1.1 }), distance <= 22 { focus(location) }
    }
}
