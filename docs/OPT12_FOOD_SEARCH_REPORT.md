# OPT-12 食品搜索交付与验收记录

实施开始：2026-10-18；汇总交付：2026-10-19。实施分支 `feat/food-search`，基线 `6990010`。用户批准依据：[实施方案](OPT12_FOOD_SEARCH_PLAN.md)与[导入规则](OPT12_FOOD_IMPORT_RULES.md)，2026-10-18 明确要求按 goal 模式完成开发和验证。

**当前状态：代码和自动门禁已完成，等待用户真机、VoiceOver和连续五轮人工计时验收。** 这不表示OPT-12全部实际验收已通过。本报告随独立`feat/food-search`提交交付；提交与远端状态以Git记录及最终交接为准。

## 实现范围

- 随包本地目录357项真实食品（旧12＋新增345），以生料为主；212项原名明确raw／uncooked，其余按干品、原料、可食部和烹调状态保留。中文名、别名、英文原名及冻结拼音首字母可搜索。
- 餐食新建／编辑／复用与模板新建／编辑共用原生搜索选择页；选择按行UUID返回，只改发起行的食品引用。重量原文、标题、日期与原有草稿／错误／保存机制保留。
- 独立食物资料按钮与设置“数据来源与许可”，显示来源、版本、原编码、生熟／可食部分、署名、许可及本地整理说明。扩展营养原值只留公开目录资料，不新增医疗、清真或过敏原自动裁决。
- 新追加命令用专用autosave关闭上下文，一次原子保存；同ID冲突或同ID未保存本地草稿保留并提示，不靠唯一约束upsert；失败回滚新增集合，父表单草稿不提交、不回滚。
- 原V1十二实体、V2十三实体、迁移链、兼容哈希、备份格式、旧12种子源文件及Core现有领域模型保持逐字节一致。既有废弃种子函数保留，但新表单初始化不调用其共享保存／删除路径，新追加命令零删除。Bundle ID仍为`com.ning6y6.ShiHeng`；无依赖、账号、后端或联网搜索。

完整目录、字段规则与逐项对照见[目录审计](OPT12_CATALOG_AUDIT.md)。发布资源SHA-256为`dfa65f09417aca70f4a83306b4869b603524d466a88f4962f0eaf54e5e10d36d`。168项纤维未知保持nil；不得读成全部营养已知或已认证清真。

补源见[抽样报告](OPT12_SOURCE_SAMPLING.md)：SG FoodID实际取得3项原料／熟主食／熟菜详情；TFDA食品级查询受连接条件限制未取得。两者未正式导入，不把访问限制当成App代码失败，不将网页元数据日期当营养版本。

## 本轮验证

仅使用公开来源、新建合成文件库和专用QA模拟器；没有操作真机、私有数据库或个人备份，没有卸载或清库。原工作区9项未提交内容的字节、工作差异和暂存状态独立留存并在交付时再次比对。

原工作区待整理文档继续原样保留：CHANGELOG、design/brand/README、APP_NAVIGATION_PLAN、DECISIONS、EXECUTION_STATUS、OPTIMIZATION_EXECUTION_PLAN、ROADMAP，另有未跟踪APP_REVIEW_2026-10-11与SCANNED_FOOD_LIBRARY_ALLERGEN_PLAN。本片没有将它们纳入食品搜索提交，也没有把陈旧总进度改写后覆盖这些工作；本报告是OPT-12的独立最新证据。后续建议将既有原生UI／品牌交接整理为一组、扫描／过敏原的待批准规划另成一组，由用户审阅后再处理。

| 检查 | 实际结果 | 证据（临时，不入Git） |
| --- | --- | --- |
| Python导入规则 | 17/17通过；最终官方Excel --check逐字节重现通过 | `/private/tmp/opt12-import-rules-final.log`、`/private/tmp/opt12-catalog-reproduction-final.log` |
| Core全量R5 | 147声明／449展开执行通过 | `/private/tmp/opt12-core-full-R5.log` |
| App全量最终R4 | 278声明／676展开执行通过，零失败／跳过，xcresult运行时警告为空 | `/private/tmp/opt12-app-R4.xcresult` |
| 实际UI：搜索／草稿／资料／许可 R5 | 1/1通过，零失败／跳过；1条既有类别布局警告 | `/private/tmp/opt12-ui-search-R5.xcresult` |
| 实际UI：完整业务与今日防遮挡 R1 | 3/3通过，零失败／跳过；3条既有类别布局警告 | `/private/tmp/opt12-ui-workflows-R1.xcresult` |
| 小屏常规 R1 | 2/2通过，零失败／跳过；1条既有类别布局警告 | `/private/tmp/opt12-ui-small-R1.xcresult` |
| 小屏AX5／深色 最终R2 | 2/2通过，零失败／跳过；1条既有类别布局警告，设置已恢复 | `/private/tmp/opt12-ui-small-ax5-R2.xcresult` |
| 大屏AX5／深色 R1 | 2/2通过，零失败／跳过；2条既有类别布局警告，设置已恢复 | `/private/tmp/opt12-ui-main-ax5-R1.xcresult` |
| 最终构建 R1 | `./scripts/build-ios.sh`成功，退出0；Bundle ID及最终资源SHA核对通过 | `/private/tmp/opt12-build-final-R1.log` |

实际UI方法（使用原生界面与软件键盘，不注入编辑状态）：

- `testFoodSearchPreservesRawDraftRowsAndReadsSources`：大屏常规，中文／别名／英文／拼音、生熟分开、无结果与清查询、两行原文／明确选择／放弃、资料和许可。
- `testChineseMealSaveAndTemplateReusePreserveOriginalWeights`：大屏常规，新记餐、模板新建／复用／编辑、最近吃过及历史编辑保存回读，只清理本轮唯一标识的合成餐和模板。
- `testSettingsSaveRefreshesPreviouslyDisplayedTodayBudget`与`testTodayInlineExpansionAutomaticallyRevealsDetailsAboveEntryButton`：大屏常规，通过真实目标表单准备专用QA的有效预算，并在展开后无手动滑动验证底部操作未被遮挡。
- `testFoodInformationAndSourcesReachableAtCurrentSystemTextSize`：小屏常规及最大辅助字号／深色，当前选中、资料按钮44pt、原码／版本／基准、返回和来源许可可达。
- `testMealControlsReachableAtCurrentSystemTextSize`：小屏常规及大屏最大辅助字号／深色，原生选择、重量、真实完成键及继续／放弃。
- `testTemplateControlsReachableAtCurrentSystemTextSize`：小屏最大辅助字号／深色，模板选择、重量与完成键、继续／放弃。
- `testInlineActionsReachableAtCurrentSystemTextSize`：大屏最大辅助字号／深色，展开编辑／复用／详情均可点击，核对详情后只清理当次合成餐。

最终相关UI为上述8个方法、10次执行全部通过，零失败／跳过；没有执行整个UI target，不把定向结果写成全部UI套件通过。专用QA为iPhone18ProMax／iOS27 `0CCCFCD2-6450-4AAA-B2CC-C28E08C7AE47`，小屏iPhone17e／iOS27 `2274AD9A-D827-422E-80ED-C5597FC08952`；两者DerivedData独立。系统显示设置按设备单独记录、修改并读回恢复，不更改其他现有QA或真机。

目录最后两处拼音键校正不改变ID、营养和本轮米饭／番茄用例；搜索R5及小屏常规R1的目录资源为修订前a2d3fcc3…，如实保留。最终CoreR5加入两个真实错拼回归；后续完整业务流程、小屏AX5R2、全量App与最终构建使用最终dfa65f09…目录，不能将早轮资源冒充最终SHA。

截图已导出目检：常规两行原文、番茄原码与许可，小屏食品全名换行、独立资料入口及模板重量均可达；大屏AX5深色下展开三操作和200g原文截图已目检。小屏AX5的资料基准值由真实AX断言核对，命名PNG只拍到该行标题；长许可链接截图只显示已进入视口的首段，需继续滚动阅读，不能称整段同屏或已点开外链。模拟器AX树不等同VoiceOver朗读。

Core覆盖中文／别名／英文／拼音、宽字符／固定locale／多词AND、排序与同名本地食品的输入顺序无关性、原值未知状态及损坏来源字段阻断、完整指纹匹配。新增App文件库测试覆盖旧12／餐食快照／模板／目标保护、nil≠0、冲突、共享同ID草稿与删除、失败／重试、真实只读文件库、重开及V1／V2备份恢复。

## 失败轮次与诊断边界

- Core R1把原码误限定为三位后缀，合法11-1045被拒；修正为支持真实三／四位后缀，未截断或改码，R2／R3通过。该候选后来因食品品类含义不清被独立隔离，和编码校验不是同一个问题。
- App R1为278声明／676执行：3声明／10执行失败，其中8次旧预览用例在只有12项的初始化前提下断言零写入。现先准备完整目录再建立基线，保留全部数量／快照／未保存状态断言。另2个既有目标迁移故障用例未到预期注入点；单独运行该套6/6通过，初轮包没有足够错误类别，不能凭单独通过将其归为环境问题。
- App R2为277/278声明、675/676执行通过，剩余旧启动重开用例失败。检查后将该冷启动夹具改为producer存活时严格复制并验证三件套，再打开从未给producer访问的副本；另给迁移故障用例补安全枚举类别及候选检查阶段布尔诊断。未修改生产迁移、原库快照守卫或放宽断言。R3全部278声明／676执行通过；其后定点目录与排序调整触发最终全量复测，R4最终278声明／676执行再次通过。
- UI R1可见食品行的AX标识附在Other包装层，内部Button没有标识。修复组合节点的按钮语义，继续要求真实唯一可点击按钮，没有改用任意firstMatch。
- UI R2进入系统搜索成功，但系统UISearchField未显示自定义键盘toolbar；改用原生Search提交并明确接入收键盘动作，用例核对键盘消失、查询保留及结果不变。餐食／模板数字键盘“完成”保持原行为。
- UI R3在核对生熟米后使用了已滚出原生虚拟列表的旧元素引用；用例改为先保存已核实的熟米UUID字符串，再滚动核对生米，保留完整状态与唯一性断言。
- UI R4已走通生熟区分与无结果／清查询，但测试没有先退出iOS27的系统搜索模式，原生导航栏当时只有“关闭”搜索动作。用例按真实AX树先点系统“关闭”，再要求唯一原生“返回”；不把父表单“取消”当作返回。R5完整1/1通过；仍保留该轮旧类别布局警告。
- 最终独立审查补正11-879、11-878、14-159的拼音键、并使异常本地食品和其他本地食品同样以UUID稳定排序；不改任何食品营养或既有记录。
- UI仍观察到既有类别`Invalid frame dimension (negative or non-finite)`，在聚焦原表单名称键盘时出现；[历史报告](PROGRESS_INPUT_FIX_REPORT.md)已登记同类警告。本片没有定位根因或关闭该问题，不能写成零警告。Esc仍按[既有核查](ESC_KEYBOARD_REVIEW.md)留待确认。
- 小屏最大辅助字号／深色R1在设置入口滚动前失败：来源入口已被原生列表回收，用例没有设置页的明确容器定位。补上settings.form标识与真实容器白名单，不改视觉、业务或断言；R1模板通过但整组为1/2；修复后同两项R2全部2/2通过。
- 最后大屏显示专项初次准备时simctl返回unknown，守卫在修改前停止；核实专用QA为Shutdown，重新启动该设备后读回原值再继续。该次没有执行测试，不算代码失败或通过。
- 读取xcresult摘要、sysctl硬件信息时的沙盒限制已通过授权系统开发工具访问解决；这属于工具权限，和上述真实断言失败分别记录。

最终构建保留AppIntents未依赖的metadata extraction skipped提示；没有把它列为编译失败。全部App单元的xcresult运行时警告列表为空，不代表预览控制台appearance-transition、只读故障注入日志或实际UI键盘警告已经消失。无遗留环境门禁阻断。

复现门禁时，Core与导入规则使用已列命令；App单元完整target与各实际UI方法沿用方案第6.4节的脚本及明确QA destination，结果包每轮新编号。最终构建命令为：

```sh
SHIHENG_SIMULATOR_DESTINATION='platform=iOS Simulator,id=0CCCFCD2-6450-4AAA-B2CC-C28E08C7AE47' SHIHENG_DERIVED_DATA_PATH='/private/tmp/opt12-derived-data' ./scripts/build-ios.sh
```

两台QA最终均读回`large/light`。大屏恢复记录`/private/tmp/opt12-main-ax-preferences.json`，小屏恢复记录`/private/tmp/opt12-ui-small-ax5-R2-prefs.log`。最终构建随包资源SHA为上列dfa65f09…，Bundle ID准确为`com.ning6y6.ShiHeng`。没有安装任何依赖、联网搜索服务或数据库迁移；静态搜索路径为本地资源加SwiftData，未把代码只读核对冒充真机断网操作。

## 搜索性能观察

Apple M5 Pro／macOS26.6.2，现有本地Core包Swift release构建，357个真实食品值投影；10个查询各10轮，预热后100样本：新进程首次目录载入约13.42ms（操作系统文件缓存不受控），过滤P50约2.69ms、P95约3.08ms、最大约3.36ms。证据`/private/tmp/opt12-search-benchmark-R3.log`，临时独立harness在`/private/tmp/opt12-search-benchmark/`。这是Mac上的领域搜索测量，**不是iPhone UI响应、冷启动整App或人工录入计时**，不据此宣称真机达到毫秒指标。

## 用户实际验收与下一步

以下必须由真实交互完成并反馈，模拟器／截图不能代替真机VoiceOver和人工计时；验收细节见已批准方案第7节。真机保存使用当次真实餐；连续五轮计时可在专用QA用同一合成模板完成，保留全部原始时长。

1. 覆盖安装现有App，不卸载／清库。打开今日与设置确认旧餐、目标历史、模板仍在；进入记录一餐搜索番茄／西红柿、鸡胸肉／jxr、米，区分生料与熟食，先返回不保存。
2. 两行分别保留`100.0`和`.`，从第二行查询／看资料／返回，确认第一行和所有原文不变；选择只改第二行。非法重量仍不能保存，明确放弃不新增餐食。
3. 用当次真实餐完成正常搜索选食物／克重／保存，详情与今日汇总一致；模板与最近吃过复用仍能修改重量、保存和回读。无需为验收删除真实记录。
4. 浅深色及最大辅助字号检查选择、资料、返回、键盘操作均可达；开启真实VoiceOver完成选择／取消，并听到名称、状态和当前选择。断网搜索仍应可用，来源页可阅读署名与许可说明。
5. 预先固定连续五轮模板复用，从今日“记录一餐”到保存返回且汇总刷新，所有取消／纠错／重试计入该轮；未完成轮次不删除或补成功样本，五轮均完成后中位≤30秒，保留五个原始时长。XCTest用例耗时不算人工计时。

本片用户验收通过后，下一建议业务切片为OPT-13个人食物卡／来源修订的具体方案：让找不到的包装食品或自用条目可人工登记。它与OPT-14历史快照编辑边界有关，需要对应批准；不自动实现日确认、菜谱批次、扫描、真实AI或完整日历。
