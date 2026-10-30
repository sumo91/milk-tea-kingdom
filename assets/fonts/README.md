# Fonts
`ui_cjk_subset.otf`：V0-Q 临时子集，覆盖 `data/*.json` + HUD 脚本用到的汉字/符号。
桌面可读≠Web 可读：Web **没有**系统字体回退，必须把字形打进包。
来源系统黑体子集，**仅本机验收**；上架前换可商用（Noto Sans SC 等）。

## 启动页文案还没打进子集

`data/content.json` 的汉字已在 `ui_cjk_subset.otf` 里。HTML 启动壳用系统字体（苹方 / 冬青黑 / Noto Sans SC），不读这个子集，所以手机上这三句现在就能显示：

- `下载资源… 32%`
- `加载游戏…`
- `马上好…`

若要游戏内字体也能画这三句，在 Mac 上把下面缺的字补进 `docs/cjk_charset_v0q.txt` 再重建 `ui_cjk_subset.otf`，然后重新导出 Web。`资`（U+8D44）、`下`、`加`、`源` 已经在子集里。

缺：`载` U+8F7D、`游` U+6E38、`戏` U+620F、`马` U+9A6C、`上` U+4E0A、`好` U+597D、`…` U+2026。
