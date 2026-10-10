# OPT-09 目标历史交付报告

日期：2026-10-10。批准规则与实施范围见 [实施计划](OPT09_GOAL_HISTORY_PLAN.md)。本片仅交付目标历史，不开放日确认、完整日历、搜索、食物卡、扫描或真实 AI。

## 实际接手状态与文档滞后

接手时实际 `main` / `origin/main` 为 `27a2cb8`，比交接快照 `cbd095a` 多三个已提交改动：空日中性热量环、展开后的定位、展开过程中开始滚动。早先 `8603505` 与 Flask 候选 `cbd095a` 均在历史中；Flask 候选不代表原生移植批准。

本地记餐、营养汇总、餐食编辑删除重算、最近与模板、S0–S2、备份启动保护、日期及草稿保护、UI-1 / B-1 / UI-2A–C 已有代码。拍照估算仍只有契约、持久化与离线 Fixture。交接中的 Core108/367、App193/475、UI4/4、网页87/87是历史证据；本片未重跑网页测试。

原状态、路线图和执行清单仍将目标历史标为未批准/未完成，应以后续批准的文档同步纠正。本计划和本报告记录本次批准与实际交付，不覆盖待整理文件。品牌 README 的真机外观状态滞后于已确认记录，且尾部有 `x x`。

## 原工作区未提交改动

保留接手时的七个修改文件及一个未跟踪文件，不 stash、清理或纳入本片：

| 分类 | 文件 | 建议后续独立处理 |
| --- | --- | --- |
| 扫描入库/过敏原规划 | CHANGELOG.md；docs/APP_NAVIGATION_PLAN.md、DECISIONS.md、EXECUTION_STATUS.md、OPTIMIZATION_EXECUTION_PLAN.md、ROADMAP.md；未跟踪 docs/SCANNED_FOOD_LIBRARY_ALLERGEN_PLAN.md | 审核后单独 `docs/scanned-food-allergen-plan` 提交；仅规划不启动代码 |
| 品牌文档编辑 | design/brand/README.md | 确认清理 `x x` 并同步已确认验收状态，单独文档提交 |
| 本片之后的状态同步 | 上述进度文档中目标历史及较新 UI 修复记录 | 与原规划差异分开审阅，不在本片自动改写 |

## 实际实现

- 正式保存只追加 `PersistentGoalVersion`，旧 `PersistentGoalProfile` 不再被目标设置覆盖。版本包含完整营养快照、来源/说明、确认时间、生效民用日期、确认时区/日界、提交序号和规则版本。
- 默认明天，可选今天整日或未来；先按不晚于统计日的最大生效日期，再按同日最大序号选版。未来安排保留，补录使用餐食统计日；手机当地时区变更后刷新，今日目标与餐食共用日期窗口。
- 设置提供自行设定/用户提供参考依据，后者必须填写说明；来源不构成系统验证的医疗依据。只读历史列表和详情保留同日被替代版本，并明确首个已知版本前未知。
- 旧安装不生成历史；旧目标只作为今日兼容参考并提示来源/历史时间未知。异常或歧义旧目标保留，允许用户明确重新确认；未确认旧目标不用于历史读取。
- 独立关闭 autosave 的 MainActor 上下文单次提交；保存失败只回滚私有事务，不保存或丢弃其他页面草稿。稳定操作 ID 防重复；成功重试优先返回已有版本，陈旧基线/标识冲突/未提交的过期日期或变更时区拒绝写入。
- 日期、来源、说明及确认状态纳入草稿保护；修改撤销确认，取消可以继续或放弃，跨午夜不静默夹紧日期。

## 结构、迁移与恢复

冻结十二实体 V1 定义及哈希不变，V2(2.0.0)新增第十三个独立实体，明确 V1→V2 lightweight stage。未知结构拒绝；不声称支持未经真实样本验证的更早九/十实体结构。

元数据读取和 V1 逻辑导出均只打开受保护副本，因为系统框架的只读打开也可能修改 SHM。原 main/WAL/SHM 做流式 SHA 校验；候选迁移、释放容器、V2-only 重开、逐条比对和文件保护成功后，最后原子发布选择指针。任何失败不覆盖原库、既有选择或当前容器，不降低源字节变化门禁。

导出备份格式2 / Schema2.0.0，继续支持格式1 / Schema1.0.0的闭合组合。V1恢复历史为空；V2恢复保留 UUID、确认时间、生效日期、顺序、nil / 0和未知原始枚举；未知枚举仍可归档，正式目标读取明确拒绝。恢复建立独立候选，不合并或重确认旧版本。

Bundle ID仍为 `com.ning6y6.ShiHeng`，SwiftUI / Swift6 / SwiftData / FoodDecisionCore及本地唯一约束保留，无新增依赖、账号或云服务。

## 本轮实际验收

所有运行均使用仓库外测试产物和新建合成 QA 模拟器；未卸载真机 App、清库或读取未知用户数据。

| 验收 | 实际结果与证据 |
| --- | --- |
| Core全量 | `swift test --package-path Packages/FoodDecisionCore`：136声明 / 431执行通过；`/private/tmp/goal-history-core-R2.log` |
| 全部App单元测试 | 226声明 / 522执行，零失败/跳过；`/private/tmp/goal-history-app-R3.xcresult` |
| 目标历史原生交互 | 三项实际 XCTest通过：连续今天修改/明天安排/历史重开、来源及取消草稿、控件可达；`/private/tmp/goal-history-ui-R2.xcresult` |
| 最大辅助字号 | 设置前已确认 `accessibility-extra-extra-extra-large`；一项实际 XCTest通过，结束恢复large；`/private/tmp/goal-history-ui-AX5-R2.xcresult` |
| 既有目标表单交互回归 | 两项实际 XCTest通过：取消/继续/放弃保留原预算，以及可选项目明确0与留空重开仍区分；`/private/tmp/goal-history-legacy-ui-R1.xcresult` |
| 文件库备份恢复重复 | 四项×10＝40次实际执行，全部通过；`/private/tmp/goal-history-backup-repeat-R4.xcresult` |
| iOS合成旧安装冷启动 | 独立producer退出后固定样本→新App正常启动→退出→独立快照验证；旧15记录完全一致，仅新增12内置食品，历史0，精确V2哈希/选择正确，原三文件SHA不变；`/private/tmp/shiheng-cold-iOS-report-597A498B/verification-report.json` |
| 保护探针脚本（合成样本） | `./scripts/verify-protected-store.sh`编译及运行通过，15条记录导出/恢复/重开、启动/激活/重启一致；脚本自带Core全量复测通过；`/private/tmp/goal-history-probe-R1.log` |
| 要求的构建脚本 | `./scripts/build-ios.sh`通过、退出0；`/private/tmp/goal-history-build-R3.log` |

Core覆盖同日、未来、补录、未知、nil/0、时区/夏令时/不存在日期与非法版本。文件库及命令覆盖重复、真实保存失败、陈旧基线、标识冲突、共享草稿、迁移首次/重开失败、原选择保护、未知结构、源文件变化拒绝与恢复一致性。

## 已处理失败与保留限制

早期 App失败包括仍按12实体断言最新结构的旧测试，以及合成producer关闭时异步checkpoint影响被测源的偶发失败。前者更新最新断言并保留冻结V1断言；后者分离producer与被测源，以严格完整文件组快照建立fixture。保留先前失败证据；这不声称已定位所有框架关闭行为，生产源变化仍硬拒绝。

初次UI运行因键盘/动画idle等待取消，后以既有真实键盘交互方式修正测试助手，通过实际断言，未加入生产同步禁用或动画绕过。一次重复测试filter匹配0项、一次AX5设置因设备未启动失败，均不算验收；最终重复与AX5结果核对了实际非零执行数量。

默认沙盒的worktree写权限及CoreSimulator/cache服务访问问题通过授权环境执行解决，单独区别于断言失败。无依赖安装。构建仍有AppIntents元数据提取跳过提示；预览单元测试控制台仍有appearance/API警告。三项新UI及两项既有表单UI分别记录两次 `Invalid frame dimension (negative or non-finite)`，尚未定位；既有键盘布局警告未解决。

合成iOS库的独立macOS读取器记录Persistence框架build差异警告，但一次读取完整成功并精确核验记录和哈希。未提供真实保护库样本，未执行真机目标历史升级、真实跨午夜/时区、VoiceOver或iOS26专项；模拟器通过不能代替这些证据。

## Git交付

原实施提交 `73aab17` 在 `feat/goal-history` 保留。GitHub以GH007邮箱隐私策略拒绝首次推送；不公开私人邮箱、不修改全局Git设置、不重写原提交。SSH身份与公开GitHub用户ID核对后，在同一基线建立 `feat/goal-history-delivery`，用公开noreply邮箱提交。交付实现与已验收代码完全相同，仅本计划/报告补记交付路径；整合只接受快进，并逐文件核对原七个修改及未跟踪计划。
