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
- 自定义启动页：`web/shell.html`（`html/custom_html_shell`）。下载中显示 `下载资源… 32%`（百分号前有空格）和 `x.x / y.y MB`，下完显示 `加载游戏…`，进游戏前显示 `马上好…`。仍走 `Engine.startGame({ onProgress })`。
- `progressive_web_app/ensure_cross_origin_isolation_headers=false`（线程已关）。不要改回 true。
- 导出命令示例（本机 Godot 4.7）：
  ```bash
  /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --export-release "Web" build/web/index.html
  sh tools/web_deploy_tip.sh
  ```
- 部署提示一行：`?v=` git 短哈希、pck/wasm 的 sha256 和字节数、COI 必须为 false。见 `tools/web_deploy_tip.sh`。
- 手机 Safari 验收文案：`tools/web_smoke_checklist.txt`。硬刷新后必须进主 HUD，不能只看哈希。
- 托管需正确 MIME（`.wasm` / `.pck`）。线程关闭，不需要 COOP/COEP。

### 包体（量过当前 `build/web`，更小的 pck 要等 Mac 再导出）

| 文件 | 现在 | 说明 |
| --- | --- | --- |
| `index.wasm` | 39,514,754 字节（gzip -9 约 10,054,758） | 官方模板。导出预设不能裁模块，只有 `thread_support` / `extensions_support`，两者都已关。要再缩小必须用自定义 Web 模板，本环境没有编。 |
| `index.pck` | 997,092 字节 | 其中设计图 `docs/v0q-main-hierarchy.jpg` 的 ctex 约 570KB，线框约 30KB，都不是玩法。 |

下次导出会按 `exclude_filter` 丢掉 docs、tests、未接线的横版底板/封口图标/升级与离线占位图、平衡草稿和编辑器插件脚本。玩法资源仍在：三站、升级数据、离线弹窗（代码绘制）、CJK 子集、奶油色 UI。预计 pck 从约 997KB 降到约 330KB。wasm 不变，手机等待主要还是这 39MB；启动页的百分比就是为了这段等待。

纹理：现有导入是无损（`compress/mode=0`），没有 VRAM 变体。桌面 S3TC 和手机 ETC2 两个导出开关都设为 false，工程里也关闭了这两种导入。Web 只有一个 pck，两个都开会把两份 GPU 纹理都塞进下载。

### 浏览器存档（`user://`）

- Godot Web 把 `user://` 落到浏览器 **IndexedDB**（持久化），不是本机磁盘路径。
- 清站点数据 / 隐私模式 / 换浏览器 = 存档可能丢；V0 可接受，README 与离线弹窗可提示「请勿清站点数据」。
- 关页面前与切后台时 `save_game()`（`WM_CLOSE` / `APPLICATION_PAUSED` / `WM_WINDOW_FOCUS_OUT`）。
- 不要假设文件系统路径可给玩家备份；需要导出存档时再做「复制 JSON」按钮。
