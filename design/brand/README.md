# 品牌素材（Evenfare / 食衡）

决定和理由都在 `docs/BRAND_UI_DECISIONS.md`，这里只放可以直接使用的素材。

2026-10-08：B-1主屏幕显示名已本地化为中文“食衡” / 英文“Evenfare”；内部产品名和Bundle ID不变，完整界面尚未翻译。用户完成的`icon-a/Evenfare.icon`已接入工程，Debug / Release构建和图标资源测试通过；60pt / 29pt真机辨识及各外观仍待验，详见`docs/B1_ICON_DELIVERY_REPORT.md`。资源编译不等于真机图标验收。

## 文件

| 文件 | 用途 |
| --- | --- |
| `icon-a/1-background.svg` | App 图标背景层，导入 Icon Composer |
| `icon-a/2-bowl.svg` | 碗（含碗足），导入 Icon Composer |
| `icon-a/3-chopsticks.svg` | 两根筷子，导入 Icon Composer |
| `icon-a/Evenfare.icon/` | 用户制作、工程已引用的Icon Composer图标；后续编辑此源文件，不另外复制一套 |
| `previews/icon-a-light.svg`、`-dark.svg`、`-mono.svg` | 三种模式的效果预览，带圆角遮罩；只用来看，不要导入 Icon Composer |
| `colors.json` | 主题色、状态色、热量环渐变、图标各模式颜色 |

## 用 Icon Composer 合成图标（Xcode 26 及以上）

1. 当前图标已制作：直接打开`icon-a/Evenfare.icon`编辑。其背景来自顶层填充，碗与筷子是两个前景层，不再导入额外的全幅背景SVG。
2. 原始SVG无渐变、阴影或圆角遮罩；用户已在Icon Composer设置材质，保留这些设置，光影由系统处理。
3. 分别检查默认、深色（Dark）、着色（Tinted）与透明（Clear）外观；Tinted和Clear不是同一种模式，不能统一套用`tintedMono`。现有文件为默认 / 深色显式填色，其他外观先验收系统派生效果。
4. 现有工程已引用该`.icon`，Debug / Release的App Icon名称均为`Evenfare`（不含扩展名）；保存艺术源后直接重建，无须重新添加资源。颜色空间保持用户导出的Display P3，不自动用sRGB hex覆盖。
5. 在真机主屏幕（60 pt）、设置列表和 Spotlight（29 pt）检查：两根筷子必须分得开。如果糊成一条，把 `3-chopsticks.svg` 里两根筷子的 `height` 从 48 改为 56，第二根的 `y` 从 374 改为 386，其余不变。

不要改 Bundle ID `com.ning6y6.ShiHeng`，也不要改 `PRODUCT_NAME`。
