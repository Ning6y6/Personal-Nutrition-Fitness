# 食衡（ShiHeng）

个人使用的原生 iOS 饮食、营养与训练平衡 App。第一阶段优先完成称重记录、拍照估算餐、动态目标、食品约束判断、营养标签扫描和 HealthKit 同步。

## 当前可用功能

- 设置每日热量、三大营养素、饱和脂肪和纤维目标。
- 从 12 项 CoFID 2021 个人种子食材中添加多个分项，按克重实时计算一餐营养。
- 以称重/包装数据（证据 A）或标准份量估算（证据 B）保存到 SwiftData。
- 在今日页通过热量圆环查看进度，并查看六项营养目标差额和最近餐食。
- 查看全部历史餐食与营养快照，并编辑或删除记录；今日汇总会随修改立即重算。

拍照 AI、食品标签 OCR、HealthKit 和 CloudKit 尚未接入。历史编辑切片的落实与验收见 [`docs/MEAL_HISTORY_EDITING_PLAN.md`](docs/MEAL_HISTORY_EDITING_PLAN.md)。

开发 skills、UI 采用范围和延后项见 [`docs/DEVELOPMENT_RESOURCES.md`](docs/DEVELOPMENT_RESOURCES.md)。

后续开发优先级见 [`docs/ROADMAP.md`](docs/ROADMAP.md)，本次完整变更见 [`CHANGELOG.md`](CHANGELOG.md)。

## 当前技术栈

- Xcode 27、Swift 6、SwiftUI
- SwiftData（应用数据，VersionedSchema V1 已接入）
- HealthKit（第 1 周先完成更新与删除实验）
- 本地 Swift Package：`FoodDecisionCore`

## 本地验证

```bash
swift test --package-path Packages/FoodDecisionCore
./scripts/build-ios.sh
```

正式显示名称为 `食衡`，英文产品名为 `ShiHeng`，应用标识为 `com.ning6y6.ShiHeng`。真机运行前需要在 Xcode 中选择已登录的开发团队。
