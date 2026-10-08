import SwiftUI

struct NutritionCalendarView: View {
    var body: some View {
        ContentUnavailableView(
            "日历尚未开放",
            systemImage: AppTab.calendar.systemImage,
            description: Text("按日回顾将在日确认与历史目标等功能完成后开放。现在可在今日页查看全部历史餐食。")
        )
        .navigationTitle(AppTab.calendar.title)
    }
}
