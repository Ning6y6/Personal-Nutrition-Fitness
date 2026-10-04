# 变更记录

本项目尚未发布到 App Store；当前版本号用于记录个人开发里程碑。

## [0.1.0] - 2026-10-04

### 新增

- 正式产品名称“食衡（ShiHeng）”、Bundle ID `com.ning6y6.ShiHeng` 和现代 Launch Screen。
- SwiftData `VersionedSchemaV1` 及餐食、餐食分项、拍照估算和称重校准持久化实体。
- “记录一餐”首版：餐食名称、时间、称重或标准份量、覆盖状态、多食物分项和实时营养预览。
- 12 项基于 CoFID 2021 的个人种子食物，使用固定 ID 和幂等导入。
- 今日页营养汇总、最近三餐和热量圆形进度图。
- `MealPhotoEstimate`、`PortionCalibration`、`MealVisionProvider` 及成功/超时/无效/低置信度离线 Fixture。
- 可测试的热量显示规则：目标内为绿色，超出不超过 10% 为琥珀色，超过 10% 为红色。
- SwiftUI、SwiftData、Swift Testing 和 Swift Concurrency 开发 skills 使用规范。

### 修复

- 修复旧 Launch Screen 配置导致的真机上下留黑和导航栏错位。
- 修复编辑餐食名称时键盘“完成”无法收起的问题，并支持下滑收起键盘。
- 新食物分项不再自动选中第一项，避免无意保存错误食物。
- 未输入有效重量时不再展示整块全零营养预览。
- 清理不符合个人饮食约束的旧种子数据；仓库中不保留对应字样。
- 未设置每日目标时使用紧凑提示，避免首页空状态占用过多空间。

### 规则与数据安全

- 记录覆盖状态与估算证据等级拆分保存；已确认拍照估算仍可进入完整日统计。
- 餐食分项保存当时的名称、重量和营养快照，食物库更新不会静默改写历史数据。
- 拍照模型只返回组成、模板映射和份量范围；最终营养由本地 `FoodItem` 计算。
- 图片数据契约只保存哈希或本地引用，不保存系统相册原图。

### 验证

- `FoodDecisionCore`：22 项 Swift Testing 测试通过。
- `FoodDecisionAssistantTests`：6 项 iOS SwiftData 测试通过。
- iOS 26 最低部署目标构建通过。
- iPhone 模拟器完成安装、启动和首页布局检查。

### 尚未包含

- 真实 AI API、图片上传、正式拍照确认界面。
- 食品标签 OCR 和商品约束判断界面。
- HealthKit、CloudKit、训练记录和 Apple Watch 交互。
- 餐食编辑/删除、常用菜模板、自定义食物和 CSV 导出。
