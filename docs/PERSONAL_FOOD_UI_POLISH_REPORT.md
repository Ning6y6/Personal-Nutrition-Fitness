# 个人食物界面统一与键盘完成按钮排查

日期：2026-10-23（Europe/London）。基线：`5b67d2f`；分支：`fix/personal-food-ui-polish`。

## 授权与改动

用户已确认 OPT-13 真机功能验收通过，随后要求调整两处外观，并排查偶发的键盘“完成”消失。用户补充消失位置可能是“记一餐”，正在自行尝试复现；该反馈不是个人卡功能未验收。

- 个人卡保留 safeAreaInset 的真实底部空间及原焦点／收键盘动作，只移除全宽 `.background(.bar)`，将完成按钮改为系统 `.glass`。保留 large 尺寸，不自绘玻璃、不固定行高，避免回退成来源末行被覆盖。统一系统按钮外观，不声称已改成其他表单的 keyboard toolbar 实现或逐像素相同。
- “我的食物”已保存行单独使用 plain 按钮，标题明确 Color.primary（深色白／浅色黑），副标题及装饰箭头 Color.secondary。两行结构、分组、稳定 UUID、44 pt 最小点击区及编辑动作保持；整行可点，箭头不重复朗读。“新建我的食物”继续使用强调色。
- 没有更改食物数值、来源协议、历史快照、保存／取消保护、实体、迁移、备份或 Bundle ID。原主工作区 10 个未提交文件单独校验，仍不混入此提交。

Apple 原生能力参考：[GlassButtonStyle](https://developer.apple.com/documentation/swiftui/glassbuttonstyle)、[keyboard placement](https://developer.apple.com/documentation/swiftui/toolbaritemplacement/keyboard)。

## 完成按钮排查边界

静态核查：餐食／模板的 keyboard toolbar 仅在自身导航栈根部注册，进入食品选择／资料页时撤销，返回后应恢复；个人卡用自己的 FocusState 控制底部完成按钮；目标页的 keyboard toolbar 无条件注册。目前没有代码证据可把问题直接归因于父子工具栏抢占或系统 bug。

原来的测试通常先点完成再离开，未覆盖所有焦点生命周期。本次增加真实原生操作，任何“键盘仍在”的检查均要求唯一、ID 正确且实际可点击的完成按钮，并点击验证键盘关闭；继续检查原始输入，不能用截图或 AX 树替代操作。

| 场景 | 新检查 |
| --- | --- |
| 个人卡焦点 | 文字→数字连续切换；交互滚动收键盘再聚焦；分类选择；后台→前台；取消继续；放弃后重新新建 |
| 个人卡末行及列表 | 七项完整输入；长来源说明；保存后整行进入编辑；重开来源键盘；未改动取消不生成脏草稿；列表实际截图 |
| 餐食／模板 | 名称和重量；选择页 push／pop 后原 UUID 重量再次聚焦；取消继续后聚焦；关闭后新表单再次聚焦 |
| 目标 | 无效预算 `.`；继续编辑再聚焦；放弃重开仍为原预算或原空值 |

## 验证记录

状态：Core、全部 App 单元、相关实际交互及最终构建全部通过，等待用户对本片两处外观做真机复验。用户已确认 Mac 保持唤醒后完成有效重跑。没有把模拟器通过说成偶发消失已修复。

| 最终门禁 | 结果与证据 |
| --- | --- |
| Core 全量 | 183 声明／685 执行，exit 0，`/private/tmp/personal-food-polish-core.log` |
| 全部 App 单元 | 335 声明／835 执行通过；R9 同包另有 2 项 UI，结构化总计 337 声明／837 执行，失败 0、跳过 0，exit 0，`/private/tmp/personal-food-polish-main-R9.xcresult` |
| 记餐／模板／目标 | 完整 1/1，exit 0，`/private/tmp/personal-food-polish-forms-R8.xcresult`，包含 13 个键盘状态截图及实际收键盘操作 |
| 个人卡普通字号／深色 | 两个新用例 2/2，exit 0，R9 上述同包；文字→数字切换、滚动、分类、后台、取消继续、新建重开及长来源保存／编辑均完成 |
| 个人卡小屏 AX5／浅色 | 修正测试定位后完整 1/1，exit 0，`/private/tmp/personal-food-polish-small-R11.xcresult`；原文及全部完成可用性断言保留 |
| 构建 | R11 后 `./scripts/build-ios.sh` 最终复核 exit 0、BUILD SUCCEEDED，`/private/tmp/personal-food-polish-build-R12.log`；Bundle ID 核对为 com.ning6y6.ShiHeng |

共 3 个不同新 UI 用例、4 次完整有效运行，不重复计算早先失败重跑。实际设备为 iOS 27.0（24A434）的专用 iPhone 18 Pro Max 和 iPhone 17e 模拟器。R8 有既有 Invalid frame dimension 警告，R9／R11 结构化结果无 runtimeWarnings，不据此关闭旧问题。

最终列表截图已目检为白色标题、灰色副标题和箭头，整行点入编辑由实际用例验证。来源用例证明原文、完成点击、保存、重开及再聚焦；其中长来源截图未包含来源文字本身，不拿该截图证明长文字在键盘上方完整可见。测试定位修正后生产两文件一直未改变，Core／App 单元不因测试滚动助手调整而失效。

以下保留失败过程，不作为最终门禁通过的证据：

- Core 全量：183 声明／685 执行通过，exit 0，`/private/tmp/personal-food-polish-core.log`。
- R1 全部 App 单元：335 声明／835 执行通过；两项 UI 在真实点击的事件回执阶段超时，整包 exit 65。宿主 pmset 的多次 Sleep／Wake 与长停顿重合；录像和最终 AX 显示目标已经获得焦点，键盘和完成仍在，不能据此认定按钮消失，也不能把未执行步骤算通过。`/private/tmp/personal-food-polish-main-R1.xcresult` 保留。
- R2／R3：测试 action 被错误重复传给脚本，停留启动阶段，已仅中断精确匹配的本任务进程；不清理模拟器或用户数据。分别退出 143／75，不计业务验收。
- R4：恢复阶段 Runner 发生 signal kill，未进入表单断言；整包失败，不计验收。后续以正确单一 action、只在测试进程期间 caffeinate 防止宿主自动休眠重跑。
- R5：再次遭遇原生事件合成超时；pmset 证实 caffeinate -i 运行期间仍有 Sleep／Wake，不能仅因设置了防止空闲休眠就当作稳定环境。两项 UI 未通过；App 全量此次另有目标页预览的真实 sheet 转场等待条件失败，整包 exit 65，不把 R1 的全量单元通过冒充 R5 通过。详见 `/private/tmp/personal-food-polish-main-R5.xcresult`。
- R6：小屏 AX5 的文字→数字切换和实际完成点击已执行，但短内容拖动没有完成交互式收键盘，新增“键盘必须消失”断言失败，整包 exit 65。录像里完成始终可见；原找字段短滚动不能充当完整下拉收键盘手势。已只修测试为按当前真实 Form／键盘几何拖到键盘下缘，保留消失、重新聚焦与原文断言；修正后尚未实际重跑。
- R7：记餐优先用例在 AX 查询阶段超时，尚未获得可用的完整表单交互结论。`/private/tmp/personal-food-polish-forms-R7.xcresult` 保留。现有键盘 frame 警告也没有关闭。
- R10：稳定环境中的 AX5 在第一次连续 energy→fat 的准备滚动阶段失败；固定 148 pt 左右步长交替越过短输入框，截图证明完成仍在。仅新测试定位助手改为读取当前 frame／viewport 中点差、小步低速并停稳，最后一次也检查完整框可见；不以坐标点击替代输入或完成，不放宽用例时间／断言，失败会附几何记录。R11 用此助手完整通过；App 源未改。
- 完成 `./scripts/build-ios.sh`：exit 0、BUILD SUCCEEDED，通用 iOS Simulator 目标；日志 `/private/tmp/personal-food-polish-build-final.log`。修正测试手势后另执行 build-for-testing，exit 0、TEST BUILD SUCCEEDED，日志 `/private/tmp/personal-food-polish-build-tests-final.log`。两者不替代实际键盘交互。
- 对结果的高层读取因 TestReport 缓存写权限及一次自动审批超时受阻，改用无需该缓存写入的 xcresulttool legacy 只读接口成功读取失败摘要；不是业务代码失败或安全审查认定不安全。没有绕开未通过的测试。
- 三个专用 QA 模拟器已恢复为原先浅色、large；原本关闭的小屏 QA 已关闭，另两个保持启动状态。不卸载、不清库。

当前确定结论：本轮在稳定环境下已完成上述检查，未复现“键盘仍开而完成消失”；原因未确认，问题保持开放。静态路径推测、睡眠干扰、测试手势不足分别登记，不把它们当作用户真机问题的解释。原始超时／失败包及截图不删除。若用户复现，依具体入口、前几步操作和输入法继续定向取证，不通过修改未知生命周期猜测修复。

本轮隔离工作树为 `/private/tmp/shiheng-personal-food-polish`，产物为 `/private/tmp/personal-food-polish-derived`。`scripts/test-ios.sh` 本身已添加 test action；test-without-building 必须直接调用 xcodebuild，不能追加给该脚本。通过后按项目约定独立提交、推送任务分支并非破坏性快进 main；原 10 个未提交文件、index 和差异内容单独逐字节保护，不混入本片。

## 真机复验与下一步

1. 深色进入“我的食物”：已保存名字为白色、热量为灰色，右侧有箭头；浅色对应黑色／灰色。点击文字、箭头或行内空白均能进入原卡编辑。“新建”仍为绿色。
2. 个人卡名称、数字营养及最后来源说明分别点入：完成为独立系统玻璃按钮，没有全宽灰色块；能收键盘，来源输入不被覆盖，继续编辑保留原文。
3. 在“记一餐”重点重复：点名称／重量、从食品选择返回、取消后继续编辑、关掉后重开。如再次出现“键盘仍开但没有完成”，保留当时页面和前几步操作用于复现；不把正常收键盘后按钮消失算缺陷。
4. 小屏／大字号和后台返回分别检查。模拟器通过不能替代真机中文输入法、VoiceOver、外接键盘或 iOS 26 专项。

下一步先由用户复验本片两处外观；键盘偶发问题保留待复现，不冒称修复。之后可另批准制定菜谱批次 OPT-15／16 方案，不自动开始下一业务。
