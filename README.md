# 刻度时钟 — SnowDesktop 组件

一个 [SnowDesktop](https://snowdesktop.com/) 桌面组件：复刻 [DeskCanvas](https://github.com/Genlue/DeskCanvas) 里那块「刻度时钟」方卡——一圈贴着卡片内缘的刻度、红色的星期、超大的时间和日期。

<p align="center"><img src="preview.png" width="420" alt="刻度时钟预览"></p>

> 非官方组件，与 DeskCanvas 无隶属关系。英文名「Tick Clock」。

## 功能

- **刻度环**：沿卡片内缘等弧长排布，相邻刻度间距一致；每根刻度指向卡片中心。圆角与卡片边框同心（外圈半径 = 卡片圆角 − 内缩量），不是简单的小圆角矩形。
- **星期**：`周日…周六`（中文）或 `SUN…SAT`（英文），固定参考图的红色 `#EE3B33`。
- **时间**：`HH:MM` 或 `H:MM`，内嵌 Bebas Neue；按字形墨迹（不是行框/字宽）适配与居中，数字上下左右都对齐卡片中心。
- **日期**：`11.16` 形式，月日之间用六分之一空格（U+2006）撑开，和参考图的细缝一致。
- **开关**：星期、日期、24 小时制各自可关；两个标签都关掉时时间占满整卡并垂直居中。
- **自适应**：2×2 默认；更高或更宽的卡片会保持文字块比例（高度 ≤ 1.25 × 宽度）并整体居中，不会被拉散。
- **外观**：磨砂 / 实色 / 透明三种预设，跟随系统深浅色（前景色取宿主解析后的 contentTheme）。

## 安装

### 从文件安装（推荐）

1. 到本仓库的 [Releases](../../releases) 下载最新的 `tick-clock.snowwidget`。
2. SnowDesktop → **设置 → 组件 → 从文件安装…**，选择该文件。
3. 添加后即可使用；组件不联网、不申请任何权限。

### 作为开发组件

把仓库内容（`widget.json`、`main.lua`、`modules/`、`assets/`、`tests/`）放进：

```
<SnowDesktop 安装目录>\data\widgets\dev\tick-clock\
```

然后在 **设置 → 组件 → 添加组件** 里找到「刻度时钟」。开发目录的改动会即时生效。

## 设置项

| 设置 | 默认 | 说明 |
| --- | --- | --- |
| 显示星期 | 开 | 关掉后星期行留空 |
| 显示日期 | 开 | 关掉后日期行留空 |
| 24 小时制 | 开 | 关掉后显示 `1:05` 这样的 12 小时制 |
| 外观预设 | 磨砂 | 磨砂 / 实色 / 透明 |

## 兼容性

- SnowDesktop 1.0.15.0 及以上（API v2）。
- 需要的组件能力：`draw.immediate`、`view.font`（内嵌字体）、`schedule.basic`、`schedule.visibility`、`time.basic`、`layout.relativeUnits`、`l10n.basic`、`lifecycle.event/model`、`widget.context`。
- 可选能力：`draw.textInkMetrics`（有则按字形墨迹精确居中，没有则退回行框）。
- 无网络域、无权限。

## 实现要点

- **字体**：内嵌 Bebas Neue（SIL OFL 1.1）。宿主的默认字面太宽，方卡上会显得空。字体句柄在入口阶段加载，`setup()` 里再取会触发 `loadPhaseRequired`。
- **时间定位**：在 `render()` 里用 `draw.measureText(text, 100, 0, bold, font).ink` 拿到真实字形盒，按它缩放和居中；`modules/clock.lua` 里保留一份逐字 TTF 度量（advance / xMin / xMax、`inkTop 0.223`、`inkHeight 0.720`）作为取不到 `ink` 时的回退。
- **刻度环**：`modules/clock.lua` 的 `dialTicks()`，移植自参考项目的 `DialTicksControl.cs`——内缩 4.1% 短边、刻度长 3.0%、间距 4.6%（最小 6 px）、圆角 `卡片圆角 − 内缩`、短边 < 92 px 时不画。
- **刷新**：`schedule.every("tick", 1000)`，只有分钟数变化才 `widget.invalidate()`，空闲帧零开销。

## 开发

用 SnowDesktop 自带的 `snowwidget` CLI 校验：

```powershell
snowwidget lint    .
snowwidget test    .      # 11 个用例：时间/星期/日期格式、刻度几何、圆角同心、非法输入
snowwidget preview . out.png --columns 2 --rows 2 --locale zh-CN
snowwidget quality .
snowwidget pack    . tick-clock.snowwidget
```

## 设计来源

- 视觉、行高比例（12.5/13/6/38/7/11/12.5%）与刻度参数来自 DeskCanvas 的 `TickClock` 组件（`src/Widgets/ClockCalendar/TickClock`）。
- 圆角处理按参考项目的 `DialTicksControl.CardCornerRadius` 语义：宿主卡片圆角减去内缩量，保证刻度环与边框同心。

## 第三方资源

- `assets/fonts/BebasNeue-Regular.ttf` — Bebas Neue, Copyright (c) Dharma Type，
  SIL Open Font License 1.1，许可证全文见 `assets/fonts/OFL.txt`。

## License

[MIT](LICENSE) © Yskye
