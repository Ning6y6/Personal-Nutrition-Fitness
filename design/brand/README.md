# 品牌素材（Evenfare / 食衡）

决定和理由都在 `docs/BRAND_UI_DECISIONS.md`，这里只放可以直接使用的素材。

2026-10-08：B-1主屏幕显示名已本地化为中文“食衡” / 英文“Evenfare”；内部产品名和Bundle ID不变，完整界面尚未翻译。当前仍只有三层SVG及视觉预览，没有合成或接入的`.icon`。图标合成由用户完成后提供工程文件，接入与60pt / 29pt真机辨识仍未完成，不能把素材预览当作App图标已安装。

## 文件

| 文件 | 用途 |
| --- | --- |
| `icon-a/1-background.svg` | App 图标背景层，导入 Icon Composer |
| `icon-a/2-bowl.svg` | 碗（含碗足），导入 Icon Composer |
| `icon-a/3-chopsticks.svg` | 两根筷子，导入 Icon Composer |
| `previews/icon-a-light.svg`、`-dark.svg`、`-mono.svg` | 三种模式的效果预览，带圆角遮罩；只用来看，不要导入 Icon Composer |
| `colors.json` | 主题色、状态色、热量环渐变、图标各模式颜色 |

## 用 Icon Composer 合成图标（Xcode 26 及以上）

1. 打开 Icon Composer，把 `icon-a/` 里的三个 SVG 按 1 → 3 的顺序拖进去（背景在最下）。
2. 图层是纯色、无渐变、无阴影、无圆角遮罩；光影由系统添加。
3. 在深色（Dark）和着色（Tinted/Clear）外观下，按 `colors.json` 的 `appIconA.dark`、`appIconA.tintedMono` 改各层颜色。
4. 存成 `.icon` 文件放进工程，在 Target → General 的 App Icon 中填写文件名（不含扩展名）。
5. 在真机主屏幕（60 pt）、设置列表和 Spotlight（29 pt）检查：两根筷子必须分得开。如果糊成一条，把 `3-chopsticks.svg` 里两根筷子的 `height` 从 48 改为 56，第二根的 `y` 从 374 改为 386，其余不变。

不要改 Bundle ID `com.ning6y6.ShiHeng`，也不要改 `PRODUCT_NAME`。
