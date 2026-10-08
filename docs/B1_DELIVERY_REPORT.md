# B-1 品牌显示名交付证据

日期：2026-10-08。分支：`feat/b-1-display-name`。本报告保留显示名切片当时的证据；当时图标未完成。用户随后提供的图标已在独立切片接入，最新状态与测试见[B-1图标交付证据](B1_ICON_DELIVERY_REPORT.md)，不改写本报告历史测试数量。

## 代码与身份

- `FoodDecisionAssistant/en.lproj/InfoPlist.strings`：`CFBundleDisplayName = Evenfare`。
- `FoodDecisionAssistant/zh-Hans.lproj/InfoPlist.strings`：`CFBundleDisplayName = 食衡`。
- `FoodDecisionAssistant.xcodeproj/project.pbxproj`：两种本地化的VariantGroup / Resources注册，默认显示名Evenfare，注册品牌测试。不重建工程。
- `FoodDecisionAssistantTests/App/BrandLocalizationTests.swift`：2声明 / 3展开执行，读取实际主App Bundle的指定语言资源，防止静默回退；检查标识、产物和默认显示名。

保持`com.ning6y6.ShiHeng`、`com.ning6y6.ShiHengTests`、`PRODUCT_NAME = ShiHeng`、`ShiHeng.app`、可执行文件ShiHeng、内部Target / Scheme / 源码目录与TEST_HOST不变。最低iOS26不变。没有修改SwiftData V1、唯一约束、营养计算、目标 / 餐食保存或导航。没有完整英文界面翻译或新增依赖。

## 实际验证

| 验证 | 结果 |
| --- | --- |
| `swift test --package-path Packages/FoodDecisionCore` | 108声明 / 367执行通过；B-1未修改Core |
| FoodDecisionAssistant Scheme，iPhone17 / iOS27 | 176声明 / 397执行，零失败、零跳过、runtimeWarnings为空 |
| `./scripts/build-ios.sh -quiet` | 成功 |
| 构建产物Info.plist与两种InfoPlist.strings只读检查 | 语言资源与显示名正确；Bundle ID / 可执行文件 / MinimumOSVersion保持原值 |
| Flask归档复核 | Python42、前端35，共77通过；不是原生交互验收 |

最终App结果包：`.build/b-1-release-2026-10-08.xcresult`。构建产物、预览PNG、日志和备份不进入Git。

B-1首次默认iPhone17回归仅16次PNG预览因窗口尚未连接失败；修正由独立`test/ui-preview-scene-readiness`交付，174声明 / 394执行验证通过后才恢复B-1并完成上述最终回归。详情见[UI-1交付证据](UI1_DELIVERY_REPORT.md)，初次失败不宣称成功。

## 品牌与计划文档

README、DECISIONS019/020、品牌决定、ROADMAP、APP_NAVIGATION_PLAN、OPTIMIZATION_EXECUTION_PLAN、EXECUTION_STATUS、CHANGELOG及素材说明已同步实际状态。旧英文名只作为内部身份或历史原型契约保留；不删除或重写旧验收证据。网页探索保留其v1行为，另以文档提交说明不代表当前原生规范。

## 尚未完成与下一步

1. 用户已制作`.icon`，工程接入详见[B-1图标交付证据](B1_ICON_DELIVERY_REPORT.md)；主屏幕60pt及设置 / Spotlight29pt两根筷子可辨认验收仍未完成。
2. 用相同Bundle ID覆盖更新真机，不卸载；检查中文 / 英文主屏幕名称及本轮UI-1浅深色 / 最大字体 / 圆环表现。系统实际主屏幕显示名、VoiceOver、减少动态效果、动画和iOS26运行时尚未实测，资源测试不代替这些检查。
3. 原有备份恢复、文件保护与旧餐 / 目标 / 模板 / 新餐已获用户报告正常，不重复要求相同门禁；本轮没有代理操作真机。
4. 今日和历史餐食现有详情 / 编辑 / 删除 / 汇总重算现在可用。轻量就地展开等新呈现需原生外壳独立批准，日确认 / 目标历史 / 有限查询按S3批准，异常输入保存确认仍是未批准的UI-BEH-01，不自动开工。
