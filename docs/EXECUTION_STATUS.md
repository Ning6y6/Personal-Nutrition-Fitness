# 第一阶段执行状态

更新日期：2026-09-30

## 当前环境

- Xcode 27.0、Swift 6.4、iOS 27 SDK：已确认
- iPhone 18 Pro Max 模拟器：已确认
- Apple Development 签名证书：未发现
- 代码仓库：本轮初始化

## 第 1 周：基础和规则

- [x] 建立原生 SwiftUI 工程骨架
- [x] 建立独立、可测试的核心规则包
- [x] 定义第一批领域模型
- [x] 写入版本化评分配置与补剂规则
- [x] 建立首批规则单元测试
- [ ] 建立 SwiftData `VersionedSchema`
- [ ] 完成七字段快速手工录入原型
- [ ] 完成 HealthKit 保存、升版本、删除和回查实验
- [ ] 导入首批种子食材、外卖模板和英国包装商品
- [ ] 确认付费 Apple Developer Program 账号和签名

## 需要用户完成

1. 在 Xcode → Settings → Accounts 登录 Apple ID，并确认是否已加入付费 Apple Developer Program。
2. 告诉 Codex 最终 App 名称；未确认前暂用 `FoodDecisionAssistant`。
3. 确认是否接受临时 Bundle ID：`com.ning6y6.FoodDecisionAssistant`。
4. 第一次真机验证时，在 iPhone 上授权读取步数、活动能量和训练，并授权写入六类营养数据。

