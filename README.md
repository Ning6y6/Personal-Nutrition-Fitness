# 食衡 Evenfare

Calm precision for every bowl.

个人使用的原生 iOS 饮食、营养与训练平衡 App。第一阶段优先完成称重记录、拍照估算餐、动态目标、食品约束判断、营养标签扫描和 HealthKit 同步。

## 当前可用功能

- 主动输入并确认热量、碳水、脂肪预算和蛋白质目标；可选饱和脂肪上限、纤维目标留空即未设置，不自动应用示例或医疗阈值。保存失败回滚本事务并保留输入，不影响其他草稿。
- 从 12 项 CoFID 2021 个人种子食材中添加多个分项，按克重实时计算一餐营养。
- 以称重/包装数据（证据 A）或标准份量估算（证据 B）保存到 SwiftData。
- 今日热量环v2：预算内翡翠、超出叠加琥珀，最多两圈；达到2倍后文字保留实际倍数和差额。浅深色自动适配，最大辅助字体将数值移到圈外。无记录不是已确认0摄入。
- 蛋白质、纤维按最低目标显示，达标不报超量红灯；热量等按预算、饱和脂肪按上限提示。未设置、未知或非法值不会冒充已知0或正常进度。
- 纤维数据部分未知时显示已知小计及未知分项数；全未知和无记录分别提示，只有数据完整时计算精确目标缺口。历史未知值不被补成0。
- 查看全部历史餐食与营养快照，并编辑或删除记录；今日汇总会随修改立即重算。
- 从最近吃过或个人常用菜模板生成独立餐食草稿，只修改本次重量后保存。
- 从历史餐食另存常用模板，并新建、重命名、编辑默认克重或删除模板。
- 导出全部本地业务数据的版本化JSON，验证独立恢复库后经二次确认切换；保留原库，不合并或覆盖原库。
- 数据库无法打开时显示恢复页，允许重试或恢复已有JSON，不自动删库。
- 正式餐食执行严格数值和完整分项校验；旧异常记录与未确认草稿保留在历史中，不参与正式汇总，并显示提示。

拍照 AI、食品标签 OCR、HealthKit 和 CloudKit 尚未接入。复用与模板切片的落实和待完成真机验收见 [`docs/MEAL_REUSE_TEMPLATE_PLAN.md`](docs/MEAL_REUSE_TEMPLATE_PLAN.md)。

开发 skills、UI 采用范围和延后项见 [`docs/DEVELOPMENT_RESOURCES.md`](docs/DEVELOPMENT_RESOURCES.md)。

当前已批准执行S0–S2可靠性加固，先保护已有数据再收紧校验，见[优化执行清单](docs/OPTIMIZATION_EXECUTION_PLAN.md)及[实际执行状态](docs/EXECUTION_STATUS.md)。个人或一两位朋友各自本机使用，不启用云或共享数据；分支与交付规范见AGENTS.md。

S0–S2及UI-1已完成代码与自动化交付；Core108个测试声明/367次执行通过，16张原生卡片预览已检查，详见[UI-1交付证据](docs/UI1_DELIVERY_REPORT.md)。B-1显示名本地化已独立交付，最新App176个声明/397次执行及构建通过，详见[品牌交付证据](docs/B1_DELIVERY_REPORT.md)。图标合成与接入仍未完成。2026-10-08用户确认真机备份、恢复、文件保护及旧餐食、目标、模板、新增餐检查无问题；未提供的VoiceOver、跨午夜/时区和复用计时证据仍待验。其余S3–S5及四栏导航不自动启动。

后续开发优先级见 [`docs/ROADMAP.md`](docs/ROADMAP.md)，本次完整变更见 [`CHANGELOG.md`](CHANGELOG.md)。

## 当前技术栈

- Xcode 27、Swift 6、SwiftUI
- SwiftData（应用数据，VersionedSchema V1 已接入）
- HealthKit（尚未接入，须先在隔离测试餐完成更新与删除实验）
- 本地 Swift Package：`FoodDecisionCore`

## 独立 UI 调色原型

用户另行批准的 Flask 手机风格预览在 [`tools/ui-preview`](tools/ui-preview/README.md)。它提供实时配色、明暗主题、圆角/间距、热量状态和四页模拟交互，仅使用虚构数据；不是 iOS 模拟器，不改 SwiftData 或正式营养规则，不表示四栏导航、日历或扫描业务已实现。

运行 `.build/ui-preview-venv/bin/python tools/ui-preview/app.py` 后打开 <http://127.0.0.1:5058>。首次依赖安装、测试与设计 JSON 契约见工具说明。

## 本地验证

```bash
swift test --package-path Packages/FoodDecisionCore
./scripts/test-ios.sh
./scripts/build-ios.sh
```

脚本自动选择可用iPhone模拟器；可用`SHIHENG_SIMULATOR_DESTINATION='platform=iOS Simulator,id=<UUID>'`指定。已保护旧库可运行`./scripts/verify-protected-store.sh /absolute/private/sample-directory`，目录须包含default.store及其sidecar。探针只打开新工作副本；不要把个人备份或探针输出提交Git。备份不含图片字节、Key或签名资料，JSON未加密；NaN/无穷值仅保留原始JSON，不会强行写回SQLite。

Xcode失败后的诊断收集可能耗时很久；需要快速取得测试结果时可用`./scripts/test-ios.sh -parallel-testing-enabled NO -collect-test-diagnostics never`。当前冻结经真机磁盘哈希确认的12实体V1，早期9/10实体结构没有部署样本，不宣称自动迁移支持。详见[兼容与恢复契约](docs/STORE_COMPATIBILITY.md)。模拟器不报告iOS文件保护等级；用户已报告真机备份恢复及文件保护正常，相关证据与自动化分开记录，本轮没有重新操作真机数据。

主屏幕显示名已本地化：简体中文为 `食衡`，英文为 `Evenfare`。这不是完整界面翻译，界面暂仍为中文。内部产物名仍为 `ShiHeng`，应用标识始终为 `com.ning6y6.ShiHeng`。图标仍需按[素材说明](design/brand/README.md)在Icon Composer合成并接入。真机运行前需要在 Xcode 中选择已登录的开发团队；覆盖安装，不卸载以保留本地记录。
