# 食衡（ShiHeng）

个人使用的原生 iOS 饮食、营养与训练平衡 App。第一阶段优先完成称重记录、拍照估算餐、动态目标、食品约束判断、营养标签扫描和 HealthKit 同步。

## 当前可用功能

- 设置每日热量、三大营养素、饱和脂肪和纤维目标。
- 从 12 项 CoFID 2021 个人种子食材中添加多个分项，按克重实时计算一餐营养。
- 以称重/包装数据（证据 A）或标准份量估算（证据 B）保存到 SwiftData。
- 在今日页通过热量圆环查看进度，并查看六项营养目标差额和最近餐食。
- 查看全部历史餐食与营养快照，并编辑或删除记录；今日汇总会随修改立即重算。
- 从最近吃过或个人常用菜模板生成独立餐食草稿，只修改本次重量后保存。
- 从历史餐食另存常用模板，并新建、重命名、编辑默认克重或删除模板。
- 导出全部本地业务数据的版本化JSON，验证独立恢复库后经二次确认切换；保留原库，不合并或覆盖原库。
- 数据库无法打开时显示恢复页，允许重试或恢复已有JSON，不自动删库。

拍照 AI、食品标签 OCR、HealthKit 和 CloudKit 尚未接入。复用与模板切片的落实和待完成真机验收见 [`docs/MEAL_REUSE_TEMPLATE_PLAN.md`](docs/MEAL_REUSE_TEMPLATE_PLAN.md)。

开发 skills、UI 采用范围和延后项见 [`docs/DEVELOPMENT_RESOURCES.md`](docs/DEVELOPMENT_RESOURCES.md)。

当前已批准执行S0–S2可靠性加固，先保护已有数据再收紧校验，见[优化执行清单](docs/OPTIMIZATION_EXECUTION_PLAN.md)及[实际执行状态](docs/EXECUTION_STATUS.md)。个人或一两位朋友各自本机使用，不启用云或共享数据；分支与交付规范见AGENTS.md。

后续开发优先级见 [`docs/ROADMAP.md`](docs/ROADMAP.md)，本次完整变更见 [`CHANGELOG.md`](CHANGELOG.md)。

## 当前技术栈

- Xcode 27、Swift 6、SwiftUI
- SwiftData（应用数据，VersionedSchema V1 已接入）
- HealthKit（第 1 周先完成更新与删除实验）
- 本地 Swift Package：`FoodDecisionCore`

## 本地验证

```bash
swift test --package-path Packages/FoodDecisionCore
./scripts/test-ios.sh
./scripts/build-ios.sh
```

脚本自动选择可用iPhone模拟器；可用`SHIHENG_SIMULATOR_DESTINATION='platform=iOS Simulator,id=<UUID>'`指定。已保护旧库可运行`./scripts/verify-protected-store.sh /absolute/private/sample-directory`，目录须包含default.store及其sidecar。探针只打开新工作副本；不要把个人备份或探针输出提交Git。备份不含图片字节、Key或签名资料，JSON未加密；NaN/无穷值仅保留原始JSON，不会强行写回SQLite。

Xcode失败后的诊断收集可能耗时很久；需要快速取得测试结果时可用`./scripts/test-ios.sh -parallel-testing-enabled NO -collect-test-diagnostics never`。当前冻结经真机磁盘哈希确认的12实体V1，早期9/10实体结构没有部署样本，不宣称自动迁移支持。详见[兼容与恢复契约](docs/STORE_COMPATIBILITY.md)。模拟器不报告iOS文件保护等级；真机锁屏保护、文件选择和恢复操作仍需人工验收。

正式显示名称为 `食衡`，英文产品名为 `ShiHeng`，应用标识为 `com.ning6y6.ShiHeng`。真机运行前需要在 Xcode 中选择已登录的开发团队。
