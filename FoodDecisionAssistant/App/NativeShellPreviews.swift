import SwiftData
import SwiftUI

// Each preview owns an isolated, empty in-memory store. No preview accesses the
// physical-device store or creates fake scan/calendar business records.
#Preview("四栏 · 今日空态 · 浅色") {
    ContentView()
        .modelContainer(for: VersionedSchemaV1.models, inMemory: true)
        .preferredColorScheme(.light)
}

#Preview("四栏 · 今日空态 · 深色") {
    ContentView()
        .modelContainer(for: VersionedSchemaV1.models, inMemory: true)
        .preferredColorScheme(.dark)
}

#Preview("四栏 · 扫描未开放 · 浅色") {
    ContentView(initialTab: .scan)
        .modelContainer(for: VersionedSchemaV1.models, inMemory: true)
        .preferredColorScheme(.light)
}

#Preview("四栏 · 扫描未开放 · 深色") {
    ContentView(initialTab: .scan)
        .modelContainer(for: VersionedSchemaV1.models, inMemory: true)
        .preferredColorScheme(.dark)
}

#Preview("四栏 · 日历未开放 · 浅色") {
    ContentView(initialTab: .calendar)
        .modelContainer(for: VersionedSchemaV1.models, inMemory: true)
        .preferredColorScheme(.light)
}

#Preview("四栏 · 日历未开放 · 深色") {
    ContentView(initialTab: .calendar)
        .modelContainer(for: VersionedSchemaV1.models, inMemory: true)
        .preferredColorScheme(.dark)
}

#Preview("四栏 · 设置 · 浅色") {
    ContentView(initialTab: .settings)
        .modelContainer(for: VersionedSchemaV1.models, inMemory: true)
        .preferredColorScheme(.light)
}

#Preview("四栏 · 设置 · 深色") {
    ContentView(initialTab: .settings)
        .modelContainer(for: VersionedSchemaV1.models, inMemory: true)
        .preferredColorScheme(.dark)
}

#Preview("四栏 · 今日空态 · 最大辅助字体") {
    ContentView()
        .modelContainer(for: VersionedSchemaV1.models, inMemory: true)
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("四栏 · 设置 · 最大辅助字体") {
    ContentView(initialTab: .settings)
        .modelContainer(for: VersionedSchemaV1.models, inMemory: true)
        .environment(\.dynamicTypeSize, .accessibility5)
}
