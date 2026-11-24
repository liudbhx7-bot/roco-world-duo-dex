import SwiftUI
import PhotosUI

private enum ScanStage {
    case archive, aim, working, choices, miss
}

private enum GuideIndex: Hashable, Identifiable {
    case all
    case forms(Int)
    var id: Self { self }
}

struct FieldGuideView: View {
    let catalog: Catalog
    @State private var recognizer: SpiritRecognizer
    @StateObject private var camera = DexCamera()
    @State private var stage: ScanStage = .archive
    @State private var page: ArchivePage = .profile
    @State private var controls = false
    @State private var digits = ""
    @State private var notice = ""
    @State private var indexScope: GuideIndex?
    @State private var indexQuery = ""
    @State private var indexType: String?
    @State private var showDetails = false
    @State private var pickingPhoto = false
    @State private var photo: PhotosPickerItem?
    @State private var scanTask: Task<Void,Never>?
    @State private var generation = UUID()
    @State private var reviewImage: UIImage?
    @State private var adjustingFrame = false
    @State private var candidates: [Int] = []
    @StateObject private var narrator = DexNarrator()
    @AppStorage("currentSpirit") private var selected = 8
    @AppStorage("foundSpirits") private var foundIDs = ""
    @AppStorage("voiceOnScan") private var voice = false
    @Environment(\.scenePhase) private var phase

    init(catalog: Catalog) {
        self.catalog = catalog
        _recognizer = State(initialValue: SpiritRecognizer(references:catalog.references))
    }
    private var spirit: Spirit { catalog.entries.first { $0.id == selected } ?? catalog.entries[0] }
    private var found: Set<Int> { Set(foundIDs.split(separator:",").compactMap { Int($0) }) }

    var body: some View {
        HandheldShell(page: $page, keypadOpen: $controls, scanActive: stage != .archive, scanning:stage == .aim || stage == .working, leftScreen: {
            leftLCD.overlay(alignment:.topLeading) {
                if stage == .aim || stage == .miss || stage == .working {
                    Button { stopScan(); notice = "" } label: {
                        Image(systemName:"chevron.backward").font(.caption.bold()).padding(8)
                            .background(.black.opacity(0.62),in:Circle())
                    }.buttonStyle(.plain).foregroundStyle(.white).padding(3)
                        .accessibilityLabel("返回精灵档案")
                }
            }
        }, rightScreen: {
            switch page {
            case .profile: DossierStatsPanel(spirit: spirit)
            case .family: SkillGuideView(spirit: spirit)
            case .habitat: HabitatMapPanel(spirit: spirit)
            }
        }, keypadScreen: {
            StatusLCD(headline: headline, message: displayMessage)
        }, onKey: press)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .photosPicker(isPresented:$pickingPhoto,selection:$photo,matching:.images)
        .onChange(of:photo) { _, item in
            if let item { importPhoto(item) }
        }
        .onChange(of:pickingPhoto) { _, isShown in
            if isShown { camera.stop() }
            else if stage == .aim && photo == nil && phase == .active { camera.start() }
        }
        .onChange(of:phase) { _, phase in
            if phase == .active {
                if stage == .aim && !pickingPhoto && indexScope == nil { camera.start() }
            } else {
                camera.stop()
                narrator.stop()
            }
        }
        .sheet(isPresented:$adjustingFrame) {
            if let reviewImage {
                ScanCropSheet(image:reviewImage) { cropped in
                    runScan(reframing:true) { cropped }
                }
            }
        }
        .sheet(item: $indexScope, onDismiss: { indexQuery = ""; indexType = nil }) { scope in indexSheet(scope) }
        .sheet(isPresented:$showDetails, onDismiss: narrator.stop) {
            detailSheet.modifier(NarrationAlert(message: $narrator.unavailableMessage, active: true))
        }
        .modifier(NarrationAlert(message: $narrator.unavailableMessage, active: !showDetails))
        .onDisappear { camera.stop(); scanTask?.cancel() }
    }

    @ViewBuilder private var leftLCD: some View {
        switch stage {
        case .archive:
            PortraitLCD(spirit: spirit, catalog: catalog, page: page, found: found.contains(spirit.id),
                        select: { choose($0, resetPage: false) }, openDetails: { showDetails = true },
                        openForms: {
                            indexScope = .forms(spirit.dexNumber ?? spirit.id)
                        },
                        animationURL: catalog.animationURLs[spirit.id], isNarrating: narrator.isSpeaking,
                        toggleNarration: toggleNarration)
        case .aim,.working:
            ZStack {
                Color(red:0.05,green:0.12,blue:0.11)
                switch camera.state {
                case .ready:
                    DexCameraPreview(camera:camera)
                        .overlay { ViewfinderMarks().stroke(.white.opacity(0.8),lineWidth:2).padding(12).allowsHitTesting(false) }
                        .overlay(alignment:.bottomTrailing) { importButton.padding(4) }
                case .idle, .starting:
                    VStack(spacing:6) { ProgressView().tint(.white); Text("正在打开取景器"); importButton }
                case .denied:
                    VStack(spacing:4) {
                        Text("相机权限已关闭")
                        Button("打开设置") {
                            if let url = URL(string:UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }.buttonStyle(.bordered)
                        importButton
                    }
                case .unavailable:
                    VStack(spacing:6) { Image(systemName:"photo.on.rectangle.angled"); Text("当前设备无可用相机"); importButton }
                case .failed(let reason):
                    VStack(spacing:3) { Text(reason).lineLimit(2); Button("重试相机") { camera.start() }; importButton }
                }
                if stage == .working {
                    VStack(spacing:6) { ProgressView().tint(.white); Text("正在比对精灵") }
                        .frame(maxWidth:.infinity,maxHeight:.infinity).background(Color(red:0.06,green:0.14,blue:0.12))
                }
            }.foregroundStyle(.white).font(.system(size:12,weight:.medium)).clipped()
        case .miss:
            VStack(spacing:6) {
                Image(systemName:"viewfinder").font(.title3)
                Text(notice).multilineTextAlignment(.center).font(.system(size:12,weight:.semibold))
                if reviewImage != nil { cropButton } else { importButton }
            }.padding(6).frame(maxWidth:.infinity,maxHeight:.infinity).foregroundStyle(.white).background(Color(red:0.06,green:0.14,blue:0.12))
        case .choices:
            ScrollView {
                VStack(alignment:.leading,spacing:4) {
                    HStack {
                        Text("请选择匹配的精灵").font(.caption.bold())
                        Spacer()
                        if reviewImage != nil { cropButton }
                    }
                    ForEach(candidates,id:\.self) { id in
                        if let candidate = catalog.entries.first(where: { $0.id == id }) {
                            Button { discover(id) } label: {
                                HStack {
                                    if let pic = catalog.pictures.thumbnail(id) { Image(uiImage:pic).resizable().scaledToFit().frame(width:30,height:30) }
                                    Text(candidate.formattedName); Spacer(); Text(candidate.number).monospacedDigit()
                                }.padding(4).background(.white.opacity(0.09),in:RoundedRectangle(cornerRadius:4))
                            }.buttonStyle(.plain)
                        }
                    }
                }.padding(6)
            }.font(.caption).foregroundStyle(.white).background(Color(red:0.06,green:0.14,blue:0.12))
        }
    }

    private var cropButton: some View {
        Button { adjustingFrame = true } label: {
            Label("框选精灵",systemImage:"crop").font(.caption.bold()).padding(.horizontal,8).padding(.vertical,6)
        }.buttonStyle(.plain).background(.white.opacity(0.15),in:Capsule())
    }

    private var importButton: some View {
        Button { pickingPhoto = true } label: {
            Label("从相册识别",systemImage:"photo").font(.caption.bold()).padding(.horizontal,8).padding(.vertical,6)
        }.buttonStyle(.plain).background(.black.opacity(0.62),in:Capsule()).foregroundStyle(.white)
    }

    private var headline: String? {
        if !digits.isEmpty { return "NO. " + digits }
        switch stage {
        case .aim: return "等待发现"
        case .working: return "正在分析…"
        case .miss: return "未能识别"
        case .choices: return "找到相似精灵"
        case .archive: return notice.isEmpty ? nil : "图鉴查询"
        }
    }
    private var displayMessage: String {
        if !digits.isEmpty { return notice.isEmpty ? "按「查找」打开档案" : notice }
        switch stage {
        case .aim: return "轻点精灵对焦，再按扫描键拍摄"
        case .working: return "正在本机匹配参考图"
        case .choices: return "在左屏点选，或重新扫描"
        case .miss: return reviewImage == nil ? "按扫描键重试，或换一张图片" : "框选照片中的精灵，或按扫描键重拍"
        case .archive: return notice
        }
    }

    private func choose(_ id:Int, resetPage:Bool = true) {
        stopScan()
        narrator.stop()
        selected = id; digits = ""; notice = ""; controls = false
        if resetPage { page = .profile }
    }
    private func discover(_ id: Int) {
        guard let entry = catalog.entries.first(where: { $0.id == id }) else { return }
        var all = found; all.insert(id)
        foundIDs = all.sorted().map(String.init).joined(separator:",")
        choose(id)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if voice { narrator.speak(entry) }
    }

    private func toggleNarration() {
        if narrator.isSpeaking { narrator.stop() }
        else { narrator.speak(spirit) }
    }
    private func stopScan() {
        generation = UUID()
        scanTask?.cancel(); scanTask = nil
        if stage != .archive { camera.stop() }
        stage = .archive; reviewImage = nil
    }
    private func beginAim() {
        stopScan(); narrator.stop(); digits = ""; notice = ""; controls = false
        stage = .aim
        camera.start()
    }

    private func runScan(reframing: Bool = false, input: @escaping @MainActor () async throws -> UIImage) {
        scanTask?.cancel()
        let token = UUID(); generation = token
        if !reframing { reviewImage = nil }
        controls = false; stage = .working; digits = ""
        scanTask = Task { @MainActor in
            do {
                let image = try await input()
                guard generation == token, !Task.isCancelled else { return }
                camera.stop()
                if !reframing { reviewImage = image }
                let result = try await recognizer.identify(image)
                guard generation == token, !Task.isCancelled else { return }
                switch result {
                case .match(let id): discover(id)
                case .candidates(let ids):
                    candidates = ids; stage = .choices
                case .unknown:
                    notice = "没有匹配到已收录的精灵"; stage = .miss
                }
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                camera.stop(); notice = "这张图片未能读取，请重试"; stage = .miss
            }
        }
    }
    private func importPhoto(_ item: PhotosPickerItem) {
        photo = nil
        runScan {
            guard let data = try await item.loadTransferable(type:Data.self),
                  let img = ScanFrame.load(data) else { throw CocoaError(.fileReadCorruptFile) }
            return img
        }
    }

    private func press(_ key: DeckKey) {
        switch key {
        case .digit(let digit):
            if stage != .archive { stopScan() }
            notice = ""
            digits = digits.count >= 3 ? String(digit) : digits + String(digit)
            controls = true
        case .clear: digits = ""; notice = ""
        case .backspace:
            if !digits.isEmpty { digits.removeLast() }; notice = ""
        case .cancel:
            stopScan(); digits = ""; notice = ""; controls = false
        case .search:
            guard !digits.isEmpty else {
                stopScan(); notice = ""; indexScope = .all; return
            }
            if let number = Int(digits), let entry = catalog.forms(number:number).first {
                choose(entry.id)
            } else { notice = "未收录这个编号，请重新输入编号" }
        case .scan:
            if stage == .aim {
                switch camera.state {
                case .ready: runScan { try await camera.capture() }
                case .denied,.unavailable,.failed: pickingPhoto = true
                default: break
                }
            } else if stage != .working { beginAim() }
        case .left,.right:
            guard stage == .archive else { return }
            let delta: Int
            if case .left = key { delta = -1 } else { delta = 1 }
            page = page.shifted(delta); notice = ""; digits = ""
        case .up,.down:
            guard stage == .archive,let index = catalog.entries.firstIndex(where:{$0.id == spirit.id}) else { return }
            let delta: Int
            if case .up = key { delta = -1 } else { delta = 1 }
            let count = catalog.entries.count
            choose(catalog.entries[(index + delta + count) % count].id)
        case .info:
            stopScan(); indexScope = .all
        }
    }

    private var filteredEntries: [Spirit] {
        let query = indexQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let entries = catalog.entries.filter { spirit in
            guard let indexType else { return true }
            return spirit.elements.contains(indexType)
        }
        guard !query.isEmpty else { return entries }
        if let number = Int(query) {
            if query.count == 3 { return entries.filter { ($0.dexNumber ?? $0.id) == number } }
            return entries.filter { $0.number.hasPrefix(query) || Int($0.number) == number }
        }
        let typeQuery = query.hasSuffix("系") && query.count > 1 ? String(query.dropLast()) : query
        return entries.filter {
            $0.formattedName.localizedStandardContains(query) || $0.type.localizedStandardContains(typeQuery)
        }
    }

    private func indexSheet(_ scope: GuideIndex) -> some View {
        NavigationStack {
            if case let .forms(number) = scope {
                List {
                    Section("NO. " + String(format: "%03d", number)) {
                        ForEach(catalog.forms(number: number)) { entry in
                            indexRow(entry)
                        }
                    }
                }
                .navigationTitle("选择形态")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { indexScope = nil } } }
            } else {
                catalogList
            }
        }
    }

    private var catalogList: some View {
        let filtered = filteredEntries
        let discovered = found
        return List {
            if indexQuery.isEmpty {
                Section {
                    Toggle("识别成功时朗读",isOn:$voice)
                    DisclosureGroup("资料与配音") {
                        Link("洛克王国世界 WIKI · 精灵图鉴", destination: URL(string:"https://wiki.biligame.com/nrc/")!.appendingPathComponent("精灵图鉴"))
                        Link("图鉴资料整理 · CC BY-SA 4.0", destination: URL(string:"https://creativecommons.org/licenses/by-sa/4.0/")!)
                        Text("本图鉴整合了 Wiki 档案与进化分支。游戏角色与美术归原权利人所有。")
                        Link("介绍配音 · Qwen3-TTS 温暖观察", destination: URL(string:"https://github.com/QwenLM/Qwen3-TTS")!)
                    }.font(.footnote)
                }
            }
            if indexQuery.isEmpty {
                Section("精灵系别") {
                    ElementFilter(catalog: catalog, selection: $indexType)
                }
            }
            Section(indexQuery.isEmpty && indexType == nil ? "已发现 \(discovered.count) / \(catalog.entries.count)" : "\(filtered.count) 个结果") {
                ForEach(filtered) { entry in indexRow(entry, discovered: discovered) }
                if filtered.isEmpty { Text("试试精灵名、形态名、系别或图鉴编号。").foregroundStyle(.secondary) }
            }
        }.navigationTitle("精灵名册")
            .searchable(text:$indexQuery, placement:.navigationBarDrawer(displayMode:.always), prompt:"名称、形态、系别或编号")
            .toolbar { ToolbarItem(placement:.confirmationAction) { Button("完成") { indexScope = nil } } }
    }

    private func indexRow(_ entry: Spirit, discovered: Set<Int>? = nil) -> some View {
        let discovered = discovered ?? found
        return Button {
            indexScope = nil; choose(entry.id)
        } label: {
            HStack {
                if let image = catalog.pictures.thumbnail(entry.id) { Image(uiImage:image).resizable().scaledToFit().frame(width:42,height:42) }
                Text(entry.number).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                VStack(alignment:.leading, spacing:2) {
                    Text(entry.name)
                    if let form = entry.distinctForm {
                        Text(form).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if discovered.contains(entry.id) { Image(systemName:"checkmark.circle.fill").foregroundStyle(.green) }
                GameTypeIcons(types: entry.type, size: 20)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("entry-\(entry.id)")
    }

    private var detailSheet: some View {
        NavigationStack {
            List {
                Section(spirit.trait) { Text(spirit.traitDetail) }
                Section("图鉴记载") {
                    Text(spirit.summary)
                    Button(action: toggleNarration) {
                        Label(narrator.isSpeaking ? "停止介绍" : "播放介绍",
                              systemImage: narrator.isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                    }
                    .accessibilityIdentifier("detailNarration")
                    if let source = spirit.sourceURL, let url = URL(string:source) {
                        Link("查看原始图鉴", destination:url)
                    }
                }
            }.navigationTitle(spirit.number + " " + spirit.formattedName)
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("完成") { showDetails = false } } }
        }
    }
}

private struct NarrationAlert: ViewModifier {
    @Binding var message: String?
    let active: Bool

    func body(content: Content) -> some View {
        content.alert("图鉴朗读", isPresented: Binding(
            get: { active && message != nil },
            set: { if !$0 && active { message = nil } }
        )) {
            Button("知道了") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }
}

private struct ViewfinderMarks: Shape {
    func path(in r:CGRect) -> Path {
        var path = Path()
        let length = min(r.width,r.height)*0.15
        for (x,y,dx,dy) in [(r.minX,r.minY,1.0,1.0),(r.maxX,r.minY,-1.0,1.0),(r.minX,r.maxY,1.0,-1.0),(r.maxX,r.maxY,-1.0,-1.0)] {
            path.move(to:CGPoint(x:x+dx*length,y:y)); path.addLine(to:CGPoint(x:x,y:y)); path.addLine(to:CGPoint(x:x,y:y+dy*length))
        }
        return path
    }
}
