# 食衡模拟器验收测试报告

- 执行日期：2026-10-05（本机时区 Europe/London，BST）
- 性质：验收与报告；未修改生产源码、Schema、Xcode 工程或测试，未 commit / push
- 证据目录（构建产物，已被 `.gitignore` 的 `.build/` 规则忽略，不提交 Git）：`.build/acceptance-2026-10-05/`
  - `core-test.log`、`ios-test.log`、`build.log`
  - `shots/`：每个步骤的截图 `*.png` 与 UI 层级 `*.txt`，文件名前缀对应下文用例 ID

## 1. 仓库状态与本次读取的规范

| 项目 | 值 |
| --- | --- |
| HEAD | `4b220669d366805989f70cd5c3d4976f4c1dad9a`（`4b22066 fix: refresh local day and distinguish unrecorded intake`） |
| 分支 | `main`，与 `origin/main` 同步 |
| 工作区 | 开始与结束时 `git status` 均为 clean；本轮只新增本报告 |

完整阅读：AGENTS.md、README.md、docs/DECISIONS.md、docs/EXECUTION_STATUS.md、docs/OPTIMIZATION_EXECUTION_PLAN.md、docs/ROADMAP.md、docs/STORE_COMPATIBILITY.md；业务补读：MEAL_LOGGING_PLAN、MEAL_HISTORY_EDITING_PLAN、MEAL_REUSE_TEMPLATE_PLAN、APP_NAVIGATION_PLAN。

核对实现：ContentView、TodayDateContext、MealReadValidation、MealIntakeAvailability、TodayStatusCard、EmptyIntakeSummaryView、MealEntryView、MealDayWindow、VersionedSchemaV1，以及按调用关系补读的 GoalSettingsView、MealHistoryView（含 MealDetailView）、MealStartView、MealTemplateManagerView / EditorView、BackupManagementView、FoodDecisionAssistantApp、EnergyProgressRing、NutritionProgressRow、NutritionProgressPresentation、FibreSummaryRow、SeedFoodCatalog、NutritionDisplayPolicy；测试 `FoodDecisionAssistantTests/App/` 下三组及相关 GoalSaveCommand、StoreBootstrap、BackupService、NutritionDisplayPolicy 测试。

Skills：`~/.codex/skills` 下已安装 swiftui-pro、swiftdata-pro、swift-testing-pro、swift-concurrency-pro，均已读取其 SKILL.md，作为审查视角（无障碍、数据流、表单展示）参考；未安装新依赖。Xcode 自带 device-interaction 技能用于模拟器操作。

## 2. 功能进度摘要（已与代码核对）

**已完成（代码 + 自动化测试）**：12 项 CoFID 种子食物与幂等导入；称重(A)/标准份量(B)记录、多分项实时预览；每日目标空白初始、明确确认、独立事务保存；热量圆环与 minimum/budget/maximum 显示策略；未知纤维下界；历史详情、编辑、删除与重算；最近吃过与个人模板；JSON 全量备份、隔离恢复、二次确认切换、启动恢复页；S0–S2 加固；路径校验修复；日期刷新与空记录语义（限定切片）。

**仅数据契约 / 规划**：拍照估算（领域模型、持久化、离线 Fixture，无界面、无真实 AI）；四栏导航与热量日历（仅计划文档）。

**尚未完成（非本轮回归失败）**：整日覆盖确认、目标历史版本、有限查询/分页、食品搜索、自定义食物、菜谱批次、外食无秤流程、拍照确认界面与真实 AI、标签扫描、HealthKit、CloudKit、滚动平均。

冻结基线：12 实体 `VersionedSchemaV1`，本轮未改动。

## 3. 环境、工具能力与数据隔离

| 项目 | 实际值 |
| --- | --- |
| Xcode | 27.0（27A266a） |
| Swift | 6.4（swiftlang-6.4.0.34.1） |
| SDK | iOS 27.0 / iOS Simulator 27.0 |
| macOS | 26.6.2（xcresult 记录） |
| Scheme / Target | FoodDecisionAssistant / FoodDecisionAssistant、FoodDecisionAssistantTests（无 UI Testing target） |
| 产物 | ShiHeng.app，`CFBundleIdentifier=com.ning6y6.ShiHeng`，`CFBundleDisplayName=食衡`，`MinimumOSVersion=26.0`，0.1.0(1) |
| 主测试模拟器 | **新建专用** `ShiHeng-QA-18ProMax`（iPhone 18 Pro Max，iOS 27.0 / 24A434，UDID 070BF3CB-9ED8-4E69-B6F1-0342CC487ACF） |
| 补充小屏 | **新建专用** `ShiHeng-QA-17e`（iPhone 17e，iOS 27.0，UDID A51A953F-ED9A-4A24-875C-A1B18C61028C），仅安装启动截图 |

- 本机没有 iPhone 16 Pro Max 设备类型，也没有 iOS 26 运行时；以 iPhone 18 Pro Max（同为 440×956 pt 级大屏）替代。**iOS 26 最低版本兼容性待验**，未下载运行时。
- 未触碰已有模拟器（iPhone 17、18 Pro 等）中的数据；未连接或修改真机；未修改 Mac 日期/时区；未使用 `status_bar override`；未上传照片、未连接 AI/HealthKit/CloudKit。
- 全部业务数据为合成测试数据（餐名均带“测试”前缀）。测试目标 600 kcal / 蛋白 30 g / 碳水 80 g / 脂肪 20 g / 饱和脂肪 5 g / 纤维先留空后为 0，**为触发阈值刻意设低，不代表任何人的营养建议**。
- 数据库核对方式：将 QA 模拟器容器中的 `default.store*` 复制到 `.build/acceptance-2026-10-05/dbcopy/` 后 `sqlite3 -readonly` 查询；切换到恢复库后，对已非活动的原库只读打开计数。
- 唯一对 QA 模拟器全局设置的改动：`simctl ui appearance dark` 与 `content_size accessibility-extra-extra-extra-large`，测试后已恢复为 `light` / `large`。

**工具能力**：通过 Xcode `DeviceInteraction*` 工具实际完成点击、文字输入（含中文）、滑动、Home 键、截图与 UI 层级抓取；`simctl` 完成终止、启动、外观/字号切换。**不具备** VoiceOver 朗读与手势、减少动态效果开关、真实午夜/时区系统通知触发、真机操作能力。

> 注：首次 `simctl terminate` 后，交互工具把其跟踪的调试进程标为 `Crashed`。经核实：无 ShiHeng 崩溃报告，App 以新 pid 正常运行，数据完整。此为工具状态，不是 App 崩溃。

## 4. 自动化测试与构建

| 命令 | 结果 |
| --- | --- |
| `swift test --package-path Packages/FoodDecisionCore` | 通过。**98 个测试声明，325 次展开执行**（41 个参数化声明共 268 例 + 57 个普通测试），0 失败，0 跳过，0 警告 |
| `SHIHENG_SIMULATOR_DESTINATION='platform=iOS Simulator,id=070BF3CB-…' ./scripts/test-ios.sh -quiet -collect-test-diagnostics never` | 通过。**140 个测试声明，245 次执行**（38 个参数化声明共 143 次），0 失败，0 跳过，0 预期失败，runtimeWarnings 空 |
| `./scripts/build-ios.sh -quiet`（同一目的地） | 构建成功，日志无 warning / error |

- 设备：ShiHeng-QA-18ProMax（iPhone 18 Pro Max，iOS 27.0，24A434）；Xcode 并行测试使用其克隆体执行。
- xcresult：`/Users/ning6y6/Documents/ChatGPT/c-app/.build/DerivedData/Logs/Test/Test-FoodDecisionAssistant-2026.10.05_20-51-01-+0100.xcresult`
- 与历史基线（Core 98/325，iOS 140/245）数量一致；以上为本轮实际重跑结果。
- 未遇到沙盒、缓存权限或模拟器服务错误。

## 5. 验收表

验证层级：**UI** = 实际模拟器交互通过；**启动** = 安装启动通过；**单元** = 单元/集成测试通过；**静态** = 仅源码检查；**未执行** = 工具受限或环境缺失。真机验收本轮均未执行。

### A. 首次启动与空记录

| ID | 层级 | 步骤/数据 | 预期 | 实际 | 结果 | 证据 |
| --- | --- | --- | --- | --- | --- | --- |
| A01 | 启动+UI | 全新 QA 模拟器经 Xcode 安装运行 | 进入首页 | 进入“今日”首页 | 通过 | shots/A01-first-launch |
| A02 | UI+DB | 首启后、两次重启后查 FoodItem | 12 条且 ID 不重复，无猪肉 | 12/12 distinct；重启后仍 12/12 | 通过 | dbq 输出；C06-food-picker-menu |
| A03 | UI | 无餐食首页 | “今日尚未记录”，无圆环/绿色额度/达标 | 显示“今日尚未记录”及“尚未记录不代表摄入为 0”，无圆环 | 通过（见问题 #4 文案） | A01 |
| A04 | UI | 无目标时 | 不出现示例目标 | 无“查看已保存目标”区 | 通过 | A01 |
| A05 | UI | 保存目标后展开/收起“查看已保存目标” | 正常展开收起，显示已保存值，无进度 | 展开 6 项（纤维“未设置”），收起正常 | 通过 | A02-goal-disclosure-expanded、A03-goal-disclosure-collapsed |
| A06 | UI | 记录入口、扫描、待核对 | 记录可用；其余明确“开发中”且不可点 | 记录为 Button；扫描/待核对为 StaticText+“开发中” | 通过 | A01 |
| A07 | 启动 | iPhone 17e 专用模拟器安装启动 | 小屏首页正常 | 正常，文字未截断（见问题 #8 卡片宽度） | 通过 | A04-17e-first-launch |

### B. 每日目标

| ID | 层级 | 步骤/数据 | 预期 | 实际 | 结果 | 证据 |
| --- | --- | --- | --- | --- | --- | --- |
| B01 | UI | 新安装打开目标 | 全空、保存禁用 | 6 个字段均为 placeholder，保存 Disabled | 通过 | B01-goal-empty |
| B02 | UI | 输入 600/30/80/20/5，未确认 | 不能保存 | 保存 Disabled | 通过 | B02 |
| B03 | UI | 数字键盘点工具栏“完成” | 收起键盘、保留值 | 键盘收起，值保留 | 通过 | B03 |
| B04 | UI | 打开确认开关 | 可保存 | 保存可用 | 通过 | B04 |
| B05 | UI | 确认后修改脂肪字段 | 确认自动关闭，保存禁用 | 开关 value 0，保存 Disabled | 通过 | B05 |
| B06 | UI+DB | 重新确认并保存 | 写入一条目标；纤维留空为 nil | DB 1 行：600/30/80/20/5/NULL | 通过 | B08、dbq |
| B07 | UI | 重新打开目标 | 原值载入，确认关闭、保存禁用（设计行为） | 载入 600.0 等，开关 0，保存 Disabled | 通过（显示“600.0”见观察 O1） | B09 |
| B08 | UI+DB | 纤维填 0、确认后点“取消” | 数据库不变 | 纤维仍 NULL | 通过 | B10、B11、dbq |
| B09 | UI+DB | 纤维填 0 确认保存 | 明确 0 保留为 0 | 纤维 0.0，与 NULL 区分 | 通过 | B12、B13、dbq |
| B10 | 单元 | 非法输入、保存失败回滚、事务隔离、只读 SQLite 失败、nil/0 | 由 GoalSaveCommandTests、GoalInputDraftTests 覆盖 | 全部通过 | 单元通过 | xcresult |
| B11 | 未执行 | UI 层注入保存失败 | — | 无 UI 入口，不声称已操作 | 未执行 | — |

### C. 记录一餐与键盘

| ID | 层级 | 步骤/数据 | 预期 | 实际 | 结果 | 证据 |
| --- | --- | --- | --- | --- | --- | --- |
| C01 | UI | 空白记录初始 | 食物“请选择”、重量空、不能保存 | 符合，保存 Disabled | 通过 | C02-blank-entry |
| C02 | UI | 输入中文“测试·番茄炒蛋午餐”，点键盘“完成” | 收起键盘，不退出，文字保留 | 符合 | 通过 | C04、C05 |
| C03 | UI | 重量数字键盘“完成” | 收起 | 符合 | 通过 | B03、C17 等 |
| C04 | UI | 内容已滚动时向下拖入键盘区 | 交互式收起键盘 | 键盘收起，表单保留 | 通过 | C11、C12 |
| C05 | UI | **表单位于顶部时下拉** | 只收键盘或至少确认放弃 | **整个录入页被关闭，草稿丢失，无确认** | **失败**（问题 #1） | C08→C09 |
| C06 | UI | 西红柿 200 g + 鸡蛋 100 g | 159 kcal / 蛋白 13.6 / 碳水 6.0 / 脂肪 9.2 / 饱和 2.58 / 纤维 2.0（独立核算：14×2+131、0.5×2+12.6、3×2、0.1×2+9、0.03×2+2.52、1×2+0） | 159 / 13.6 / 6 / 9.2 / 2.6 / 2 g | 通过 | C19 |
| C07 | UI | 第二行未选食物时 | 预览仅含有效行并提示，不能保存 | 显示“当前仅预览已填有效分项…”，保存 Disabled | 通过 | C15 |
| C08 | UI | 加菜籽油 10 g，再左滑删除 | 248.9 kcal / 脂肪 19.2 / 饱和 3.2；删除后回到 159 | 符合 | 通过 | C23、C24、C25 |
| C09 | UI+DB | 保存 | 只新增 1 餐 2 分项，证据 A、完整 | DB 1 餐/2 分项，a/complete，159 kcal | 通过 | D01、dbq |
| C10 | UI+DB | 取消新增（草稿“测试·后台草稿”） | 不写库 | 取消后仍 4 餐 | 通过 | G03、dbq |
| C11 | UI | 食物列表 | 无猪肉菜品 | 12 项无猪肉。**不据此认定牛肉/鸡肉清真认证** | 通过 | C06 |

### D. 今日汇总与进度

| ID | 层级 | 步骤/数据 | 预期 | 实际 | 结果 | 证据 |
| --- | --- | --- | --- | --- | --- | --- |
| D01 | UI | 保存第 1 餐后 | 餐数、热量、宏量、圆环同步 | “1 餐计入合计”，159/600，各行正确 | 通过 | D01 |
| D02 | UI | 标题措辞 | “已记录摄入”，不宣称整日记全 | “今日已记录摄入”“N 餐计入合计” | 通过（见问题 #4：`.available` 说明文案未展示） | D01 |
| D03 | UI | 鸡胸 100 g 后蛋白 45.6/30 | 最低目标达成，非红色 | 绿色✓“已达最低目标” | 通过 | D04 |
| D04 | UI | 牛排 30 g+米饭 200 g → 625.4 kcal（104.2%） | 琥珀 + 图标 + 文字 | 琥珀圆环，“!”图标，“超出预算 25.4 kcal” | 通过 | D09 |
| D05 | UI | 米饭改 250 g → 690.9 kcal（115.2%） | 红 + 图标 + 文字 | 红圆环，三角图标，“明显超出预算 90.9 kcal” | 通过 | D11 |
| D06 | UI | 碳水 83.8/80（104.7%） | 琥珀 | 琥珀“超出预算 3.8 g” | 通过 | D11 |
| D07 | UI | 饱和脂肪 4.44/5（88.8%） | ≥80% 预警 | 琥珀“接近上限，剩余 0.6 g” | 通过 | D09 |
| D08 | UI | 饱和脂肪 7.05/5 | 超过 100% 为超量 | 红“已超出上限 2 g” | 通过 | D12 |
| D09 | 单元 | 79.9%/80%/恰好 100% 上限、预算 110% 边界 | NutritionDisplayPolicyTests 覆盖 | 通过 | 单元通过（UI 未精确构造 100%） | xcresult |
| D10 | UI | 牛排纤维未知 | “至少 X g + 未知分项”，无精确缺口、无达标色 | “至少 3 g / 1 个分项纤维未知…总量与缺口未确定”，问号图标 | 通过 | D08、D09 |
| D11 | UI | 颜色是否有文字/符号 | 均有 | 每行都有图标与文字，圆环有图标与文字 | 通过 | D09、D11 |
| D12 | 单元 | 无记录、仅 D/异常、实际零营养餐、合计溢出、删最后一餐 | MealIntakeAvailabilityTests（8 个声明）覆盖 | 通过；无 UI 入口构造 D/异常/溢出 | 单元通过 | xcresult |
| D13 | UI | 脂肪 23.95/20 | 显示与差额一致 | 显示“24 / 20 g，明显超出预算 3.9 g” | 低严重性显示问题（问题 #5） | D12 |

### E. 历史详情、编辑与删除

| ID | 层级 | 步骤/数据 | 预期 | 实际 | 结果 | 证据 |
| --- | --- | --- | --- | --- | --- | --- |
| E01 | UI | 首页进入“测试·牛排米饭”详情 | 分项、重量、时间、营养一致 | 30 g / 200 g，318.4 kcal 等一致 | 通过 | E01-detail |
| E02 | UI+DB | 编辑米饭为 999 后取消 | 不变 | DB 仍 200 g / 318.4 | 通过 | E03、E04 |
| E03 | UI+DB | 编辑为 250 g 保存 | 详情与今日重算，旧分项清理 | 383.9 kcal；今日 690.9；分项总数 5 不变 | 通过 | E06、D11 |
| E04 | UI+DB | 鸡胸肉移到 10 月 4 日 | 今日减少，历史保留 | 今日 542.9（2 餐）；历史 3 条含 4 Oct | 通过 | E11、E12、E13 |
| E05 | UI+DB | 再移回 10 月 5 日 | 今日恢复，无重复 | 690.9、3 餐；DB 3 行 3 distinct ID | 通过 | E15、E17 |
| E06 | UI+DB | 删除→确认框点外部取消 | 无变化 | 仍 4 餐，仍在详情页 | 通过 | E20、E21 |
| E07 | UI+DB | 确认删除 | 合计更新，分项级联删除 | 842.9→690.9；分项 7→5 | 通过 | E22 |
| E08 | UI+DB | 删除今日最后一餐 | 中性空态，无绿色 0 额度 | “今日尚未记录”，目标折叠，无圆环；DB 0 餐 0 分项 | 通过 | E25 |
| E09 | UI+DB | `simctl terminate` 后重启 | 数据一致 | 4 餐 842.9、目标 1、食物 12 | 通过 | E18、dbq |

### F. 最近吃过与个人模板

| ID | 层级 | 步骤/数据 | 预期 | 实际 | 结果 | 证据 |
| --- | --- | --- | --- | --- | --- | --- |
| F01 | UI+DB | 详情“保存为常用模板”并重命名 | 模板保存默认重量，useCount 0 | “测试模板·番茄炒蛋”，200/100 g，0 次 | 通过 | F02、F03、F04 |
| F02 | UI | 最近吃过复用 | 新草稿、当前时间、证据 B | 符合 | 通过 | F06 |
| F03 | UI+DB | 复用后改重量再取消 | 不新增，原餐不变，计数不变 | 3 餐，原 200/100，useCount 0 | 通过（取消前未单独截图确认 150 已输入，证据较弱） | F07 |
| F04 | UI+DB | 模板复用，西红柿改 150 g 保存 | 只影响新餐；计数 +1 | 新餐 152 kcal、B；模板默认仍 200/100；原餐 200/100；useCount 1 | 通过 | F09、dbq |
| F05 | UI+DB | 编辑模板：改名、鸡蛋默认 120 | 保存成功，已生成餐不变 | 名称加“改”、120 g；模板餐仍 150/100 | 通过 | F12–F14 |
| F06 | UI+DB | 左滑删除→点外部取消→再确认删除 | 取消无变化；删除后模板及分项清空，餐食保留 | 取消后仍 1；删除后模板 0、模板分项 0、餐食 4、分项 7 | 通过 | F15–F18 |
| F07 | UI（自动化计时） | 首页“记录一餐”→点模板→改 1 个重量→保存 | 记录耗时 | 约 11 秒（21:11:39.4→21:11:50，含约 4 秒固定等待），iPhone 18 Pro Max 模拟器、自动化工具操作 | 仅为自动化参考；**真机人工 30 秒验收未执行** | F08、F09 |

### G. 日期与生命周期

| ID | 层级 | 步骤/数据 | 预期 | 实际 | 结果 | 证据 |
| --- | --- | --- | --- | --- | --- | --- |
| G01 | UI | 昨日有餐、今日无餐的状态（E04 中途 + E25） | 正常状态，非数据丢失 | 历史保留 4 Oct 餐；今日按日界线汇总 | 通过 | E12、E13 |
| G02 | UI | 未保存表单 → Home 键后台 5 s → `simctl launch` 前台 | 同进程恢复，草稿保留，不重建导航 | pid 88493 不变；“测试·后台草稿”/豆腐/88 g 保留 | 通过 | G01–G03 |
| G03 | 单元 | MealDayWindowTests（11）：午夜、半开边界、London 23/25 h、向前/向后校时、时区变化、GMT/半小时偏移、非有限时间、不可变快照 | — | 全部通过 | 单元通过 | core-test.log |
| G04 | 单元 | TodayDateContextTests（9）：午夜唤醒不改餐、前后校时、同日重排程、时区、取消前后不发布、失败锁止、非法时间不当空日 | — | 全部通过 | 单元通过 | xcresult |
| G05 | 单元 | TodayMealSummaryTests（3）：跨午夜/回拨重组不改时间戳、新日中性空态+昨日保留、换时区不改存储时间 | — | 全部通过 | 单元通过 | xcresult |
| G06 | 未执行 | 真实跨午夜、系统时区/时钟变更通知的 UI 链路 | — | 未改 Mac 时钟，未用 status_bar 声称午夜刷新 | 未执行/待真机 | — |

注入时钟测试只证明领域与状态行为，不代替真实系统通知和跨午夜 UI 验收。

### H. 备份与恢复

| ID | 层级 | 步骤/数据 | 预期 | 实际 | 结果 | 证据 |
| --- | --- | --- | --- | --- | --- | --- |
| H01 | UI | 导出全量备份到模拟器“On My iPhone” | 成功提示，统计正确 | 27 条（目标 1、食物 12、餐 4、分项 7、模板 1、模板分项 2），“备份已导出” | 通过 | H03–H06 |
| H02 | 文件 | 检查导出 JSON | 结构化记录 | 39 KB，records 27 | 通过 | 文件位于 QA 模拟器 File Provider Storage |
| H03 | UI+文件 | 删除全部 4 餐后“验证备份恢复”，选择该 JSON | 独立库恢复，现用库不变 | 生成 `BackupVerification/5B48…/restored.store`，提示“现用数据未改变”；现库 0 餐，标记仍 defaultStore | 通过 | H07–H09 |
| H04 | UI | 切换二次确认→点外部取消 | 不切换 | 标记仍 defaultStore | 通过 | H10 |
| H05 | UI+文件 | 确认“使用恢复库” | 切换到恢复库，原库保留不合并 | 首页 4 餐 842.9；标记 restoredStore；原 default.store 仍 0 餐 | 通过 | H11 |
| H06 | UI+DB | 终止后重启 | 继续使用恢复库 | pid 89151，4 餐/7 分项/1 模板/12 食物/目标一致 | 通过 | H12 |
| H07 | 单元 | 损坏文件、符号链接、路径越界、标记损坏、发布失败、NaN、未保存改动阻止切换、恢复不污染现库 | StoreBootstrapTests、BackupServiceTests、BackupImportReaderTests、LocalStorePathValidatorTests 覆盖 | 通过 | 单元通过 | xcresult |
| H08 | 未执行 | 真机文件保护等级、真机文件选择 | — | 模拟器不报告保护等级 | 待真机 | — |

### I. 布局与无障碍

| ID | 层级 | 步骤/数据 | 预期 | 实际 | 结果 | 证据 |
| --- | --- | --- | --- | --- | --- | --- |
| I01 | UI | 浅色、默认字号全流程 | 正常 | 正常；顶部备份/目标按钮在安全区内 | 通过 | 全部 A–H 截图 |
| I02 | UI | 深色模式首页 | 可读，状态色有文字 | 可读；**卡片与背景同为黑色，失去分隔** | 部分通过（问题 #7） | I01-dark-home |
| I03 | UI | AX5 最大字号首页圆环 | 文字不重叠，可读 | **图标/数字压到圆环描边，“预算 60…”“明显超…”被截断** | **失败**（问题 #2） | I02-ax5-dark-home |
| I04 | UI | AX5 目标表单 | 不重叠、按钮可达 | 换行正常，取消/保存可达 | 通过 | I03-ax5-goal-form |
| I05 | UI | AX5 今日餐食列表 | 可读 | 可读但时间被拆成“9:11P / M”，名称每行 3 字 | 低严重性（问题 #3） | I04-ax5-home-lower |
| I06 | UI | 键盘遮挡 | 输入框可见、可收起 | 目标表单底部确认开关被键盘遮挡，收起后可操作；记录表单正常 | 通过 | B02、B03 |
| I07 | 静态（层级） | 可访问性标签 | 名称准确 | 圆环 label “今日热量”+完整 value；进度行合并朗读含状态文字。**目标字段 label 重复；记录表单餐名/重量输入只有 placeholder** | 部分（问题 #6），VoiceOver 未实测 | B01、C02 层级 txt |
| I08 | 未执行 | VoiceOver 朗读顺序与手势 | — | 工具不支持 | 待人工 | — |
| I09 | 静态 | 减少动态效果 | 不依赖动画表达状态 | 源码中 `reduceMotion` 时 animation 为 nil，状态由文字/图标表达；未实际开启开关 | 仅静态检查 | EnergyProgressRing.swift |
| I10 | 未执行 | iOS 26 运行时、iPhone 16 Pro Max 实机尺寸 | — | 环境缺失 | 兼容性待验 | — |

## 6. 发现的问题

| # | 严重性 | 标题 | 复现 | 实际 vs 预期 | 定位 | 原因 | 建议修复范围 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 中 | 有未保存修改时下拉会直接关闭录入表单，草稿丢失 | 记录一餐→空白记录→填餐名、选西红柿、输入 200→表单在顶部时从内容区向下大幅拖动 | 实际：sheet 关闭回到“记录一餐”起始页，草稿全部丢失、无确认；预期：有改动时阻止交互式关闭或要求确认 | `MealEntryView.swift` sheet 无 `interactiveDismissDisabled`；同模式见 `GoalSettingsView.swift`、`MealTemplateEditorView.swift`（静态） | **已证实**（实际复现 + 源码中三处均无该修饰符）。数据库未写入，无持久化损坏 | 仅 UI：有脏状态时 `interactiveDismissDisabled(isDirty)` 并在取消时确认；三处表单统一；补 UI 测试需另行批准 target |
| 2 | 中 | AX5 字号下热量圆环文字溢出、截断并与描边重叠 | 设置 → 字号 AX5（accessibility-extra-extra-extra-large）→ 首页有餐食状态 | 实际：预算与状态文字截断为“预算 60…”“明显超…”，图标/数字压线；预期：关键读数完整可读 | `TodayStatusCard.swift` 对圆环 `.frame(maxWidth: 180)`；`EnergyProgressRing.swift` 环内 VStack 文本随动态字体放大 | **已证实**（截图）；具体最佳布局方案未定 | 仅 UI：辅助字号下将状态文字移出圆环或改为环下方纵向布局，限制环内仅数字；不改 Core |
| 3 | 低 | AX 大字下今日/历史餐食行横排过挤 | 同上，滚动到“今日记录” | 时间被拆成“9:11P / M”，名称每行 2–3 字 | `MealHistoryView.swift` `MealSummaryRow` 固定 HStack | 已证实 | 在 `dynamicTypeSize.isAccessibilitySize` 时改纵向排列 |
| 4 | 低 | 空态标题与正文矛盾；正式状态说明未展示 | 无餐食首页 | 卡片同时显示“今日已记录摄入 / 0 餐计入合计”和“今日尚未记录”；`.available` 的“不代表当天所有摄入都已记录”文案从未出现 | `TodayStatusCard.swift` 固定渲染标题；`MealIntakeAvailability.explanation` 仅在空态视图中使用 | 已证实（源码 + 截图） | 文案：空态隐藏或改写标题；在已记录状态显示 availability.explanation |
| 5 | 低 | 摄入值与差额分别四舍五入导致不一致 | 4 餐后脂肪合计 23.95 g、预算 20 g | 显示“24 / 20 g，明显超出预算 3.9 g”（24−20≠3.9）；分类/颜色正确 | `NutritionProgressPresentation.formatted` 对 consumed 与 overage 独立格式化 | 已证实（DB 精确值 23.95，差 3.9499…） | 显示层：差额由已舍入值计算或统一舍入规则；补边界单元测试 |
| 6 | 低 | 输入框无障碍标签重复/缺失 | 查看 UI 层级 | 目标字段 label 为“热量 (kcal), 热量 (kcal)”；记录表单餐名、重量 TextField 仅有 placeholder，填值后 VoiceOver 可能只读数字 | `GoalSettingsView.goalField`（LabeledContent + accessibilityLabel 双重）；`MealEntryView` TextField 无 label | 层级已证实；**VoiceOver 实际朗读未验证** | 仅 UI 标签调整，并在真机 VoiceOver 复核 |
| 7 | 低 | 深色模式卡片无层次 | 深色模式首页 | 卡片 `.background` 与 `systemGroupedBackground` 均为黑色 | `ContentView`/`TodayStatusCard` 卡片背景 | 截图已证实 | 卡片改用 `secondarySystemGroupedBackground` 等分层色 |
| 8 | 低 | 今日状态卡在内容短时不满宽 | 空态首页（17e 明显） | 状态卡比其他卡窄 | `TodayStatusCard` 缺 `.frame(maxWidth: .infinity, alignment: .leading)` | 截图+源码 | 一行布局修饰符 |

**观察项（非缺陷 / 设计或环境相关）**

- O1：已保存目标载入为“600.0”格式，源于设计上的可往返 `String(Double)`；可考虑展示去掉多余 `.0`，属 UX 优化。
- O2：模拟器系统语言为英文，列表时间显示为“9:00 PM”“5 Oct 2026 at 9:04 PM”，滑动删除按钮为“Delete”；DatePicker 强制 zh_Hans_CN。中文系统真机需复核。
- O3：iOS 26+ 确认框以 popover 呈现，无独立“取消”按钮，点外部即取消；属系统行为。
- O4：12 项食物菜单在下半屏打开时需滚动菜单才能选到末项（鸡蛋），印证 OPT-12 搜索/选择器需求；不在本轮修复。
- O5：经 DatePicker 修改时间后秒数归零（21:04:xx→21:04:00），不影响日归属。

## 7. 待人工或真机验收

1. **真机覆盖更新**（相同 Bundle ID，不卸载）：启动进入首页、原餐食/目标/模板可见、强制退出重开、记录一餐正常。
2. **VoiceOver**：首页圆环朗读“今日热量，已摄入…，预算…，状态”；蛋白/碳水等行朗读含状态文字；目标字段是否重复朗读（问题 #6）；记录表单重量输入是否读出“重量”；朗读顺序与“开发中”卡片。
3. **减少动态效果**：设置→辅助功能→动态效果→减少动态效果，开启后增删餐食观察圆环不依赖动画且状态文字正确。
4. **跨午夜**：23:55 打开首页并保持前台，过 00:00 后观察是否变为“今日尚未记录”，昨日餐在历史中；另测一次 23:55 打开记录表单不保存，跨午夜后表单内容仍在。
5. **后台隔日**：晚上退后台，次日打开，检查今日中性空态与历史。
6. **时区/时钟**：在真机设置中改时区（如 London→Shanghai）再改回，确认今日归属重算、历史时间不变。
7. **常用餐 30 秒**：真机连续 5 次“记录一餐→模板→改一个重量→保存”，人工计时取中位数。
8. **备份**：真机导出到“文件”，再“验证备份恢复”、二次确认切换、重启核对；锁屏后的文件保护由真机验证。
9. **键盘与字体**：真机中文输入法候选栏下点“完成”、深色模式、最大辅助字体（复核问题 #1–#3）。
10. **iOS 26 设备或运行时**：最低支持版本的安装与基础流程。

## 8. 下一步建议（按路线与门禁排序，均未开始实施）

1. **补齐本轮验收**：由你完成第 7 节真机与 VoiceOver 项目，记录结果到 EXECUTION_STATUS。
2. **修复已证实缺陷（需你批准，建议独立 `fix/` 分支，不改 Schema、不改 Core 规则）**：
   - `fix/sheet-dismiss-guard`：问题 #1（优先，涉及草稿丢失）。
   - `fix/accessibility-layout`：问题 #2、#3、#6、#7、#8。
   - `fix/today-copy-rounding`：问题 #4、#5。
   每项修复后重跑 Core / iOS 测试与构建，并在模拟器与真机复测对应用例。
3. **再提请批准其余 S3**：OPT-10 整日确认、OPT-09 目标历史、OPT-11 剩余的有限查询/分页/10,000 餐性能、OPT-12 食品搜索；每项都需要对应批准，涉及新持久化结构时须先通过 S1 迁移门禁。
4. **S4 自定义食物、S5 菜谱批次**：在搜索交付、来源契约确认后按各自门禁推进。
5. **AI 拍照、标签扫描、HealthKit、CloudKit**：继续遵守 OPTIMIZATION_EXECUTION_PLAN 中“后续功能启用前的强制门禁”，本轮未触碰。

以上均为建议，**不是已经完成的工作**。

## 9. 测试残留

- QA 模拟器 `ShiHeng-QA-18ProMax`（现使用恢复库，含合成数据与 `BackupVerification` 目录、导出的 ShiHeng-backup.json）和 `ShiHeng-QA-17e`（已关机）均保留，便于复测；不需要时可在 Xcode 设备管理中删除。外观与字号已恢复为 light / large。
- 证据与数据库副本在 `.build/acceptance-2026-10-05/`，不提交 Git。
