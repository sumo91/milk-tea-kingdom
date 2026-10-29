<callout icon="🎨" color="pink_bg">
状态：Draft（Idle美术）→ 待 Lando 看三图 + 命名后标 Approved。<br />栈：Godot 4 · 路径 `res://assets/ui/idle/{screen}/{asset_id}.png` · 图标 64×64 · 临时 `_temp`。<br />主题皮：奶茶王国 MVP（泡面/耙耙柑仅换皮）。
</callout>

## 路径约定

| 用途 | 路径 |
| --- | --- |
| 主屏 | `res://assets/ui/idle/main/` |
| 升级 | `res://assets/ui/idle/upgrade/` |
| 离线弹窗 | `res://assets/ui/idle/offline/` |
| 图标（资源/产线） | `res://assets/ui/idle/icons/` |
| 主题换皮 | `res://assets/ui/idle/skins/{skin_id}/` |

正式替换非 `_temp` 前须 Lando 同意。

## 资源轨（与字段 key 对齐）

| key | 中文 | 色相 | 资产 ID |
| --- | --- | --- | --- |
| ingredient | 茶叶 | 绿 `#5BBF6A` | `UI_BAR_INGREDIENT` · `UI_ICON_INGREDIENT` |
| product | 杯装奶茶 | 橙 `#F0A04B` | `UI_BAR_PRODUCT` · `UI_ICON_PRODUCT` |
| gold | 金币 | 黄 `#F5C542` | `UI_ICON_GOLD`（无硬顶条，仅存量字） |
| prestige | 声望 | 紫 `#9B7EDE` | `UI_BAR_PRESTIGE`（次级小条） |

条样式：可拉伸九宫 `UI_BAR_FILL_*_temp` + 底板 `UI_BAR_BG_temp`。

## 主屏 `main`

| 资产 ID | 说明 |
| --- | --- |
| `UI_PANEL_MAIN_temp` | 主屏底板 |
| `UI_TXT_TITLE` | 标题「奶茶王国」样式 |
| `UI_BAR_INGREDIENT` / `_PRODUCT` / `_PRESTIGE` | 见上 |
| `UI_RATE_LABEL` | 旁注 `+N/分` 小字样式 |
| `UI_LINE_STATION_01`…`04` | 产线四站图标位 |
| `UI_BTN_UPGRADE_ROW` | 底部升级卡行模板 |

## 产线三站图标（V0 锁定，对齐 content id）

| 站序 | building id | 中文 | 资产 ID |
| --- | --- | --- | --- |
| 1 | `tea_garden` | 茶园（视觉：茶叶货架） | `UI_ICON_STATION_SHELF` |
| 2 | `brew_station` | 调制台（封口并入本站） | `UI_ICON_STATION_BREW` |
| 3 | `stall` | 摊位 | `UI_ICON_STATION_STALL` |

`UI_ICON_STATION_SEAL_temp` 保留文件但不接线；V0 不单独占站。

## 升级 `upgrade`

| 资产 ID | 说明 |
| --- | --- |
| `UI_PANEL_UPGRADE_temp` | 升级列面板 |
| `UI_CARD_UPGRADE_temp` | 单卡：图标框 64 + 名称 + Lv + 效果 + 回本文案 + 按钮 |
| `UI_BTN_UPGRADE` | 常态 / 买不起灰 / 可点 |
| `UI_TXT_PAYBACK` | 「回本 ~N 分钟」样式 |

## 离线 `offline`

| 资产 ID | 说明 |
| --- | --- |
| `UI_MODAL_OFFLINE_temp` | 弹窗底 |
| `UI_ROW_OFFLINE_GAIN` | 明细行（图标+数量） |
| `UI_BTN_CLAIM` | 「确认领取」 |

## `_temp` 色块规格（给程序先挂）

- 资源条：高 28–32 px，圆角 8；填充纯色按上表 hex，底板 `#EDE4D7`。
- 图标：64×64 PNG，中心 glyph 占 40×40，透明底；`_temp` 可用色块+首字。
- 升级卡：宽满栏、高约 88；左图标 / 中文案 / 右按钮。
- 弹窗：宽屏 80%、圆角 16，背景白 `#FFFAF5`，遮罩 50% 黑。

## 验收（美术）

- [ ] 三轨色相一眼可分；数字优先于装饰
- [ ] 四站图标同栅格同描边权重
- [ ] 升级卡带回本字段位；离线弹窗仅三行信息区
- [ ] 全部 ID 可被 Control 节点同名引用
