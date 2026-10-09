# 进度反馈与重量输入修复

日期：2026-10-09。原生任务分支：`fix/progress-and-weight-input`。

## 授权与边界

依据用户的四张真机截图，修复普通剩余状态像加载的图标、预填重量首次聚焦的光标位置，以及超额圆环末端不易分辨的问题。水位效果另外在 Flask 原型探索，不替换原生热量环，也不将旧网页的绿 / 黄 / 红策略移入 App。

保留 Bundle ID、十二实体冻结 V1、本地唯一约束、原始重量字符串、营养计算、证据与覆盖状态、保存 / 取消 / 草稿保护事务。没有新增食品搜索、日级确认、扫描、AI、健康阈值或第三方依赖。没有读取、清除、卸载或改写真机数据。

## 实现

| 用户反馈 | 实际修改 | 保持不变 |
| --- | --- | --- |
| 普通剩余图标像转圈 / 报错 | 下限未达用 `arrow.up.circle`，预算内用 `chart.pie`，上限内用 `arrow.left.and.right.circle` | 已达标、超额、硬约束与缺失数据仍各自表达；不改颜色或分类阈值 |
| 预填重量的光标在左边 | 共用 `WeightTextField`，通过原生 `TextSelection(insertionPoint:)` 在新聚焦会话移到当前字符串末尾；失焦清理选择 | 后续手动移动、局部插入、软件键盘、完成按钮及非法原始草稿继续使用原生行为 |
| 第二圈末端不清楚 | 端点直径由 16 pt 改为 20 pt，增加 2 pt 浅深色自适应描边与轻阴影；出现超额圈时只突出当前末端，不同时突出被覆盖的第一圈末端 | 同一顺时针几何、两圈饱和、实际超出数值、翡翠 / 琥珀语义及辅助字号圈外数字 |

`WeightTextField` 同时用于记餐 / 编辑餐食与常用模板的重量字段；名称和目标输入没有随本片改焦点策略。新文件已加入现有 Xcode 工程，没有重建工程。

## 文件

- `FoodDecisionAssistant/App/WeightTextField.swift`、`MealEntryView.swift`、`MealTemplateEditorView.swift`：原生重量光标修复。
- `FoodDecisionAssistant/App/NutritionProgressPresentation.swift`：三种普通剩余图标。
- `FoodDecisionAssistant/App/DesignTokens.swift`、`EnergyRingArc.swift`、`EnergyRingEndpoint.swift`、`EnergyProgressRing.swift`：可分辨的环末端及浅 / 深 / AX5 原生预览。
- `FoodDecisionAssistantTests/App/EnergyRingPresentationTests.swift`、`NutritionProgressPresentationTests.swift`：语义和几何断言。
- `FoodDecisionAssistantUITests/NativeNavigationUITests.swift`：两项新增真实键盘用例，不用全选或直接写库掩盖初始光标位置。
- `FoodDecisionAssistant.xcodeproj/project.pbxproj`：注册共用字段。

## 验证记录

- 环境为 Xcode 27、iOS 27、专用 iPhone 18 Pro Max 模拟器 `ShiHeng-NativeUI-QA`。全部交互使用虚构餐食，证据位于忽略的 `.build`，不提交截图、数据库、健康数据或 xcresult。
- Core 最新执行：108 个声明 / 367 次展开执行通过；`.build/progress-input-core-2026-10-09.log`。Core 源码未改。
- 首次构建退出 0；`.build/progress-input-build-2026-10-09.log`。此记录不代替最后源码构建。
- R1：两项真实光标 UI 用例 2/2 通过，命令退出 0；`.build/progress-input-caret-r1-2026-10-09.xcresult`。验证普通首次聚焦后 500 → 删除 → 50、保存后的 50 g，以及模板放弃后原餐仍 500 g。四张操作附件已导出。存在两条既有类别的 `Invalid frame dimension (negative or non-finite)` 警告，不写成零警告。
- R1 测试已在 17:07:58 结束，随后 Xcode 等待 `simctl diagnose --timeout=600` 归档；这是测试后诊断耗时，不是键盘卡死。保留完整结果，下一轮通过公开 `-collect-test-diagnostics never` 跳过冗长诊断，不关闭 UI 同步或减少业务断言。
- R2：全量 App 单元测试 193 个声明 / 475 次展开执行通过；定向 UI 测试 4/4 通过、零失败、零跳过，命令退出 0。结果为 `.build/progress-input-final-r2-2026-10-09.xcresult`。两项加强光标用例覆盖同一焦点内左移 / 插入 / 删除、不同长度重新聚焦、保存与取消确认；另外两项验证非法重量仍受草稿保护。结果包含四条上述类别的 frame 运行时警告，未定位或宣称修复。
- R2 渲染检查发现第一圈起点与超额圈末端同时描边，产生两个醒目标记。随后仅调整圆环端点显示条件，重量输入与 UI 测试代码不变。
- R3：在上述端点调整后重跑全量 App 单元测试，193 个声明 / 475 次展开执行通过，零失败、零跳过，命令退出 0；`.build/progress-input-ring-r3-2026-10-09.xcresult`。此轮没有 UI 键盘交互，其零运行时警告不能用于关闭 R2 的四条键盘警告。
- 已查看 R3 的八张实际 SwiftUI 渲染：预算内、超额、超过两倍预算分别覆盖浅 / 深色；超过两倍预算另覆盖浅 / 深色 AX5。单一卡片以 430 pt 宽渲染，不等同于完整真机页面测试。正常字号数字仍在圈内，AX5 数字位于圈外；超额仅有一个突出的当前末端，没有新增文字截断或描边遮挡。附件位于 `.build/progress-input-ring-r3-evidence/`。
- 最后源码使用 `./scripts/build-ios.sh` 构建退出 0；`.build/progress-input-ring-r3-build-2026-10-09.log`。构建与模拟器测试均未访问真机数据库。

## 独立 Flask 水位预览

原型单独使用 `feat/water-fill-preview` 分支提交。控制台「02 / 热量状态」可切换圆环 / 水位圆圈，按已记录热量与预算比例填充，超额时水位封顶但保留实际超出数值；空记录、未知或无效预算不伪造水位。选择沿用本地预览偏好保存，不改变设计 JSON v1 或原生持久化。

本地固定数据验证：Python 44/44、Node 43/43；浏览器实际检查浅 / 深色、空态、未知预算、25% → 75% 水位、超额封顶、虚构餐食增加后水位更新，以及明确选择后的重载保留。控制台没有 warning / error。详细文件、步骤与限制见 `tools/ui-preview/README.md`、`MOTION_SPEC.md`。没有将水位效果加入原生 App，也没有改成饮水或连续少吃奖励。

## 尚待专项

- 本轮不冒称全量 17 项 UI 均已重跑；以实际定向执行范围为准。
- 真机首次聚焦体验、VoiceOver、iOS 26 运行时仍待专项检查；模拟器通过不替代这些证据。
- 未定位的键盘 frame 运行时警告继续挂账，不以本次外观修复关闭。
- 浏览器水位只是一种候选展示方式。是否替换原生热量环仍须用户确认和独立实现批准。

实现遵循 SwiftUI Pro 的原生选择 / 焦点、系统字体和无障碍降级原则；测试遵循 Swift Testing Pro 的语义 / 几何单测与真实 XCTest 交互分工，不把截图生成或参数断言当作实际用户体验验收。
