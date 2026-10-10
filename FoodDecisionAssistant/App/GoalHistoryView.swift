import FoodDecisionCore
import SwiftData
import SwiftUI

/// Read-only goal versions. No historical date editor or backfilling belongs in this slice.
struct GoalHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var snapshot: GoalHistorySnapshot?
    @State private var today: GoalDay?
    @State private var hasReadError = false

    private var versions: [GoalVersion] {
        (snapshot?.versions ?? []).sorted {
            if $0.effectiveDay != $1.effectiveDay { return $0.effectiveDay > $1.effectiveDay }
            return $0.commitSequence > $1.commitSequence
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if hasReadError {
                    Section {
                        Label("目标历史暂不可用", systemImage: "exclamationmark.triangle")
                        Text("无法安全读取目标版本。原数据保留，未按未知或空值替代。")
                        Button("重试读取", action: reload)
                    }
                } else if let snapshot {
                    Section {
                        if snapshot.legacyNeedsConfirmation {
                            Label("旧目标需重新确认", systemImage: "exclamationmark.triangle")
                            Text("旧数据含无效值或存在歧义，原记录保留。请到预算与目标页明确填写并确认新版本。")
                        } else if snapshot.hasLegacy {
                            Text("旧安装只保留当前目标，其来源和过去生效时间未知。")
                        }
                        if versions.isEmpty {
                            Text("尚无已确认的目标版本")
                                .font(.headline)
                        }
                        Text("首个已知版本之前的目标未知，不能用当前目标还原。每次修改保留原版本；同日以最后确认为准。")
                            .font(.footnote)
                    }
                    if !versions.isEmpty {
                        Section("已确认版本") {
                            ForEach(versions) { version in
                                NavigationLink(value: version.id) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("\(GoalVersionDetailView.dayText(version.effectiveDay)) 生效")
                                            .font(.headline)
                                        Text("热量预算 \(version.profile.energyKcal.formatted()) kcal")
                                        Text(status(for: version))
                                            .font(.subheadline)
                                        Text("\(GoalVersionDetailView.sourceTitle(version.source)) · \(version.confirmedAt.formatted(date: .abbreviated, time: .shortened)) 确认")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                        if let sourceNote = version.sourceNote {
                                            Text(sourceNote)
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .fixedSize(horizontal: false, vertical: true)
                                }
                                .accessibilityIdentifier("goalHistory.row.\(version.id.uuidString)")
                            }
                        }
                    }
                }
            }
            .accessibilityIdentifier("goalHistory.list")
            .navigationTitle("目标历史")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { id in
                if let version = snapshot?.versions.first(where: { $0.id == id }) {
                    GoalVersionDetailView(version: version, status: status(for: version))
                } else {
                    ContentUnavailableView("此版本暂不可用", systemImage: "exclamationmark.triangle", description: Text("请返回并重新读取目标历史。"))
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .task { reload() }
            .onChange(of: scenePhase) { if scenePhase == .active { reload() } }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in reload() }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemClockDidChange).receive(on: RunLoop.main)) { _ in reload() }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange).receive(on: RunLoop.main)) { _ in reload() }
        }
    }

    private func status(for version: GoalVersion) -> String {
        if versions.contains(where: { $0.effectiveDay == version.effectiveDay && $0.commitSequence > version.commitSequence }) {
            return "同日被后续确认替代"
        }
        if snapshot?.selected?.id == version.id { return "今日生效" }
        if let today, version.effectiveDay > today { return "未来安排" }
        return "历史版本"
    }

    private func reload() {
        do {
            let day = try GoalDay(containing: .now, timeZoneIdentifier: TimeZone.current.identifier)
            snapshot = try GoalHistoryReader.read(container: modelContext.container, day: day, allowLegacyCurrent: true)
            today = day
            hasReadError = false
        } catch {
            snapshot = nil
            hasReadError = true
        }
    }
}
