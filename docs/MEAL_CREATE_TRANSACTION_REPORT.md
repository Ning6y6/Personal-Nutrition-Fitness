# A：新建餐食保存事务保护

日期：2026-10-23（Europe/London）。基线：`908f4c8`。分支：`fix/meal-create-transaction`。

## 批准范围与执行计划

用户批准架构评审中的 A：提取新建餐食正式保存入口，补充生产路径测试，隔离提交和回滚，防止重试重复记餐。保留正常界面、导航、原始重量输入、分项 UUID、取消保护和历史快照；不实施 B–E，不改菜谱、扫描等业务。事务隔离属于保护性行为修正，使用 fix 分支，不把它称为纯移动代码。

执行顺序为：独立基线验证→最小提取命令与表单请求状态→合成内存／文件库测试→全量 Core、App 单测→相关实际 UI 交互及前后截图→项目构建→独立提交与交付真机验收。主工作区原十个未提交文件另存完整 diff、index、SHA256 核对，不纳入本片。

## 实现与数据边界

- `MealCreateCommand` 使用独立 ModelContext 并关闭 autosave。新餐、分项及来源模板使用次数同次提交；未提交失败只回滚私有上下文，不保存或回滚页面共享上下文。
- 新建表单继续调用原有 MealDraftValidation 和 Core 的 MealLog／MealComponent 校验，所有分项有效才构造请求，不保存压缩后的有效子集。食品营养快照、顺序、未知纤维与已知零均保留。
- 一次表单呈现保留稳定餐食 ID，来源草稿已有 ID 直接沿用。每次保存先检查当前完整输入，普通失败后的改动不能重用旧请求；未变请求保留模板使用时间。相同 ID 与完整原始快照一致时只核对并刷新，不再次写入或增加计数。不同内容及已占用分项 ID 拒绝覆盖，不依赖唯一约束自动 upsert。
- 相关食品、餐食、分项、来源模板及其分项若在共享上下文中有未保存插入／修改／删除，明确拒绝；无关待保存对象保持原样。来源模板已经不存在仍允许保存餐食，模板存在但损坏／计数溢出则整餐拒绝，沿用原有规则。
- 区分未能确认保存与已提交但刷新失败。后一状态冻结已保存请求：原始输入未变时，即使食品后来变化或不可用，仍可核对原结果；原始输入此后改变则保留输入并明确说明这餐已保存，不新增另一餐。取消确认仅在此异常状态说明关闭不会撤销已保存餐，普通取消文案不变。
- MealEntryView 只替换新建保存调用及其请求状态；历史编辑仍走 MealEditCommand。Form／Section、焦点、键盘完成、选择页回退后按 ID 移除、原始文本和布局未移动。

未改 Core 源码、SwiftData 实体、冻结十二实体 V1、当前 V2、迁移、备份格式或数据库路径。未安装依赖、引入账号或云服务，不读取、卸载或清除真机数据；Bundle ID 保持 `com.ning6y6.ShiHeng`。工程仅注册四个新 Swift 文件到既有 App／单元测试目标。

## 验证记录

状态：本片实现、自动化回归及构建完成，等待用户真机验收。

| 门禁 | 结果／证据 |
| --- | --- |
| 改动前全部 App 单元 | 335 声明／835 执行通过，`/private/tmp/meal-create-a-baseline.xcresult` |
| Core 全量 | 183 声明／685 执行通过，`/private/tmp/meal-create-a-core.log` |
| 实现后首轮全部 App 单元 | R1 通过，`/private/tmp/meal-create-a-unit-R1.xcresult` |
| 最终 App 单元 | R3 359 声明／901 执行通过，0 失败／0 跳过，`/private/tmp/meal-create-a-unit-R3.xcresult` |
| 实际 UI 交互 | R4 深色 Pro Max 3/3、R5 浅色 17e 3/3、R6 AX5 餐食／模板 2/2，共 8/8 通过，0 失败／0 跳过，使用专用 QA 模拟器、虚构记录 |
| 前后原生截图 | 浅／深色 × 默认字号／AX5 四组目检，布局、标签、数值与间距一致；当前时钟的分钟值不同 |
| `./scripts/build-ios.sh` | 最终构建通过，`/private/tmp/meal-create-a-build-final.log`；构建产物 Bundle ID 核对为 `com.ning6y6.ShiHeng` |

新增 24 个单元测试声明／66 次执行，覆盖正式 form request→command 入口、150 g × 200 kcal／100 g＝300 kcal、完整字段、nil／0、模板单次计数、ID 冲突、相关及无关共享修改、失败后修改当前输入、真实合成只读文件库、关闭重开、提交后抛错／刷新失败重试。失败注入只存在测试闭包和合成文件库，不增加产品调试入口。

R2 全量中，未修改的 GoalHistoryMigrationTests.postMigrationReopenFailurePreservesSource 在预期 opener 之前因 storeChangedDuringInspection 被拦截（attempts 0，预期 2），两条断言未通过；不将其写作成功或环境权限错误。原迁移代码／断言不改，随后完整迁移套件隔离 6/6 通过，最终全量 R3 通过。提前拦截的偶发原因未定位，不因此改动源保护或迁移断言。失败证据保留于 `/private/tmp/meal-create-a-unit-R2.xcresult`，隔离结果位于 `/private/tmp/meal-create-a-migration-check.xcresult`。

真实 UI 回归覆盖新建、模板实际复用、最近吃过实际保存、今日更新、历史元信息编辑、个人卡更新后的旧快照／新餐、分项移除、取消／继续编辑、键盘完成及最大字号可达。扩充既有 ChineseMealSave 用例，明确保存“最近吃过”的新餐，并检查它不会再次增加模板次数；只清理本轮带唯一名称的样本，不触碰未知记录。

UI 结果分别保留于 `/private/tmp/meal-create-a-ui-main-R4.xcresult`、`/private/tmp/meal-create-a-ui-forms-R5.xcresult`、`/private/tmp/meal-create-a-ui-ax5-R6.xcresult`，结构化摘要均为 Passed。实际交互截图目检包含最近复用 125 g／164 kcal、个人卡新餐 30 g／135 kcal、移除空白项后原值及键盘完成。四组静态前后截图只用于版式比较，不替代交互测试。

185 个 Swift／工程文件的 SHA256 与最终全量测试和构建版本一致。原主工作区十个未提交路径的文件 SHA256、完整 diff 和 index 均保持不变。测试用模拟器恢复原浅色／large 字号及原开关机状态。没有未解决的环境权限阻塞；R2 既有迁移测试波动按上段单独记录，不能归为权限失败。

复现基础门禁（项目根目录；设备和临时输出可通过既有脚本环境变量指定）：

```sh
swift test --package-path Packages/FoodDecisionCore
./scripts/test-ios.sh -only-testing:FoodDecisionAssistantTests -parallel-testing-enabled NO -collect-test-diagnostics never
./scripts/build-ios.sh
```

定向 UI 共八个用例：NativeNavigationUITests 的 `testChineseMealSaveAndTemplateReusePreserveOriginalWeights`、`testInlineMealExpandEditReuseDeleteRecalculatesToday`、`testKeyboardDoneSurvivesMealTemplateNavigationCancellationAndGoalReopening`、`testMealComponentRemovalPreservesSurvivingRowsAndSavedSnapshot`、`testMealControlsReachableAtCurrentSystemTextSize`、`testTemplateControlsReachableAtCurrentSystemTextSize`；另有 MealSnapshotEditingUITests 的 `testMetadataOnlySavePreservesRiceSnapshotAfterNameAndTimeChange` 和 PersonalFoodUITests 的 `testEditingPersonalProteinCardPreservesOldMealsAndRefreshesNewSelections`。前两组分别为深色 Pro Max 和浅色 17e，控件可达两项使用另一台真实系统 AX5 设置的 17e。

本轮使用 SwiftUI Pro、SwiftData Pro、Swift Testing Pro、Swift Concurrency Pro；独立只读审查核查了事务、重试、已保存异常态、工程注册及前后截图。模拟器不能替代真机输入法、VoiceOver、外接键盘或既有未确认专项。

## 真机验收步骤

正常覆盖更新 App，保留原安装和数据。测试记录统一加“[验收A]”前缀；先截图一条已有餐食的分项、重量和热量，后续只回看这条旧记录。当前内置“熟长粒白米饭（无盐）”为每 100 g 131 kcal，显示取整与存储精度分开。

1. **空白新建**：记录“[验收A] 原餐”，选择上述米饭，输入 `100.0` g。保存后只有一条新餐，重量 100 g、热量 131 kcal，今日汇总增加相应数值。退出 App 再打开，记录仍在。
2. **最近吃过实际保存**：从刚才的原餐复用，改名“[验收A] 最近复用”，重量改成 50 g 并保存。新餐显示 66 kcal（原始值 65.5）；原餐仍为 100 g／131 kcal，两餐独立。
3. **模板复用**：从原餐保存一个“[验收A] 米饭模板”，记录保存前使用次数。从模板记餐，命名“[验收A] 模板餐”，改成 150 g。保存显示 197 kcal（原始值 196.5），模板次数仅加 1、默认量仍为 100 g；只打开模板后取消，次数不增加。
4. **分项和取消保护**：新建“[验收A] 分项测试”，选米饭并填 100 g，再添加空白项，保存应不可用；移除空白项后应能保存，最终只增加一餐。另开空白记录，输入 `100.0`，进入食品选择页再返回，检查原文和“完成”；取消→继续编辑应保留输入，明确放弃后没有新餐。再另开空白记录，只在唯一分项填重量，移除整项后取消，应直接关闭；不要同时改餐名或时间。
5. **历史编辑**：只编辑本轮“[验收A] 原餐”的名称或时间后保存，仍为 100 g／131 kcal；然后改成 200 g，保存显示 262 kcal，最近复用和模板餐不变。核对最初截图的那条旧记录仍未改变。
6. **个人食物卡**：用自己的已保存卡新建一条带前缀的餐食；保存和回看正常，旧餐快照保持。若需测试修改卡营养，另建一张带前缀的验收卡，避免改变日用食品。
7. **浅／深色和字号**：正常字号检查表单与原版一致，再把字号调大确认名称、重量、保存和取消可操作；结束后恢复原设置。

失败注入、私有事务回滚、提交后刷新失败、ID 冲突由合成单元／文件库测试验证；不要求为了真机验收制造磁盘写入失败或修改私有数据库。验收后只删除自己明确创建的前缀样本与模板，核对今日汇总和原有记录恢复预期。

## 下一步

先等待本片真机验收；不自动实施 B–E。通过后建议回到 OPT-15／16 菜谱批次方案审阅，重构后续按真实需要安排。
