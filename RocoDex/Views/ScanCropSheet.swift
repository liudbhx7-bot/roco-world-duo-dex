import SwiftUI

struct ScanCropSheet: View {
    let image: UIImage
    let submit: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var center = CGPoint(x:0.5,y:0.5)
    @State private var fraction = 0.55

    private var unitRect: CGRect {
        let minSide = min(image.size.width,image.size.height)
        let w = minSide * fraction / image.size.width
        let h = minSide * fraction / image.size.height
        return CGRect(x:min(max(0,center.x - w/2),1-w), y:min(max(0,center.y - h/2),1-h), width:w, height:h)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing:12) {
                Text("点一下精灵，把选框调到刚好包住它。").font(.subheadline)
                GeometryReader { proxy in
                    let scale = min(proxy.size.width/image.size.width,proxy.size.height/image.size.height)
                    let size = CGSize(width:image.size.width*scale,height:image.size.height*scale)
                    let selection = unitRect
                    let box = CGRect(x:selection.minX*size.width,y:selection.minY*size.height,
                                     width:selection.width*size.width,height:selection.height*size.height)
                    ZStack {
                        Image(uiImage:image).resizable().frame(width:size.width,height:size.height)
                        Path { path in
                            path.addRect(CGRect(origin:.zero,size:size)); path.addRect(box)
                        }.fill(.black.opacity(0.56),style:FillStyle(eoFill:true))
                        Path { $0.addRect(box) }.stroke(.yellow,lineWidth:2)
                    }
                    .frame(width:size.width,height:size.height)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance:0).onChanged { drag in
                        center = CGPoint(x:min(1,max(0,drag.location.x/size.width)),
                                         y:min(1,max(0,drag.location.y/size.height)))
                    })
                    .accessibilityLabel("调整目标位置")
                    .frame(maxWidth:.infinity,maxHeight:.infinity)
                }
                HStack { Image(systemName:"minus.magnifyingglass"); Slider(value:$fraction,in:0.12...1).accessibilityLabel("选框大小"); Image(systemName:"plus.magnifyingglass") }
                Button("识别选中区域") {
                    if let crop = ScanFrame.crop(image,unitRect:unitRect) { dismiss(); submit(crop) }
                }.buttonStyle(.borderedProminent).controlSize(.large)
            }
            .padding()
            .navigationTitle("框选精灵")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.cancellationAction) { Button("取消") { dismiss() } } }
        }
    }
}
