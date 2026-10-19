import FoodDecisionCore
import SwiftData
import SwiftUI

struct FoodInformationView: View {
    @Query private var foods: [PersistentFoodItem]
    @State private var catalog: FoodCatalog?
    @State private var catalogError: String?

    init(foodID: UUID) {
        _foods = Query(filter: #Predicate<PersistentFoodItem> { $0.id == foodID })
    }

    var body: some View {
        List {
            if let food = foods.first {
                Section {
                    Text(food.name)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    FoodInformationRow(title: "营养基准", value: "每 100 \(food.unit)")
                    Text(food.source)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let domain = try? food.domainModel {
                    nutritionSection(domain.nutrientsPer100Units, unit: food.unit)
                    if let metadata = catalog?.metadata(for: domain), let catalog {
                        metadataSection(metadata, source: catalog.source)
                    } else if catalog != nil {
                        Section("来源资料") {
                            Text("此本地记录的来源资料尚未核实。营养数值以当前本地记录为准。")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Section {
                        Label("这项食物的营养资料有误，当前无法核对。", systemImage: "exclamationmark.triangle")
                    }
                }
            } else {
                ContentUnavailableView("食物已不可用", systemImage: "fork.knife", description: Text("请返回重新选择食物。"))
            }
            if catalogError != nil {
                Section {
                    Label("来源资料暂不可用，当前仅显示本地记录。", systemImage: "exclamationmark.triangle")
                    Button("重试载入食品资料", action: loadCatalog)
                }
            }
        }
        .accessibilityIdentifier("food.information")
        .navigationTitle("食物资料")
        .navigationBarTitleDisplayMode(.inline)
        .task { loadCatalog() }
    }

    private func nutritionSection(_ values: NutrientValues, unit: String) -> some View {
        Section("每 100 \(unit) 营养") {
            FoodInformationRow(title: "热量", value: KcalDisplay.amount(values.energyKcal))
            FoodInformationRow(title: "蛋白质", value: grams(values.proteinGrams))
            FoodInformationRow(title: "碳水化合物", value: grams(values.carbohydrateGrams))
            FoodInformationRow(title: "脂肪", value: grams(values.fatGrams))
            FoodInformationRow(title: "饱和脂肪", value: grams(values.saturatedFatGrams))
            FoodInformationRow(title: "糖", value: grams(values.sugarGrams))
            FoodInformationRow(title: "盐", value: grams(values.saltGrams))
            FoodInformationRow(title: "膳食纤维", value: values.fibreGrams.map(grams) ?? "未知")
        }
    }

    private func metadataSection(_ entry: FoodCatalogEntry, source: FoodCatalogSource) -> some View {
        Section("目录来源资料") {
            FoodInformationRow(title: "英文原名", value: entry.originalName)
                .accessibilityIdentifier("food.information.originalName")
            FoodInformationRow(title: "原始编码", value: entry.code)
                .accessibilityIdentifier("food.information.code")
            FoodInformationRow(title: "数据版本", value: "CoFID \(source.datasetVersion)")
                .accessibilityIdentifier("food.information.datasetVersion")
            FoodInformationRow(title: "食品状态", value: entry.foodState)
            FoodInformationRow(title: "原始基准", value: "每 100 g（可食部分）")
                .accessibilityIdentifier("food.information.basis")
            if !entry.aliases.isEmpty {
                FoodInformationRow(title: "中文别名", value: entry.aliases.joined(separator: "、"))
            }
            if let url = URL(string: source.url) {
                Link("原始数据来源", destination: url)
            }
            if let url = URL(string: source.licenseURL) {
                Link(source.licenseName, destination: url)
            }
        }
    }

    private func grams(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...2)))) g"
    }

    private func loadCatalog() {
        do {
            catalog = try FoodCatalog.bundled()
            catalogError = nil
        } catch {
            catalog = nil
            catalogError = error.localizedDescription
        }
    }
}
