# 开发 Skills 与 UI 采用清单

更新日期：2026-10-08

## 当前采用

以下四个 MIT skills 已安装到 `~/.codex/skills`，覆盖项目当前阶段，不再叠加同类大型技能集：

- `swiftui-pro`：SwiftUI API、布局、导航、性能与无障碍审查。
- `swiftdata-pro`：SwiftData 模型、关系、查询与迁移审查。
- `swift-testing-pro`：领域规则和边界条件测试。
- `swift-concurrency-pro`：Swift 6 严格并发、异步提供方与取消处理。

以上 skills 已可在 Codex 中使用。每个任务只加载与该任务相关的 skill，避免无关上下文和重复建议。

## 按阶段再安装

- 标签扫描切片：安装 `vision-framework`，用于 Vision OCR、条码和 DataScanner。
- HealthKit 切片：安装 `healthkit`，用于授权、统计查询、保存、更新和删除。
- 营养区间和体重趋势图：先使用原生 Swift Charts；只有遇到具体实现问题时再安装 `swift-charts` skill。
- 训练休息计时：进入该模块后再评估 `alarmkit`。

暂不安装 Axiom、第二套 SwiftUI/并发技能或完整的 `swift-ios-skills` 集合，避免规则重叠。暂不引入 Pow、Vortex、Inferno 等运行时依赖；核心记录流程优先使用系统动画和触感。

## 已采用的 UI 原则

- 今日热量采用热量环v2：预算内使用翡翠色，同色系渐变；达到预算闭合但不变警告色。超出部分叠加琥珀圈，最多再画一圈；2倍及以上同时显示实际倍数和超出量。营养显示不使用红色，v1仍保留兼容解码与测试。
- 颜色必须同时配合图标和文字，满足“不依赖颜色区分”的无障碍要求。
- 蛋白质、纤维的最低目标始终使用主题色，达标加对勾；热量、碳水、脂肪称预算。饱和脂肪称上限，达到80%起琥珀预警，超过上限仍为琥珀并显示超出量。红色只用于硬约束判断，不把摄入超出预算当作医疗冲突。
- 动态数字使用系统 `numericText` 过渡，并尊重“减少动态效果”。
- Liquid Glass 只用于浮在内容上的交互控件；营养数字和规则结论保持在清晰实体表面上。
- 独立页面的空状态优先使用系统 `ContentUnavailableView`；卡片内使用紧凑的 `Label` 和说明文字，避免空状态撑高首页。
- 不为了视觉效果引入第三方依赖。
- 未来根级导航使用系统 `TabView`；四栏分别为今日、扫描、日历和设置，每栏使用独立 `NavigationStack`。该外壳仍待独立批准，没有随UI-1实施。
- 不照搬参考 App 的自定义悬浮底栏；由系统处理底部安全区、选中态、Liquid Glass 和辅助功能。

以上以[品牌与UI决定第8节](BRAND_UI_DECISIONS.md)为准。网页原型只作为流程、用词和配色探索，不将480ms曲线、CSS玻璃或可调圆角复制为原生规范。

## 后续页面方向

- 拍照估算：显示低—中—高范围，不用单个伪精确值；接入图表时使用 Swift Charts 范围带。
- 扫描：使用 DataScanner 原生高亮；结论卡使用颜色、SF Symbol 和文字三重表达，并增加成功、警告、错误触感。
- 称重：优先做净重输入和“毛重 − 皮重 = 净重”的清晰反馈，动画不得干扰快速录入。
- 体重趋势：原始称重点使用浅色点，平滑趋势使用实线。

## 参考来源

- [SwiftUI Pro](https://github.com/twostraws/swiftui-agent-skill)
- [SwiftData Pro](https://github.com/twostraws/SwiftData-Agent-Skill)
- [Swift Testing Pro](https://github.com/twostraws/Swift-Testing-Agent-Skill)
- [Swift Concurrency Pro](https://github.com/twostraws/Swift-Concurrency-Agent-Skill)
- [Apple：Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
