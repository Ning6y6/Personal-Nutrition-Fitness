/// Stable, transient navigation identities. No tab selection is written to the store.
enum AppTab: String, CaseIterable, Hashable, Sendable {
    case today
    case scan
    case calendar
    case settings

    var title: String {
        switch self {
        case .today: "今日"
        case .scan: "扫描"
        case .calendar: "日历"
        case .settings: "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "house"
        case .scan: "viewfinder"
        case .calendar: "calendar"
        case .settings: "gearshape"
        }
    }
}
