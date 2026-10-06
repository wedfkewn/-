# 视觉资源

标题字体 Ma Shan Zheng 来自 [Google Fonts 官方仓库](https://github.com/google/fonts/tree/main/ofl/mashanzheng)。
正文字体霞鹜文楷轻便版来自 [作者仓库](https://github.com/lxgw/LxgwWenKai-Lite)。均保持原字体数据，随应用包含各自的OFL许可证。下载时核对官方Git blob哈希，资源离线打包。

`images/` 中的山水、宣纸、墨按钮、朱笔、突破和导航图案使用内置 Image Generation，按用户选定的第三张设计稿独立生成。参考及实际界面截图保存在 `docs/design/`，不作为交互界面图层使用。

`illustrations/` 的32张独立插画使用内置 `image_gen.imagegen` 生成，编码为离线 WebP。提示词与编码参数见 [提示词记录](../docs/illustrations-prompts.json)，映射与知识隔离说明见 [插画实现](../docs/illustrated-world.md)。
