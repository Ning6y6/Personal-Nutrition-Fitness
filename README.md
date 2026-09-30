# Food Decision Assistant

个人使用的原生 iOS 食品决策与饮食记录 App。第一阶段优先完成称重记录、动态目标、食品约束判断、营养标签扫描和 HealthKit 同步。

## 当前技术栈

- Xcode 27、Swift 6、SwiftUI
- SwiftData（应用数据，下一步接入）
- HealthKit（第 1 周先完成更新与删除实验）
- 本地 Swift Package：`FoodDecisionCore`

## 本地验证

```bash
swift test --package-path Packages/FoodDecisionCore
./scripts/build-ios.sh
```

当前应用标识 `com.ning6y6.FoodDecisionAssistant` 是临时值。真机运行前需要在 Xcode 中选择已登录的开发团队。

