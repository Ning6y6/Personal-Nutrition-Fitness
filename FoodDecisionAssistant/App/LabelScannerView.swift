import SwiftUI

struct LabelScannerView: View {
    var body: some View {
        ContentUnavailableView(
            "扫描尚未开放",
            systemImage: AppTab.scan.systemImage,
            description: Text("食品标签识别将在后续独立切片中开放。当前不会启动相机或上传照片。")
        )
        .navigationTitle(AppTab.scan.title)
    }
}
