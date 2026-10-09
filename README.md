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
- 今日 / 历史餐食可轻量就地展开食物与原营养快照，提供可见的编辑、复用及详情入口；每个列表同时只展开一项，不写入业务数据。
- 从最近吃过或个人常用菜模板生成独立餐食草稿，只修改本次重量后保存。
- 从历史餐食另存常用模板，并新建、重命名、编辑默认克重或删除模板。
- 导出全部本地业务数据的版本化JSON，验证独立恢复库后经二次确认切换；保留原库，不合并或覆盖原库。
- 数据库无法打开时显示恢复页，允许重试或恢复已有JSON，不自动删库。
- 正式餐食执行严格数值和完整分项校验；旧异常记录与未确认草稿保留在历史中，不参与正式汇总，并显示提示。
- 系统“今日、扫描、日历、设置”四栏，各自独立导航；目标与既有备份入口迁入设置，今日保留同一目标编辑流程的快捷入口。扫描 / 日历明确未开放，不代表业务已实现。

拍照 AI、食品标签 OCR、HealthKit 和 CloudKit 尚未接入。复用与模板切片的落实和待完成真机验收见 [`docs/MEAL_REUSE_TEMPLATE_PLAN.md`](docs/MEAL_REUSE_TEMPLATE_PLAN.md)。

开发 skills、UI 采用范围和延后项见 [`docs/DEVELOPMENT_RESOURCES.md`](docs/DEVELOPMENT_RESOURCES.md)。

当前已批准执行S0–S2可靠性加固，先保护已有数据再收紧校验，见[优化执行清单](docs/OPTIMIZATION_EXECUTION_PLAN.md)及[实际执行状态](docs/EXECUTION_STATUS.md)。个人或一两位朋友各自本机使用，不启用云或共享数据；分支与交付规范见AGENTS.md。

S0–S2及UI-1已完成代码与自动化交付；Core108个测试声明/367次执行通过，16张原生卡片预览已检查，详见[UI-1交付证据](docs/UI1_DELIVERY_REPORT.md)。B-1显示名本地化独立交付，详见[品牌交付证据](docs/B1_DELIVERY_REPORT.md)。图标工程及App177个声明/398次执行、Debug构建通过；用户本轮确认Normal / Dark / Tinted / Clear与Settings缩小显示正常，详见[图标交付证据](docs/B1_ICON_DELIVERY_REPORT.md)。Spotlight、中英文显示名与UI-1真机视觉专项仍待验。此前真机备份 / 恢复 / 文件保护和既有数据检查由用户确认；未提供的VO、跨午夜 / 时区和复用计时证据不宣称通过。

本轮另行批准原生整改 **UI-2A导航 / 设置迁移→UI-2B今日记录入口 / 原生表单→UI-2C轻量餐食展开**，已依次通过代码与适用功能门禁，不只交付底栏，也不等全部业务。UI-2A当轮Core108声明/367执行、App单元180声明/410执行及XCTest实际UI交互4/4通过，iOS合计184声明/414执行，零失败/跳过；10张整页原生PNG已检查，最终构建通过。该轮两条键盘frame警告保留历史，真机、VO与iOS26专项仍待验，见[原生UI交付证据](docs/NATIVE_UI_DELIVERY_REPORT.md)。完整计划见[NATIVE_UI_EXECUTION_PLAN](docs/NATIVE_UI_EXECUTION_PLAN.md)；食品搜索 / 日确认 / 目标历史等新业务及S4–S5未新增批准，不改Schema或已有保存保护。

后续开发优先级见 [`docs/ROADMAP.md`](docs/ROADMAP.md)，本次完整变更见 [`CHANGELOG.md`](CHANGELOG.md)。

UI-2B于2026-10-09通过适用门禁，独立提交`2b18a34`已推送任务分支与快进后的main：Core108/367，App单元181声明/432执行、实际UI交互10/10，iOS合计191声明/442执行，零失败 / 跳过；22张原生PNG检查和最终构建通过，8条未定位frame警告保留为该轮证据。今日默认采用安全区内带文字的底部系统记录按钮，保留原保存 / 草稿保护；合成视口及系统AX5专项的证据边界见[原生UI交付证据](docs/NATIVE_UI_DELIVERY_REPORT.md)。不宣称真机、VoiceOver、iOS26或真实单手 / 计时验收通过。

UI-2C于2026-10-09通过代码与适用功能门禁：Core108声明/367执行，完整R4 App189声明/465执行及实际UI15/15，合计204声明/480执行全部通过，零失败 / 跳过；最终构建成功，13条未定位Invalid frame dimension警告仍挂账。已检查R3的18张合成原生PNG（App源码与R4相同）及R4的4张实际操作截图，不冒称R4重看全部18张渲染。所有失败及低电量休眠污染保留历史，不作性能指标；本片按验证后独立提交规则以`feat/inline-meal-details`交付，实际提交 / 推送状态以Git记录为准。真机、VoiceOver、iOS26与未批准新业务仍未完成，见[原生UI交付证据](docs/NATIVE_UI_DELIVERY_REPORT.md)。

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

主屏幕显示名已本地化：简体中文为 `食衡`，英文为 `Evenfare`，真机两语言专项尚未报告。这不是完整界面翻译，界面暂仍为中文。内部产物名仍为 `ShiHeng`，应用标识始终为 `com.ning6y6.ShiHeng`。用户制作的`Evenfare.icon`已接入工程，产物`CFBundleIconName`为`Evenfare`；四种外观 / Settings缩小显示的用户验收与剩余专项见[图标交付证据](docs/B1_ICON_DELIVERY_REPORT.md)，不自动修改艺术源。真机运行前在Xcode选择已登录开发团队；覆盖安装，不卸载以保留本地记录。
