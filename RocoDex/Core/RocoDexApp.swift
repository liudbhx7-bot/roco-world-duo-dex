import SwiftUI

@main
struct RocoDexApp: App {
    private let archive = Result { try Catalog() }
    var body: some Scene {
        WindowGroup {
            switch archive {
            case .success(let catalog): FieldGuideView(catalog: catalog)
            case .failure:
                ContentUnavailableView("图鉴资料无法打开", systemImage: "externaldrive.badge.exclamationmark", description: Text("请重新安装包含完整资源的应用。"))
            }
        }
    }
}
