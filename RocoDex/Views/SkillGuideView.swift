import SwiftUI

struct GameTypeIcons: View {
    let types: String
    let size: CGFloat

    var body: some View {
        let names = types.components(separatedBy: CharacterSet(charactersIn: "／/、,，·|"))
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        HStack(spacing: max(2, size * 0.17)) {
            ForEach(names, id: \.self) { name in
                if let icon = BattleGuide.shared.typeImage(name) {
                    Image(uiImage: icon).resizable().scaledToFit().frame(width: size, height: size)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(names.map { $0.hasSuffix("系") ? $0 : $0 + "系" }.joined(separator: "、"))
    }
}

struct TraitIcon: View {
    let spiritID: Int
    let size: CGFloat

    var body: some View {
        if let trait = BattleGuide.shared.trait(for: spiritID),
           let icon = BattleGuide.shared.image(trait.icon) {
            Image(uiImage: icon).resizable().scaledToFit().frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}

private enum SkillPalette {
    static let screen = Color(red: 0.20, green: 0.23, blue: 0.25)
    static let card = Color(red: 0.26, green: 0.29, blue: 0.30)
    static let line = Color.white.opacity(0.20)
    static let blue = Color(red: 0.72, green: 0.87, blue: 0.98)
    static let gold = Color(red: 1, green: 0.83, blue: 0.48)
}

struct SkillGuideView: View {
    let spirit: Spirit

    var body: some View {
        SkillBook(spirit: spirit).id(spirit.id)
    }
}

private struct SkillBook: View {
    let spirit: Spirit
    @State private var source: SkillSource?
    @State private var query = ""
    @State private var expanded = false

    var body: some View {
        SkillGridPanel(spirit: spirit, source: $source, query: $query, expanded: false) {
            expanded = true
        }
        .sheet(isPresented: $expanded) {
            SkillGridPanel(spirit: spirit, source: $source, query: $query, expanded: true) {
                expanded = false
            }
            .presentationDragIndicator(.visible)
            .presentationBackground(SkillPalette.screen)
        }
    }
}

private struct KnownMove: Identifiable {
    let learned: LearnedSkill
    let skill: BattleSkill
    var id: String { learned.id }

    func matches(_ query: String) -> Bool {
        query.isEmpty || [skill.name, skill.effect, skill.element, skill.category, learned.learningDescription]
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

private struct SkillGridPanel: View {
    let spirit: Spirit
    @Binding var source: SkillSource?
    @Binding var query: String
    let expanded: Bool
    let changeSize: () -> Void
    @State private var selection: KnownMove?
    @FocusState private var editing: Bool

    private var moves: [KnownMove] {
        let guide = BattleGuide.shared
        return guide.skills(for: spirit.id).compactMap { learned in
            guide.skill(learned.skill).map { KnownMove(learned: learned, skill: $0) }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let large = geometry.size.width > 520
            let small = geometry.size.height < 195
            let all = moves
            let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let matches = all.filter { (source == nil || source == $0.learned.source) && $0.matches(search) }
            let counts = Dictionary(grouping: all) { $0.learned.source }.mapValues(\.count)
            let pad: CGFloat = large ? 14 : (small ? 5 : 8)
            VStack(alignment: .leading, spacing: small ? 3 : 6) {
                searchBar(compact: small, large: large)
                filters(counts: counts, compact: small, large: large)
                if matches.isEmpty {
                    Text(search.isEmpty ? "暂无技能资料" : "没有找到「\(search)」相关的技能")
                        .font(.callout).foregroundStyle(.white.opacity(0.78))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 9) {
                            ForEach(SkillSource.allCases) { group in
                                let entries = matches.filter { $0.learned.source == group }
                                if !entries.isEmpty {
                                    section(group, entries: entries, compact: small, large: large)
                                }
                            }
                        }
                        .padding(.bottom, 4)
                    }
                    .id([source?.rawValue ?? "", search])
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .padding(pad)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(SkillPalette.screen)
            .foregroundStyle(.white)
        }
        .fullScreenCover(item: $selection) { move in
            SkillDetail(move: move) {
                DeckSound.key.play()
                selection = nil
            }
                .presentationBackground(.clear)
        }
    }

    private func searchBar(compact: Bool, large: Bool) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(SkillPalette.blue)
                TextField("", text: $query,
                          prompt: Text("搜索技能或效果").foregroundStyle(.white.opacity(0.75)))
                    .foregroundStyle(.white).tint(SkillPalette.blue)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.search).focused($editing)
                    .onSubmit { editing = false }
                    .accessibilityLabel("搜索技能或效果").accessibilityIdentifier("skillSearch")
                if !query.isEmpty {
                    Button(feedback: .key) {
                        query = ""
                    } label: { Image(systemName: "xmark.circle.fill") }
                    .accessibilityLabel("清空搜索")
                }
            }
            .padding(.horizontal, 8)
            .frame(height: large ? 34 : (compact ? 23 : 28))
            .background(SkillPalette.card, in: Capsule())
            .overlay { Capsule().strokeBorder(SkillPalette.line) }

            Button(feedback: .key) {
                editing = false
                changeSize()
            } label: {
                Image(systemName: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .frame(width: large ? 36 : 29, height: large ? 34 : 26)
                    .background(SkillPalette.card, in: Capsule())
                    .overlay { Capsule().strokeBorder(SkillPalette.line) }
                    .frame(minWidth: 44, minHeight: compact ? 32 : 44).contentShape(Rectangle())
            }
            .accessibilityLabel(expanded ? "收起技能图鉴" : "放大技能图鉴")
            .accessibilityIdentifier("skillExpand")
        }
        .buttonStyle(.plain)
        .font(.system(size: large ? 15 : 12, weight: .medium))
    }

    private func filters(counts: [SkillSource: Int], compact: Bool, large: Bool) -> some View {
        let total = counts.values.reduce(0, +)
        return ScrollView(.horizontal) {
            HStack(spacing: 4) {
                sourceButton(nil, title: "全部", count: total, compact: compact, large: large)
                ForEach(SkillSource.allCases) { option in
                    if let count = counts[option], count > 0 {
                        sourceButton(option, title: option.title, count: count, compact: compact, large: large)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func sourceButton(_ option: SkillSource?, title: String, count: Int, compact: Bool, large: Bool) -> some View {
        let selected = source == option
        return Button(feedback: .key) {
            editing = false
            source = option
        } label: {
            HStack(spacing: 3) {
                Text(title)
                Text(String(count)).font(.caption2.monospacedDigit())
            }
            .padding(.horizontal, large ? 10 : 7)
            .frame(height: large ? 29 : (compact ? 20 : 23))
            .background(SkillPalette.card, in: Capsule())
            .overlay { Capsule().strokeBorder(selected ? SkillPalette.blue : SkillPalette.line) }
            .frame(minWidth: 44, minHeight: compact ? 32 : 44).contentShape(Rectangle())
        }
        .font(.system(size: large ? 14 : 11, weight: .semibold))
        .foregroundStyle(selected ? SkillPalette.blue : Color.white.opacity(0.86))
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)，\(count) 个技能")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("skillFilter-" + (option?.rawValue ?? "all"))
    }

    private func section(_ source: SkillSource, entries: [KnownMove], compact: Bool, large: Bool) -> some View {
        let minimum: CGFloat = large ? 80 : 51
        let iconSize: CGFloat = large ? 46 : (compact ? 26 : 33)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(source.title).foregroundStyle(SkillPalette.gold)
                Text("\(entries.count) 个技能").foregroundStyle(.white.opacity(0.72))
            }
            .font(.system(size: large ? 14 : 10, weight: .semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum), spacing: 4)], spacing: 4) {
                ForEach(entries) { move in
                    Button(feedback: .key) {
                        editing = false
                        selection = move
                    } label: {
                        VStack(spacing: 2) {
                            ZStack(alignment: .topTrailing) {
                                skillIcon(move.skill, size: iconSize)
                                    .frame(maxWidth: .infinity)
                                GameTypeIcons(types: move.skill.element, size: large ? 15 : 11)
                            }
                            Text(move.skill.name)
                                .font(.system(size: large ? 14 : 11, weight: .semibold))
                                .foregroundStyle(SkillPalette.blue).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .padding(4)
                        .frame(maxWidth: .infinity)
                        .background(SkillPalette.card, in: RoundedRectangle(cornerRadius: 6))
                        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(SkillPalette.line) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(move.skill.name)，\(move.learned.learningDescription)")
                    .accessibilityIdentifier("skill-\(source.rawValue)-\(move.learned.skill)")
                }
            }
        }
    }
}

private func skillIcon(_ skill: BattleSkill, size: CGFloat) -> some View {
    Group {
        if let image = BattleGuide.shared.image(skill.icon) {
            Image(uiImage: image).resizable().scaledToFit()
        }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
}

private struct SkillDetail: View {
    let move: KnownMove
    let close: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.57).ignoresSafeArea()
                .onTapGesture(perform: close).accessibilityHidden(true)
            ViewThatFits(in: .vertical) {
                card
                ScrollView { card }.scrollBounceBehavior(.basedOnSize)
            }
            .frame(maxWidth: 450)
            .padding(14)
        }
        .foregroundStyle(.white)
        .accessibilityAction(.escape, close)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                skillIcon(move.skill, size: 49)
                VStack(alignment: .leading, spacing: 5) {
                    Text(move.skill.name)
                        .font(.system(size: 22, weight: .heavy)).foregroundStyle(SkillPalette.blue)
                    HStack(spacing: 5) {
                        GameTypeIcons(types: move.skill.element, size: 17).accessibilityHidden(true)
                        Text(move.skill.element)
                        Text(move.skill.category).padding(.leading, 4)
                    }
                    .font(.subheadline.weight(.medium))
                }
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                        .frame(width: 35, height: 35)
                        .overlay { Circle().strokeBorder(SkillPalette.line) }
                }
                .buttonStyle(.plain).accessibilityLabel("关闭技能详情")
                .accessibilityIdentifier("skillDetailClose")
            }
            Divider().overlay(SkillPalette.line)
            HStack(spacing: 8) {
                value("威力", move.skill.power ?? "—")
                value("能耗", String(move.skill.energy))
            }
            HStack(spacing: 6) {
                Text("学习来源").foregroundStyle(.white.opacity(0.72))
                Text(move.learned.learningDescription)
            }
            .font(.subheadline)
            Text("技能效果").font(.subheadline.bold()).foregroundStyle(SkillPalette.gold)
            Text(move.skill.effect).font(.body).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(SkillPalette.screen, in: RoundedRectangle(cornerRadius: 15))
        .overlay { RoundedRectangle(cornerRadius: 15).strokeBorder(SkillPalette.line) }
        .shadow(color: .black.opacity(0.28), radius: 15, y: 5)
    }

    private func value(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.subheadline.weight(.medium))
            Spacer()
            Text(value).font(.title3.bold().monospacedDigit()).foregroundStyle(SkillPalette.gold)
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(SkillPalette.card, in: RoundedRectangle(cornerRadius: 7))
    }
}
