import FoodDecisionCore
import SwiftData
import SwiftUI

struct MyFoodsView: View {
    @Query(sort: \PersistentFoodItem.name) private var foods: [PersistentFoodItem]
    @State private var identity: PersonalFoodIdentity?
    @State private var identityLoadFailed = false
    @State private var isCreatingFood = false
    @State private var foodToEdit: FoodItem?
    @State private var savedMessage: String?

    private var personalFoods: [FoodItem] {
        guard let identity else { return [] }
        return foods.compactMap { persistent in
            guard let food = try? persistent.domainModel, identity.isEditable(food) else { return nil }
            return food
        }
    }

    var body: some View {
        List {
            if let savedMessage {
                Section {
                    Text(savedMessage)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("myFoods.savedStatus")
                }
            }
            if identityLoadFailed {
                Section {
                    Label("暂时无法核实个人食物资料，未开放创建或编辑。", systemImage: "exclamationmark.triangle")
                    Button("重试载入", action: loadIdentity)
                        .accessibilityIdentifier("myFoods.retry")
                }
            } else if identity == nil {
                ProgressView("正在载入我的食物…")
            } else {
                Section {
                    Button("新建我的食物", systemImage: "plus") { isCreatingFood = true }
                        .accessibilityIdentifier("myFoods.create")
                } footer: {
                    Text("按每 100 g 标签值录入，记餐时按克使用。保存食物卡本身不增加摄入。")
                }

                if personalFoods.isEmpty {
                    ContentUnavailableView("还没有个人食物卡", systemImage: "fork.knife", description: Text("可为蜂蜜、蛋白粉等食品填写包装上的每 100 g 营养。"))
                } else {
                    Section("已保存的食物") {
                        ForEach(personalFoods) { food in
                            Button {
                                foodToEdit = food
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(food.name).foregroundStyle(Color.primary)
                                        Text("每 100 g · \(KcalDisplay.amount(food.nutrientsPer100Units.energyKcal))")
                                            .font(.subheadline)
                                            .foregroundStyle(Color.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                    Image(systemName: "chevron.forward")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(Color.secondary)
                                        .accessibilityHidden(true)
                                }
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("编辑个人食物卡")
                            .accessibilityIdentifier("myFoods.food.\(food.id.uuidString)")
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("myFoods.list")
        .navigationTitle("我的食物")
        .navigationBarTitleDisplayMode(.inline)
        .task { if identity == nil { loadIdentity() } }
        .sheet(isPresented: $isCreatingFood) {
            PersonalFoodEditorView { _ in
                savedMessage = "已加入食物库，尚未记录摄入。"
            }
        }
        .sheet(item: $foodToEdit) { food in
            PersonalFoodEditorView(food: food) { _ in
                savedMessage = "食物卡已更新，已有餐食的营养记录保持不变。"
            }
        }
    }

    private func loadIdentity() {
        do {
            identity = try PersonalFoodIdentity()
            identityLoadFailed = false
        } catch {
            identity = nil
            identityLoadFailed = true
        }
    }
}
