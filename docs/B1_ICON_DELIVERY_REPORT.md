# B-1 图标工程接入交付证据

日期：2026-10-08。分支：`feat/b-1-app-icon`。范围：已批准B-1的剩余图标资源接入；用户完成Icon Composer制作后继续执行。不扩展为导航、界面翻译或新业务。

## 文件与接入

| 文件 | 本次内容 |
| --- | --- |
| `design/brand/icon-a/Evenfare.icon/icon.json` | 用户导出的图标工程，保留背景、默认 / 深色特化、Display P3色值、材质与阴影 |
| `design/brand/icon-a/Evenfare.icon/Assets/2-bowl.svg`、`3-chopsticks.svg` | 用户图标引用的两个本地图层，与已批准的原SVG一致，不重绘 |
| `FoodDecisionAssistant.xcodeproj/project.pbxproj` | 用`SOURCE_ROOT`相对路径注册`folder.iconcomposer.icon`，加入App Resources；Debug / Release设`ASSETCATALOG_COMPILER_APPICON_NAME = Evenfare` |
| `FoodDecisionAssistantTests/App/BrandLocalizationTests.swift` | 新增1个非参数化测试，检查实际编译App的`CFBundleIcons / CFBundlePrimaryIcon / CFBundleIconName`及非空编译资源文件 |
| 当前状态 / 路线 / 品牌文档 | 同步为“图标已制作并接入，真机外观待验”；保留显示名阶段176 / 397等历史结果 |

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

## 边界与待验

- 保留12实体SwiftData V1、唯一约束、所有数据库路径及保存 / 恢复流程；不改Bundle ID、PRODUCT_NAME、Target、Scheme和TEST_HOST。
- `design/brand/README.md`的接入状态与操作说明已更正；用户原有未提交的`x x`编辑保留原样且不混入本次提交，只暂存本轮文档更正。
- 只显示名已本地化，完整英文界面仍未实现。
- Default / Dark有显式颜色特化；Tinted / Clear未手工覆盖，需验收系统派生外观。没有因为缺少手工特化就擅自修改用户素材。
- 未运行iOS26运行时、VoiceOver或本轮真机视觉验收。资源编译及iOS27模拟器测试不代替这些证据。
- 原生四栏、记录入口比较、餐食就地展开、日确认 / 历史目标、日历 / 趋势和异常输入核对仍按各自批准与门禁，不自动开工。

## 用户下一步

1. Xcode选择现有FoodDecisionAssistant Scheme和自己的iPhone，用相同Bundle ID运行并覆盖更新；不要卸载App。确认旧餐食 / 目标 / 模板仍在。
2. 在主屏幕默认及深色外观检查碗和两根筷子；再检查着色和透明外观，确认图案仍能区分。
3. 按品牌决定在主屏幕60pt、设置 / Spotlight小尺寸29pt检查两根筷子分离度。若小尺寸糊成一条，先反馈截图，再在独立图标调整中采用批准的几何修正，当前不提前改稿。
4. 用户确认通过后再标记B-1真机验收完成；原生外壳仍须另获批准。
