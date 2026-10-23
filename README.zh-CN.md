[English](README.md) | [简体中文](README.zh-CN.md)

# 食衡 / Evenfare

食衡是我为日常称重记餐做的原生 iOS App，用来对照自己设定的每日营养目标。我已完成离线食品搜索、餐食历史、模板、个人食物卡和本地备份恢复，方便做饭和重复记餐。不需要账号；当前界面为简体中文。

## 当前可用功能

- **离线食品搜索**：内置 CoFID 2021 精选食品 357 项，可按中文名、别名、英文原名和已核对的拼音首字母搜索。
- **记餐与今日汇总**：一餐可添加多个食物分项，按克重预览营养，支持称重／包装数据或标准份量记录，并显示今日热量及营养进度。分项未填完整不能保存；当天没有记录不代表实际摄入为零。
- **历史查看与编辑**：查看、展开、编辑、删除和复用已有餐食；修改后重算今日汇总，同时保护每餐原有的营养依据。
- **最近吃过与常用模板**：从最近餐食或个人模板生成独立草稿；可新建、重命名、编辑模板及默认克重。
- **个人食物卡**：按标签每 100 g 的数值创建、编辑食物，再在记餐时选择。保存食物卡本身不增加摄入。热量、脂肪、饱和脂肪、碳水、糖、蛋白质和盐必填，纤维可保留未知。
- **目标历史**：每次保存追加版本，记录来源、确认时间和生效日期。默认明天生效，也可选今天或未来日期；同一生效日以最后确认的版本为准。无法恢复的过去目标明确保留为未知。
- **本地数据保护**：SwiftData 存储、未保存输入保护、版本化 JSON 导出、独立库验证恢复；当前数据库打不开时提供恢复页。

## 已知限制

食物卡、餐食和模板当前都按 **g** 使用。尚无支持每 100 ml、勺或份的数量模型，不能直接换算。个人卡暂未提供删除、归档或修订历史界面。

扫描和日历栏仍是占位页。拍照估算只有数据契约、持久化和离线 Fixture 提供方，尚未交付照片确认流程或接入真实 AI。标签 OCR、条码查询、HealthKit、CloudKit、账号和跨设备同步均未接入。菜谱批次、整日记录确认、完整日历／趋势和完整英文界面也尚未实现。历史查询还没有分页，不宣称具备大数据量性能保证。

## 架构与权衡

- **领域规则与界面分开。** [`FoodDecisionCore`](Packages/FoodDecisionCore) 保存模型、校验、营养计算、食品搜索和目标选版；App 负责 SwiftUI 表单、SwiftData 适配、保存命令和恢复。规则可以独立测试，代价是需要明确的持久化适配代码。
- **每餐保留营养快照。** 只改名称或时间不重算；改克重按原分项快照同比缩放；新增或更换食物才用当前数值。因此，修改个人卡不会改写旧餐。代价是重复保存数据，目录更新后过去的记录仍保持原样。详见[快照设计与验证](docs/OPT14A_SNAPSHOT_PROTECTION_REPORT.md)。
- **未知不能当零。** 纤维数据不全时显示覆盖情况和已知部分的小计（若有），不给出精确总量或目标缺口。其余七项必须有数值，源数据缺失不能静默补零；尚不支持所有营养字段任意缺失。
- **新餐独立保存。** 私有上下文将餐食和模板使用次数一起提交。未提交的失败只回滚本次上下文，保留其他草稿。稳定 ID 与完整内容比较使未修改请求的重试只核对已存结果；内容冲突则拒绝覆盖。已提交的餐食不会因刷新失败被撤销。代价是额外读取和重试状态管理；相关记录有未保存修改时会阻止保存。详见[事务设计、测试与失败案例](docs/MEAL_CREATE_TRANSACTION_REPORT.md)。
- **恢复先验证，再切换。** JSON 格式 2 也可读取格式 1。恢复检查版本、类型、ID 和关系，写入独立库，关闭重开并比较后，由用户确认切换。原库保留，不合并。代价是额外磁盘空间和一次确认。导出含个人数据及图片引用，不含图片字节；JSON 没有 App 层密码加密。详见[目标历史迁移与备份验证](docs/OPT09_GOAL_HISTORY_REPORT.md)及[恢复实现](FoodDecisionAssistant/Persistence/LocalStoreBackupService.swift)。

当前存储为 [Schema V2，版本 2.0.0](FoodDecisionAssistant/Persistence/VersionedSchemaV2.swift)：冻结的十二实体 V1 加一个目标版本实体，**共 13 个实体**。保留本地唯一约束，明确关闭 CloudKit；遇到未知历史结构，不猜测迁移或删库重建。Bundle ID 始终为 `com.ning6y6.ShiHeng`。

## 构建与运行

环境要求：Core 包需要 macOS 26 或以上；安装具备所需 iOS SDK／模拟器运行时的 Xcode，Swift tools 至少为 6.2。工程采用 Swift 6 语言模式，最低部署版本为 **iOS 26.0**。已记录的开发工具链为 **Xcode 27.0 / Apple Swift 6.4**，不代表所有支持的系统和设备组合都经过验证。

在仓库根目录打开工程：

```sh
open FoodDecisionAssistant.xcodeproj
```

选择共享 scheme **FoodDecisionAssistant** 和 iPhone 模拟器后运行。真机运行时，在 Xcode 选择自己的签名团队与设备。更新原安装以保留本地记录，不卸载或清库。构建产物名为 `ShiHeng.app`。

不指定某台模拟器、仅编译时运行：

```sh
SHIHENG_SIMULATOR_DESTINATION='generic/platform=iOS Simulator' ./scripts/build-ios.sh
```

脚本对模拟器构建关闭代码签名，不需要食品 API Key 或后端配置。

## 测试

领域测试可以独立运行：

```sh
swift test --package-path Packages/FoodDecisionCore
```

**App／UI 测试必须使用只含虚构数据的专用 QA iPhone 模拟器。** UI 测试直接启动普通 App，会创建、编辑和删除记录，部分目标版本和个人卡会在结束后保留。脚本不负责数据隔离；不指定设备时会自动选可用模拟器，并优先选已启动的设备。不要指向含个人记录的日常模拟器，也不要在真机上运行这些测试。

先列出模拟器，将 `QA_SIMULATOR_UDID` 替换为专用模拟器的 UUID，再执行：

```sh
xcrun simctl list devices available
export SHIHENG_SIMULATOR_DESTINATION='platform=iOS Simulator,id=QA_SIMULATOR_UDID'

./scripts/test-ios.sh -only-testing:FoodDecisionAssistantTests \
  -parallel-testing-enabled NO -collect-test-diagnostics never

./scripts/test-ios.sh -only-testing:FoodDecisionAssistantUITests \
  -parallel-testing-enabled NO -collect-test-diagnostics never
```

App 测试需要已安装的 iOS 模拟器运行时；UI 测试还需要 Mac 保持唤醒、模拟器界面可用。检查字号或外观的 UI 用例需要相应系统设置。模拟器通过不能代替真机、VoiceOver 或外接键盘验收。

## 食品数据与归属

随包目录是 **[CoFID 2021](https://www.gov.uk/government/publications/composition-of-foods-integrated-dataset-cofid) 的 357 项精选子集**，不是完整原始数据库，也不是品牌商品／条码库。目录版本为 `cofid-2021-zh-v1`，导入规则版本为 `food-import-cofid-2021-v1`。

[核对后的食品清单](data/food-catalog/cofid-2021-curation.json)与[导入脚本](scripts/import_cofid.py)核对官方 Excel 哈希、食品身份和计量基准。清单补充中文搜索词，食品条目仍区分生熟和部位；身份歧义、必需营养缺失的条目被隔离，原 12 项保留 ID 和数值。原始 Excel 不提交仓库。

- 热量和碳水保留 CoFID 口径，不套用 4/9/4 重算热量；碳水和糖按单糖当量表示，不能直接视为与包装标签相同。
- 痕量 `Tr` 仅在计算时近似为零；`N` 和空白表示无可靠数值。AOAC 纤维未知就保持未知，不用 NSP 替代。钠换算盐采用 `钠 mg / 1000 × 2.5`。
- 当前计餐只接受每 100 g 食品基准。品牌配方、实际烹调方式可能不同于通用条目；通用肉类数据不证明清真认证。App 用于记录营养和用户自定目标，不声称具有已验证的医学效果或食品安全保证。

Public Health England (2021). McCance and Widdowson’s The Composition of Foods Integrated Dataset (CoFID). Contains public sector information licensed under the [Open Government Licence v3.0](https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/).

完整清单、排除项、修改说明与来源依据见[目录审计](docs/OPT12_CATALOG_AUDIT.md)、[导入规则](docs/OPT12_FOOD_IMPORT_RULES.md)和[目录清单元数据](data/food-catalog/catalog-manifest-v1.json)。App 设置中也提供“数据来源与许可”页。

## 验证证据与后续计划

[最近一次代码改动的验证记录](docs/MEAL_CREATE_TRANSACTION_REPORT.md)日期为 **2026-10-23**，对应交付提交 `57ff859`：

| 测试范围 | 测试声明数 | 执行次数 |
| --- | ---: | ---: |
| FoodDecisionCore | 183 | 685 |
| App 单元测试 | 359 | 901 |
| 选定 UI 回归用例 | 8 | 8 |

声明数将每个参数化测试计为一个，执行次数分别计算各组输入；UI 数字仅涵盖选定用例。最终构建通过。报告保留了既有迁移测试的一次偶发失败及随后通过的隔离／全量重跑，原因尚未定位。以上是已有记录，**不是本次 README 整理重新执行的结果**。真机步骤和证据边界见对应报告；[个人食物卡验证](docs/OPT13_PERSONAL_FOOD_REPORT.md)另有记录。

下一项规划是菜谱批次与份量分配，之后是整日确认、有限历史查询及日历／趋势。照片确认、真实 AI、标签扫描和 HealthKit 分别留待后续，云同步只是更后面的考虑。更多方向见[路线图](docs/ROADMAP.md)，其中保留了历史阶段记录。后续任务需分别确定范围并验证；当前实现以本页的功能列表为准。
