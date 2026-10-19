import FoodDecisionCore
import SwiftUI

struct FoodSourcesView: View {
    @Environment(\.appDateDisplay) private var dateDisplay
    @State private var catalog: FoodCatalog?
    @State private var loadError: String?

    var body: some View {
        List {
            if let catalog {
                Section("食品数据") {
                    FoodInformationRow(title: "来源", value: catalog.source.title)
                        .accessibilityIdentifier("food.sources.provider")
                    FoodInformationRow(title: "数据版本", value: "CoFID \(catalog.source.datasetVersion)")
                        .accessibilityIdentifier("food.sources.datasetVersion")
                    FoodInformationRow(title: "获取日期", value: retrievalDate(catalog.source.retrievedOn))
                    if let url = URL(string: catalog.source.url) {
                        Link("原始数据来源", destination: url)
                    }
                    if let url = URL(string: catalog.source.guideURL) {
                        Link("原始数据说明", destination: url)
                    }
                }
                Section("许可与署名原文") {
                    Text(catalog.source.attribution)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("food.sources.attribution")
                    if let url = URL(string: catalog.source.licenseURL) {
                        Link(catalog.source.licenseName, destination: url)
                    }
                }
                Section("本地整理说明") {
                    Text("中文名称、别名和拼音搜索键经过本地整理。食品按来源的生熟状态、可食部和每 100 g 基准使用。")
                    Text("营养值保留原数据口径；痕量 Tr 按 0 作计算近似，不代表精确测得 0。盐由钠换算（盐 = 钠 × 2.5）；缺失纤维保持未知。")
                    Text("来源许可原文与上述中文说明分别列示。数据提供者未对本 App 作背书。")
                        .foregroundStyle(.secondary)
                }
            } else if loadError != nil {
                Section {
                    Label("数据来源资料暂不可用，请重试。", systemImage: "exclamationmark.triangle")
                    Button("重试", action: loadCatalog)
                }
            } else {
                ProgressView("正在载入来源资料…")
            }
        }
        .accessibilityIdentifier("food.sources")
        .navigationTitle("数据来源与许可")
        .navigationBarTitleDisplayMode(.inline)
        .task { loadCatalog() }
    }

    /// Dataset acquisition is a Gregorian civil day, not midnight in any time zone.
    private func retrievalDate(_ raw: String) -> String {
        let parts = raw.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let key = Int(parts.joined()), let day = try? GoalDay(key: key) else {
            return "未核实"
        }
        return dateDisplay.civilDate(for: day, referenceDay: nil)
    }

    private func loadCatalog() {
        do {
            catalog = try FoodCatalog.bundled()
            loadError = nil
        } catch {
            catalog = nil
            loadError = error.localizedDescription
        }
    }
}
