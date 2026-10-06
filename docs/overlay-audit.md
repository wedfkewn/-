# 弹窗入口审查

所有业务模态入口已接入 ui/ink_overlays.dart：

| 文件 | 入口 | 样式 |
|---|---|---|
| details.dart | 人物、历史事件、关系 | showInkSheet |
| karma_page.dart | 筛选 | showInkSheet |
| map_page.dart | 地点详情、路线预览 | showInkSheet |
| karma_page.dart | 搜索、图例 | InkDialog |
| ai_pages.dart | 模型列表、服务商变更 | InkDialog |
| game_shell.dart | 创角、交战确认、死亡 | InkDialog |
| growth_page.dart | 雷劫确认 | InkDialog |

业务代码未保留 AlertDialog 或直接 showModalBottomSheet；底层只有共享组件调用。失败信息三处使用全局 SnackBarTheme，选择菜单使用统一 PopupMenuTheme。死亡提示禁止点遮罩或返回键绕过，确认后才进入存档页。

扫描命令：rg -n 'showModalBottomSheet|showDialog|showGeneralDialog|showCupertino|AlertDialog|SimpleDialog|Dialog\(|BottomSheet\(|PopupMenu|showMenu|OverlayEntry|SnackBar\(' lib
