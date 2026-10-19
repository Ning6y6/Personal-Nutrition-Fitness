import FoodDecisionCore
import SwiftData
import SwiftUI

/// Search and information browsing are read-only. The caller changes one draft
/// row only after an explicit selection or clear action.
struct FoodSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \PersistentFoodItem.name) private var foods: [PersistentFoodItem]

    let selectedFoodID: UUID?
    let onSelect: (UUID?) -> Void
    let onShowInformation: (UUID) -> Void

    @State private var query = ""
    @State private var catalog: FoodCatalog?
    @State private var catalogError: String?
    @FocusState private var searchIsFocused: Bool

    var body: some View {
        let results = FoodSearchPolicy.search(query, in: searchDocuments)
        List {
            if selectedFoodID != nil {
                Section {
                    Button("清空当前选择", systemImage: "xmark.circle") {
                        select(nil)
                    }
                    .accessibilityIdentifier("food.selection.clear")
                }
            }

            if catalogError != nil {
                Section {
                    Label("食品资料未能载入，当前仅按本地名称搜索。", systemImage: "exclamationmark.triangle")
                    Button("重试载入食品资料", action: loadCatalog)
                }
            }

            if let selectedFoodID, !foods.contains(where: { $0.id == selectedFoodID }) {
                Section {
                    Text("原食物已不可用。返回会保留原选择；请重新选择或明确清空。")
                        .foregroundStyle(.secondary)
                }
            }

            if results.isEmpty {
                Section {
                    ContentUnavailableView(
                        "没有找到食物", systemImage: "magnifyingglass",
                        description: Text(query.isEmpty ? "食物目录尚未准备好，请返回后重试载入。" : "试试其他名称、别名或拼音首字母。")
                    )
                    if !query.isEmpty {
                        Button("清除搜索") { query = "" }
                            .accessibilityIdentifier("food.search.clear")
                    }
                }
            } else {
                Section {
                    ForEach(results, id: \.id) { document in
                        if let food = foods.first(where: { $0.id == document.id }) {
                            resultRow(food)
                        }
                    }
                } header: {
                    Text("可选食物（\(results.count) 项）")
                }
            }
        }
        .accessibilityIdentifier("food.selection.list")
        .navigationTitle("选择食物")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "名称、别名或拼音首字母")
        .searchFocused($searchIsFocused)
        .onSubmit(of: .search) { searchIsFocused = false }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .scrollDismissesKeyboard(.interactively)
        .task { loadCatalog() }
    }

    private var searchDocuments: [FoodSearchDocument] {
        let validFoods = foods.compactMap { try? $0.domainModel }
        let validIDs = Set(validFoods.map(\.id))
        let known = catalog?.searchDocuments(for: validFoods) ?? validFoods.map { food in
            FoodSearchDocument(id: food.id, name: food.name, aliases: [], englishName: "", pinyinInitials: [], catalogOrder: .max)
        }
        // Keep damaged local rows visible rather than silently dropping them. Their
        // current validation and write-boundary protection still decide saveability.
        let invalid = foods.compactMap { food -> FoodSearchDocument? in
            guard !validIDs.contains(food.id) else { return nil }
            return FoodSearchDocument(id: food.id, name: food.name, aliases: [], englishName: "", pinyinInitials: [], catalogOrder: .max)
        }
        return known + invalid
    }

    private func resultRow(_ food: PersistentFoodItem) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Button {
                select(food.id)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(food.name)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(sourceSummary(for: food))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if food.id == selectedFoodID {
                        Image(systemName: "checkmark")
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityValue(food.id == selectedFoodID ? "当前选择" : "")
            .accessibilityAddTraits(food.id == selectedFoodID ? .isSelected : [])
            .accessibilityIdentifier("food.select.\(food.id.uuidString)")

            Button {
                searchIsFocused = false
                onShowInformation(food.id)
            } label: {
                Label("查看资料", systemImage: "info.circle")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看\(food.name)的资料")
            .accessibilityIdentifier("food.info.\(food.id.uuidString)")
        }
    }

    private func sourceSummary(for food: PersistentFoodItem) -> String {
        if let domain = try? food.domainModel, let catalog, catalog.metadata(for: domain) != nil {
            return "CoFID \(catalog.source.datasetVersion) · 每 100 g"
        }
        return "本地记录 · 每 100 \(food.unit) · 来源资料未核实"
    }

    private func select(_ id: UUID?) {
        searchIsFocused = false
        onSelect(id)
        dismiss()
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
