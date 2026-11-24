import SwiftUI

struct DossierStatsPanel: View {
    let spirit: Spirit

    private let statOrder = [0, 1, 3, 2, 4, 5]
    private let statSymbols = ["heart.fill", "bolt.fill", "shield.fill", "wand.and.stars", "shield.lefthalf.filled", "hare.fill"]
    private let gold = Color(red: 1, green: 0.79, blue: 0.37)
    private let cream = Color(red: 0.96, green: 0.94, blue: 0.85)
    private let blue = Color(red: 0.69, green: 0.87, blue: 0.96)

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = proxy.size.height < 300 ? 7 : 12
            ScrollView {
                VStack(alignment: .leading, spacing: spacing) {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(spacing: 4) {
                            Text("特性")
                                .font(.caption2.bold()).foregroundStyle(.black)
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(gold, in: Capsule())
                            TraitIcon(spiritID: spirit.id, size: 42)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(spirit.trait).font(.title3.bold()).foregroundStyle(blue)
                            if !spirit.traitDetail.isEmpty {
                                Text(spirit.traitDetail).font(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    VStack(spacing: 0) {
                        HStack {
                            Label("种族资质", systemImage: "sparkles")
                            Spacer()
                            Text(String(spirit.stats.reduce(0, +)))
                                .font(.title3.bold().monospacedDigit()).foregroundStyle(gold)
                        }
                        .font(.headline).padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.black.opacity(0.18))
                        VStack(spacing: spacing) {
                            ForEach(statOrder, id: \.self) { index in
                                HStack(spacing: 7) {
                                    Image(systemName: statSymbols[index]).frame(width: 18)
                                    Text(Spirit.statNames[index]).fixedSize()
                                    GeometryReader { bar in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(.black.opacity(0.44))
                                            Capsule().fill(cream)
                                                .frame(width: bar.size.width * min(CGFloat(spirit.stats[index]) / 180, 1))
                                        }
                                    }.frame(height: 7)
                                    Text(String(spirit.stats[index])).monospacedDigit()
                                        .frame(width: 31, alignment: .trailing)
                                }.font(.system(size: 13, weight: .bold, design: .rounded))
                                    .accessibilityElement(children: .combine)
                            }
                        }.padding(12)
                    }.background(.black.opacity(0.13), in: RoundedRectangle(cornerRadius: 10))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    if let profile = BattleGuide.shared.profile(for: spirit.id) {
                        HStack(alignment: .top, spacing: 6) {
                            if let height = profile.height { measure("身高", "ruler", height) }
                            if let weight = profile.weight { measure("体重", "scalemass", weight) }
                        }
                    }
                }.padding(12)
            }.id(spirit.id)
        }
        .foregroundStyle(cream)
        .background(Color(red: 0.22, green: 0.25, blue: 0.26))
    }

    private func measure(_ title: String, _ symbol: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.white.opacity(0.75))
            Text(value).font(.callout.bold()).minimumScaleFactor(0.75)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(9)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}
