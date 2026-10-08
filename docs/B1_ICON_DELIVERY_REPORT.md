# B-1 图标工程接入交付证据

日期：2026-10-08。分支：`feat/b-1-app-icon`。范围：已批准B-1的剩余图标资源接入；用户完成Icon Composer制作后继续执行。不扩展为导航、界面翻译或新业务。

## 文件与接入

| 文件 | 本次内容 |
| --- | --- |
| `design/brand/icon-a/Evenfare.icon/icon.json` | 用户导出的图标工程，保留背景、默认 / 深色特化、Display P3色值、材质与阴影 |
| `design/brand/icon-a/Evenfare.icon/Assets/2-bowl.svg`、`3-chopsticks.svg` | 用户图标引用的两个本地图层，与已批准的原SVG一致，不重绘 |
| `FoodDecisionAssistant.xcodeproj/project.pbxproj` | 用`SOURCE_ROOT`相对路径注册`folder.iconcomposer.icon`，加入App Resources；Debug / Release设`ASSETCATALOG_COMPILER_APPICON_NAME = Evenfare` |
| `FoodDecisionAssistantTests/App/BrandLocalizationTests.swift` | 新增1个非参数化测试，检查实际编译App的`CFBundleIcons / CFBundlePrimaryIcon / CFBundleIconName`及非空编译资源文件 |
| 当前状态 / 路线 / 品牌文档 | 工程交付时同步为“图标已制作并接入，真机外观待验”；后续限定用户反馈另记下节，保留176 / 397等历史结果 |

图标是正常Xcode资源，不塞入`Assets.xcassets`，不复制成第二套艺术源，不手写Info.plist图标字典。主图标元数据与PNG由Xcode资源编译生成。

静态检查：JSON有效；两个图层文件存在、为普通文件、引用不越界；SVG无外部链接、脚本或位图；1024画布一致。背景来自图标顶层填充，不要求另一个背景SVG。未自动修改颜色空间，Display P3相同数值通道不等于严格匹配原hex的sRGB观感。

## 实际验证

| 验证 | 结果 |
| --- | --- |
| `swift test --package-path Packages/FoodDecisionCore` | 108声明 / 367展开执行通过；本次未改Core |
| `./scripts/test-ios.sh -quiet -parallel-testing-enabled NO -collect-test-diagnostics never -resultBundlePath .build/b-1-icon-2026-10-08.xcresult` | FoodDecisionAssistant Scheme，iPhone17 / iOS27：177声明 / 398展开执行；零失败、跳过、预期失败与运行时告警 |
| `./scripts/build-ios.sh -quiet` | Debug构建成功 |
| `./scripts/build-ios.sh -quiet -configuration Release` | Release构建成功 |
| Debug编译产物只读检查 | `CFBundleIconName = Evenfare`，含`Assets.car`、`Evenfare60x60@2x.png`及iPad后备PNG；默认后备PNG已查看，碗与两根筷子可见，但不冒充真机29pt验收 |
| 身份回归 | `com.ning6y6.ShiHeng`、`ShiHeng`可执行文件 / 产物名、显示名本地化和MinimumOSVersion26.0不变 |

结果包位于忽略的`.build/b-1-icon-2026-10-08.xcresult`。编译产物、日志、预览和健康数据不提交Git。本次没有操作真机、卸载App或清除数据。

## 后续用户真机验收反馈：2026-10-08

- [x] 用户确认图标Normal（默认）外观正常，Dark / Tinted / Clear外观良好。
- [x] 用户确认Settings中缩小显示的图标正常。
- [ ] Spotlight独立小尺寸检查未报告；不由Settings反馈推定通过，也不声称已测量60pt / 29pt几何分离度。
- [ ] 中英文主屏幕显示名专项未报告；完整英文界面未开发。
- [ ] UI-1真机浅深色 / 最大字体、VoiceOver、减少动态效果及动画仍待专项验收。

这是用户报告的验收证据，不是代理实际操作真机。已报告的图标外观 / Settings缩小显示不再重复待验；B-1全部实机专项仍不标整项完成，图标反馈也不关闭UI-1或S3验收。

## 边界与待验

- 保留12实体SwiftData V1、唯一约束、所有数据库路径及保存 / 恢复流程；不改Bundle ID、PRODUCT_NAME、Target、Scheme和TEST_HOST。
- `design/brand/README.md`的接入状态与操作说明已更正；用户原有未提交的`x x`编辑保留原样且不混入本次提交，只暂存本轮文档更正。
- 只显示名已本地化，完整英文界面仍未实现。
- Default / Dark有显式颜色特化；Tinted / Clear未手工覆盖，系统派生外观已获上述用户确认。没有因为缺少手工特化就擅自修改用户素材。
- 代理未运行iOS26、VoiceOver或操作本轮真机；图标用户反馈与代理资源编译 / iOS27模拟器证据分别记录，不互相替代。
- 本轮随后另获原生整改三切片批准，见[NATIVE_UI_EXECUTION_PLAN](NATIVE_UI_EXECUTION_PLAN.md)，均未实施；日确认 / 历史目标 / 食品搜索、完整日历 / 趋势和异常输入核对没有新增批准。

## 用户仍待完成的专项

1. 后续继续用相同Bundle ID覆盖更新，不卸载或清库。已确认四种图标外观及Settings缩小显示，不重复要求同一验收。
2. 尚未报告的Spotlight小尺寸辨识与中文 / 英文主屏幕名称分别检查；若图形糊成一条先反馈，再按独立图标调整处理，不提前改用户艺术源。
3. UI-1与新增UI整改的真实设备视觉 / 无障碍专项分别记录。未测项目不统一阻塞不改数据库的UI开发，但不能冒称通过。
