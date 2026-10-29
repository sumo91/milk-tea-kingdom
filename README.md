# 奶茶王国放置（milk-tea-kingdom）

Godot 4 Web 发布目标 · 桌面调试骨架。与北境仓完全分离，勿混入北境资产。

## 打开

1. 本机已装 Godot 4.7+（`/Applications/Godot.app`）
2. 导入本目录，F5 运行 `scenes/main.tscn`

## 目录

- `data/` — 配表（JSON，单位全为 **/分**）
- `scripts/` — 计时 / 离线 / 存档 / 读表
- `scenes/` — 主界面
- `assets/ui/idle/{screen}/{asset_id}.png` — UI；临时占位用 `_temp` 后缀；图标建议 64

## 真实字段（进存档）

`ingredient` / `product` / `gold` / `prestige`、产线 `level`、升级购买状态、`last_logout_at`

## 先假数据

回本分钟文案、事件文案、换皮图标数字量级可改表。

## 存档

用户目录下 `user://save.json`（本地 JSON，无后端）。

## 发布目标：Web（HTML5）

- 开发仍用桌面编辑器调试；**对外可玩包走 Web 导出**。
- 预设：`export_presets.cfg` → **Web**，输出 `build/web/index.html`。
- 导出命令示例（本机 Godot）：
  ```bash
  /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --export-release "Web" build/web/index.html
  ```
- 托管需支持正确 MIME（`.wasm` / `.pck`）及 COOP/COEP（若开线程；当前预设 **关闭 thread_support**，部署更简单）。

### 浏览器存档（`user://`）

- Godot Web 把 `user://` 落到浏览器 **IndexedDB**（持久化），不是本机磁盘路径。
- 清站点数据 / 隐私模式 / 换浏览器 = 存档可能丢；V0 可接受，README 与离线弹窗可提示「请勿清站点数据」。
- 关页面前与切后台时 `save_game()`（`WM_CLOSE` / `APPLICATION_PAUSED` / `WM_WINDOW_FOCUS_OUT`）。
- 不要假设文件系统路径可给玩家备份；需要导出存档时再做「复制 JSON」按钮。
