# UI-1 原生视觉基础交付证据

日期：2026-10-08。依据：BRAND_UI_DECISIONS第3、7、8节及本聊天批准。分支：`feat/ui-1-native-foundation`。

## 已交付与边界

语义Assets/DesignTokens统一浅深色翡翠、琥珀、表面和背景；热量/碳水/脂肪叫预算，蛋白质/纤维叫目标，饱和脂肪叫上限。红色不用于营养进度。UI仍为现有首页和表单，没有搬动记录入口或增加Tab。

Core保留v1，新增v2作为默认显示策略；数值阈值、营养计算和JSON字段兼容不变。`baseLap`、`overflowLap`、`multiple`为计算属性：图形最多两圈，营养值和倍数不截断；无效目标/未知值无伪进度，比例溢出明确注明显示精度不足。

圆环同色系渐变与末端帽区分重叠。达到预算仍主题色并注明未超出；超出叠加琥珀；2倍以上加实际倍数。最大辅助字体将数字移到圈外，营养行横排不够时纵排。空态不称“已记录摄入0”；有餐食显示“仅汇总…不代表整日记全”。深色实体表面与黑色背景分隔。

未改持久化12实体V1、唯一约束、Bundle ID、产物名、目标/餐食保存事务或删除行为。未接AI/HealthKit/云，未实现UI-BEH-01保存确认、搜索、日确认、历史目标、四栏、就地展开、日历或趋势。

## 实际验证

| 验证 | 结果 | 范围 |
| --- | --- | --- |
| `swift test --package-path Packages/FoodDecisionCore` | 108声明 / 367执行，零失败 | v1/v2、边界、Codable、派生圈数等全部Core回归 |
| FoodDecisionAssistant Scheme，iPhone17e专用UnitQA / iOS27 | 174声明 / 394执行，零失败、零跳过 | 现有持久化/事务/日期/草稿回归，新增显示测试和原生预览 |
| `./scripts/build-ios.sh -quiet`，iPhone17 / iOS27 | 成功 | 最低部署iOS26，当前安装SDK为27；不代表iOS26运行时已测 |
| 原生卡片渲染与逐张检查 | 16张，430pt宽/2x | 六场景各浅深色12张，3.2倍AX5浅深2张，未设目标浅深2张 |

最终UI-1结果包：`.build/ui-1-release-2026-10-08.xcresult`。原生附件保存在该结果包；可用`xcrun xcresulttool export attachments --path <结果包> --output-path <本地目录> --filter '*.png'`导出。截图为隔离卡片，不含导航栏或真实用户数据，不提交Git。

`TodayStatusPreview`与`UI1PreviewScenario`的样例是纯内存虚构数据，不写SwiftData。`UI1NativePreviewTests`使用`UIHostingController`和独立非key窗口绘制真正的系统进度条；窗口结束即解绑，不替换App根窗口。原`ImageRenderer`生成的系统ProgressView黄色占位与裁切截图不计最终视觉通过；已修复实际圆环高度撑高问题，并重新渲染。最初测试里的只读无障碍环境值注入和CGFloat歧义属于已修复编译问题；不将旧失败结果包宣称最终通过。

## 修改位置

- Core：`Rules/NutritionDisplayPolicy.swift`、`Rules/EnergyProgress.swift`及两组测试。
- App：语义Assets、`DesignTokens`、`EnergyProgressRing`及拆分的Arc/Endpoint/Value/Presentation；`NutritionProgressRow`/Presentation、TodayStatusCard、FibreSummaryRow、EmptyIntakeSummaryView、目标表单用词、现有餐食入口主题色与根tint。
- 原生预览：`TodayStatusPreview`、`UI1PreviewScenario`与`App/UI1NativePreviewTests`；新`App/EnergyRingPresentationTests`。Xcode工程只注册源码/资源，无数据库变更。
- 当前状态/路线/品牌/导航/开发资源/README与CHANGELOG同步；早期报告的历史测试数量保持不变。

## 尚未验证

真机本轮视觉覆盖更新、VoiceOver实际朗读、系统减少动态效果、动画/帧率、全屏页面交互、iOS26运行时与所有支持宽度未测。430pt最大字体卡片没有观察到文字裁切，不把这一观察扩展为全App无障碍通过。历史报告中的时间换行、独立数值舍入、表单无障碍标签等不在本次修复范围。

用户已报告真机备份恢复、文件保护及旧餐/目标/模板/新餐正常，记录为用户验收；不重复声称本轮代理检查真机。B-1随后独立提交；`.icon`由用户按design/brand/README在Icon Composer合成，缺文件与小尺寸证据时仍未完成。
