# 本地交互设计预览

这个 Flask 工具在浏览器中展示手机尺寸的交互 UI 原型，供检查颜色、布局、明暗主题和演示交互。页面上的食物、营养与记录都是虚构示例；网页不是 iOS 模拟器，也不代表正式 SwiftUI 功能已经实现。它不连接 HealthKit、SwiftData、设备数据、外部 API 或数据库，不改变正式应用中的健康与饮食规则。

颜色、圆角、密度、主题和黄色警示起点都是视觉预览参数。黄色起点只影响示例的视觉状态，不是健康阈值。修改仅保存到当前浏览器的 `localStorage`；导入会在内存中校验，导出经同源本地接口校验后下载设计 token JSON，文件名固定为 `ShiHeng-design-v1.json`。Flask 不保存导入或导出配置，后续请求始终得到相同默认配置。

## 启动

从仓库根目录执行：

```sh
python3 -m venv .build/ui-preview-venv
.build/ui-preview-venv/bin/python -m pip install -r tools/ui-preview/requirements.txt
.build/ui-preview-venv/bin/python tools/ui-preview/app.py
```

打开 [http://127.0.0.1:5058](http://127.0.0.1:5058)。如端口被占用：

```sh
.build/ui-preview-venv/bin/python tools/ui-preview/app.py --port 5060
```

服务器固定绑定 `127.0.0.1`，关闭 debug 和自动重载；按 `Ctrl+C` 停止。资源从本机加载，不使用 CDN。受信 Host 仅为 `localhost` 和 `127.0.0.1`，响应限制脚本与连接来源，并阻止嵌入其他页面。无需账号、密钥或健康数据。

Flask 3.1.2 是唯一直接依赖，版本固定以便复现，采用它的路由、模板自动转义及请求处理，减少手写 HTTP 服务的解析风险。Flask 安装时自带的必要依赖由 pip 安装；不增加生产 iOS 应用的依赖。

## 如何试设计

1. 宽窗口直接使用左侧调色面板；窄窗口点顶部「调色」，调整后点「完成调色，返回预览」。可以使用色块选择器或输入 `#RRGGBB`。
2. 切换浅色/深色，分别调整背景与卡片；改变圆角和间距。卡片文字与按钮文字按背景调整可读对比色，进度颜色保留原色。
3. 用六个状态按钮检查有余量、接近、刚好达到、超过、无记录及未设目标。也可以手动调整热量与预算。
4. 点击手机底部「今日、扫描、趋势、设置」，试玻璃近似导航与选中背景滑动。右下角「+」从同一容器展开为记录表单；选择演示食物、改克重、查看营养，再保存重算。取消、背景点击和 Escape 均保留草稿确认，包含未完成数字输入。
5. 今日顶部预算按钮不随内容滚走。点击餐食行就地展开详情，再点行标题收回。趋势上方是七日图，下方是日历；横向日期带可滑动吸附，方向键也可选日期。连续记录不奖励少吃，不代表整天记全。扫描仍只返回固定样例。
6. 在设置中切换中文 / English、减少动态效果与减少透明度。偏好保存在浏览器，独立于配色 JSON；用户自己的餐名不翻译。系统减少动态效果优先。
7. 导出 JSON 保留配色方案，之后可以导入。刷新仅保留设计参数与上述偏好，模拟餐食与目标重置；切换状态预设也会重置模拟餐食。

统一曲线、时长、材质与原生落地边界见 [MOTION_SPEC.md](MOTION_SPEC.md)。这是 CSS 玻璃近似，不是 Apple 原生 Liquid Glass。

初始绿/黄/红 `#2ED158` / `#FFD500` / `#FF4144` 是用户参考图的 sRGB 近似采样，不宣称是 Apple 官方 token。默认 80% 变黄只是可调整的拟议视觉参考线：热量、碳水、脂肪达到预算显示红色，文字区分「已达，尚未超出」与实际超量。蛋白质/纤维是最低目标，达标或超过保持达标；饱和脂肪按上限，80% 预警、相等未超出、真正超出才红。无餐食与无目标保持中性。

这个拟议预算配色**没有改写** `FoodDecisionCore` 的 `NutritionDisplayPolicy.v1`。日历的完整日状态也是虚构样例，不是正式日确认业务。四栏导航、正式 UI 改版及其他 S3–S5 事项仍遵守原批准门禁。

## 设计配置契约

`GET /` 渲染本地预览页。`GET /health` 返回 `{ "status": "ok", "service": "ui-preview", "localOnly": true }`。

`GET /api/preview-config` 返回以下配置本体：

```json
{
  "version": 1,
  "theme": "light",
  "colors": {
    "green": "#2ED158",
    "yellow": "#FFD500",
    "red": "#FF4144",
    "lightBackground": "#F6F7F3",
    "lightSurface": "#FFFFFF",
    "darkBackground": "#111214",
    "darkSurface": "#202124"
  },
  "warningPercent": 80,
  "radius": 22,
  "density": 1
}
```

`POST /api/validate-design` 接收此配置本体，`Content-Type` 必须为 `application/json`。所有字段必需，顶层及 `colors` 中的未知字段均被拒绝：

| 字段 | 允许值 |
| --- | --- |
| `version` | 整数 `1` |
| `theme` | `light` 或 `dark` |
| `colors` | 上述七个字段，每个为六位十六进制 `#RRGGBB`；输出统一大写 |
| `warningPercent` | 整数，50–99（含边界） |
| `radius` | 整数，12–32（含边界） |
| `density` | 有限数字，0.85–1.15（含边界） |

布尔值不能作为数字。禁止 `NaN`、无穷大、重复 JSON 字段、损坏的 JSON 与超过 8 KiB 的正文。

成功返回 HTTP 200：`{ "valid": true, "config": <规范化后的配置> }`。错误返回 `{ "valid": false, "error": { "code": "…", "message": "…", "field": "…" } }`，`field` 仅在字段错误时出现。HTTP 400 表示格式或字段无效，415 表示媒体类型不支持，413 表示正文过大。

`GET /api/design-export?config=<URL 编码的设计 JSON>` 使用相同的字段和 JSON 校验。`config` 必须是唯一查询参数，且解码后的 UTF-8 长度最多 8 KiB。成功响应为 `application/json` 附件，`Content-Disposition: attachment; filename="ShiHeng-design-v1.json"`，内容是规范化后的配置本体，没有成功响应外层包装。接口在内存中生成响应，不持久化文件或数据库。

使用上述 `app.py` 启动方式时，本地访问日志仅记录方法、路径、状态和响应大小，省略查询字符串。设计参数仍存在下载请求的 URL 中；它们只包含视觉 token，不能用于健康数据、密钥或其他个人数据。采用其他服务器或启动方式时，其访问日志设置需要另行配置。

## 验证

从仓库根目录执行标准库 `unittest`，不需要 pytest：

```sh
.build/ui-preview-venv/bin/python -m unittest discover -s tools/ui-preview/tests -v
```

测试覆盖页面和 API、附件下载、导出查询参数与 UTF-8 长度限制、默认配置隔离、严格类型和边界、颜色规范化、畸形/重复/非有限 JSON、请求大小限制、Host 限制、访问日志查询参数省略以及启动参数和响应安全头。此工具独立于 Swift 目标；不需要也不会操作物理设备或清除应用存储。

纯前端演示策略也可使用 Node.js 标准测试器验证（不安装 npm 依赖）：

```sh
node --test tools/ui-preview/tests/*.test.cjs
```

2026-10-07 验证：后端 42/42、前端 11/11 全通过，JavaScript 语法检查通过。实际浏览器已检查实时改色、明暗切换、自定义深色卡片的文字对比、六种状态、阈值键盘调整、称重预览、取消后继续编辑、Enter 离开输入、保存重算、固定扫描到记录、日历空日/月切换、目标修改、设计下载后导入以及无效导入不覆盖。独立空日用 50 g 燕麦演示保存后为 190 kcal / 1 餐，无重复累计。使用宽窗口与窄窗口实际操作；未宣称完成所有设备/浏览器、VoiceOver 或原生 iOS 验收。

同日交互升级后重新验证：后端 42/42、前端 35/35 全通过（策略 11、双语 9、动效 3、趋势 12），共 77 项。浏览器实际检查了四栏切换、同容器录入展开与草稿确认、350 g 演示餐计算/保存、餐食就地展开、滚动后固定预算入口及单字段预算修改、日期吸附居中、方向键选择、缺失日期断线与“无记录”、图表/日历日期联动、中英切换、减少动效与不透明降级，未发现控制台错误。前端纯测试不等于真实动画帧率验收；快速反转的起始几何已修正，但未进行逐帧性能测量。辅助字号、VoiceOver、原生 Liquid Glass 与真实设备仍须后续原生切片验收。

运行截图在仓库忽略的 `.build/ui-preview-qa/`，没有真实健康数据，不提交 Git。此次未改 Swift 源码、Schema 或 Xcode 配置，因此未运行 Swift / iOS 构建；既有 iOS 测试结果不作为网页验证结果。
