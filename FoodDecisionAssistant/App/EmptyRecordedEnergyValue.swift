import SwiftUI

struct EmptyRecordedEnergyValue: View {
    var body: some View {
        VStack {
            Text("已记录")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("0")
                .font(.largeTitle.bold())
                .monospacedDigit()
            Text("kcal")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
