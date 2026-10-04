# 第一阶段执行状态

更新日期：2026-10-04

## 当前环境

- Xcode 27.0、Swift 6.4、iOS 27 SDK：已确认
- iPhone 18 Pro Max 模拟器：已确认
- Apple Development 签名证书：已通过 Personal Team 创建并完成真机构建
- iPhone 16 Pro Max 真机运行：已确认；Personal Team 描述文件需每 7 天重新签名
- 代码仓库：工程骨架、核心规则包和 SwiftData v1 已建立
- `FoodDecisionAssistantTests`：已建立并接入共享 Scheme
- iPhone 18 Pro Max 模拟器测试：SwiftData 6/6 通过
- `FoodDecisionCore`：Swift Testing 22/22 通过
- 正式产品名称：`食衡` / `ShiHeng`
- 正式 Bundle ID：`com.ning6y6.ShiHeng`

## 第 1 周：基础和规则

- [x] 建立原生 SwiftUI 工程骨架
- [x] 建立独立、可测试的核心规则包
- [x] 定义第一批领域模型
- [x] 写入版本化评分配置与补剂规则
- [x] 建立首批规则单元测试
- [x] 建立 SwiftData `VersionedSchema` 和十个应用层持久化实体
- [x] 建立每日目标设置页，可保存并重新读取六项营养目标
- [x] 增加现代 Launch Screen 声明，修复真机兼容模式造成的上下留黑和导航栏错位
- [x] 建立 iOS 单元测试 target，并通过内存 SwiftData 保存、读取和领域转换测试
- [ ] 完成七字段快速手工录入原型
- [ ] 完成 HealthKit 保存、升版本、删除和回查实验
- [ ] 导入首批种子食材、外卖模板和英国包装商品
- [x] 导入 12 项可追溯至 CoFID 2021 的个人常用食材种子数据
- [x] 完成“记录一餐”首版：称重/标准份量、多分项、实时营养计算、SwiftData 保存与今日汇总
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
- [x] 核心包 22 项测试通过，iOS SwiftData 6 项测试通过，iOS App 构建通过

## 记录一餐首版

- [x] 使用 `MealComponent` 按每 100 克营养数据生成历史快照，避免食物库更新后改写旧记录
- [x] 称重/包装数据自动记为证据 A，标准份量/经验估算自动记为证据 B
- [x] 支持餐食名称、时间、覆盖状态、多个食物分项、重量与分项删除
- [x] 实时预览热量、蛋白质、碳水、脂肪、饱和脂肪与纤维
- [x] 今日页显示摄入、目标差额和最近三餐，保存后通过 SwiftData 自动刷新
- [x] 在全新 iPhone 18 Pro Max 模拟器上完成安装、启动与首页布局检查
- [x] 修复餐食名称输入时键盘“完成”无法收起的焦点缺陷
- [x] 新分项默认不选食物，高级记录项折叠，无有效重量时不显示全 0 营养表
- [x] 个人种子库收缩为 12 项，并在启动时清理已废弃的非适用种子条目
- [x] 今日热量改为圆形进度图；目标内、轻微超出和显著超出使用可测试的确定性状态
- [x] 热量和营养数字增加系统数值过渡，并用文字和图标补充颜色含义

## 开发工具与 UI 规范

- [x] 安装 `swiftui-pro`、`swiftdata-pro`、`swift-testing-pro` 和 `swift-concurrency-pro`
- [x] 采用按开发切片安装专项 skill 的策略，暂不安装完整技能集合
- [x] 记录 Liquid Glass、拍照估算范围、扫描反馈、称重反馈和体重趋势的使用边界
- [ ] 标签扫描切片开始时评估并安装 `vision-framework`
- [ ] HealthKit 切片开始时评估并安装 `healthkit`

当前记录界面只支持本地种子食物和克重。自定义食物、菜谱批次、剩菜复用、照片识别和标签扫描仍未接入。

下一开发切片为历史餐食详情、编辑和删除，并验证修改后今日汇总能够正确重算；完整优先级见 [`ROADMAP.md`](ROADMAP.md)。

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

1. 若需要 App 超过 Personal Team 的 7 天签名期持续可用，或后续使用付费账号能力，需确认 Apple Developer Program 会员资格。
2. 在真机上手动记录一餐，确认中文菜单、键盘、保存与首页刷新符合你的操作习惯。
3. 开始第一次 HealthKit 真机验证时，在 iPhone 上授权读取步数、活动能量和训练，并授权写入六类营养数据。
