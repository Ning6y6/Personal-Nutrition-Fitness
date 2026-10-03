# 第一阶段执行状态

更新日期：2026-10-03

## 当前环境

- Xcode 27.0、Swift 6.4、iOS 27 SDK：已确认
- iPhone 18 Pro Max 模拟器：已确认
- Apple Development 签名证书：未发现
- 代码仓库：工程骨架、核心规则包和 SwiftData v1 已建立
- `FoodDecisionAssistantTests`：已建立并接入共享 Scheme
- iPhone 18 Pro Max 模拟器测试：SwiftData 5/5 通过
- `FoodDecisionCore`：Swift Testing 13/13 通过

## 第 1 周：基础和规则

- [x] 建立原生 SwiftUI 工程骨架
- [x] 建立独立、可测试的核心规则包
- [x] 定义第一批领域模型
- [x] 写入版本化评分配置与补剂规则
- [x] 建立首批规则单元测试
- [x] 建立 SwiftData `VersionedSchema` 和九个应用层持久化实体
- [x] 建立每日目标设置页，可保存并重新读取六项营养目标
- [x] 建立 iOS 单元测试 target，并通过内存 SwiftData 保存、读取和领域转换测试
- [ ] 完成七字段快速手工录入原型
- [ ] 完成 HealthKit 保存、升版本、删除和回查实验
- [ ] 导入首批种子食材、外卖模板和英国包装商品
- [ ] 确认付费 Apple Developer Program 账号和签名
- [x] 定义 `MealPhotoEstimate`、`PortionCalibration` 和 `MealVisionProvider` 数据契约
- [ ] 准备首批可称重对照的餐食照片测试集

## 计划 A：拍照估算餐首个开发切片

- [x] 将餐食记录覆盖状态拆分为 `MealCoverageStatus`，证据等级拆分为 `EstimateEvidenceGrade`
- [x] 确认 `complete + c` 仍属于完整日记录
- [x] 建立可校验、可编码、满足 Swift 6 并发要求的拍照估算领域模型
- [x] 建立与商业提供方无关的异步 `MealVisionProvider`
- [x] 建立成功、超时、无效结果和低置信度四种离线 Fixture
- [x] 使用 SwiftData 保存估算、分项、用户修正、提供方元数据和称重校准
- [x] 为 SwiftData 多项关系保存显式顺序，避免回读时分项顺序不稳定
- [x] 核心包 13 项测试通过，iOS SwiftData 5 项测试通过，iOS App 构建通过

本切片没有接入真实 AI API，没有上传或保存系统相册原图，也没有实现正式拍照/确认界面、HealthKit 或 CloudKit。营养值仍须在后续切片中由本地 `FoodItem` 映射与计算，不能直接采用模型输出。

项目尚未发布，因此新增实体继续补入 `VersionedSchemaV1`。如果曾在模拟器运行旧版数据库并出现模型不兼容，应清除该模拟器中的 App 数据后重试，无需删除仓库文件。

## 已确认的范围调整

- [x] 采用计划 A，将拍照估算餐纳入产品 v0.1
- [x] 开发周期调整为 7 周开发加 2 周个人试用
- [x] AI 只提取菜品和份量候选，本地数据库负责营养计算
- [x] 记录覆盖完整度与估算精度分开保存
- [x] 外食日只要每餐都已记录，就可以进入完整日滚动平均
- [x] 隐藏油和酱汁作为可单独修正的估算项
- [x] 保存拍照估值与称重结果，为个人校准积累样本

## 需要用户完成

1. 在 Xcode → Settings → Accounts 登录 Apple ID，并确认是否已加入付费 Apple Developer Program。
2. 告诉 Codex 最终 App 名称；未确认前暂用 `FoodDecisionAssistant`。
3. 确认是否接受临时 Bundle ID：`com.ning6y6.FoodDecisionAssistant`。
4. 第一次真机验证时，在 iPhone 上授权读取步数、活动能量和训练，并授权写入六类营养数据。
