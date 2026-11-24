import SwiftUI

struct ElementFilter: View {
    let catalog: Catalog
    @Binding var selection: String?
    private let elements = ["普通", "草", "火", "水", "光", "地", "冰", "龙", "电", "毒", "虫", "武", "翼", "萌", "幽", "恶", "机械", "幻"]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64, maximum: 92))], spacing: 6) {
            ForEach(elements, id: \.self) { element in
                let count = catalog.countsByElement[element, default: 0]
                Button {
                    selection = selection == element ? nil : element
                } label: {
                    HStack(spacing: 4) {
                        GameTypeIcons(types: element, size: 19)
                        Text(String(count)).font(.caption.monospacedDigit())
                    }
                    .frame(maxWidth: .infinity, minHeight: 31)
                    .background(.secondary.opacity(0.09), in: Capsule())
                    .overlay {
                        if selection == element {
                            Capsule().strokeBorder(Color.accentColor, lineWidth: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(element)系，\(count) 个形态")
                .accessibilityAddTraits(selection == element ? .isSelected : [])
            }
        }
        .padding(.vertical, 3)
    }
}
