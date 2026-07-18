# 交互设计

首次运行先检测 Windows、Codex、CC Switch 和已安装能力，再用结果能力提问，不要求用户理解 MCP、Skill 或模型配置。Windows 官方包显示名为 ChatGPT 时，界面必须直接说明其中包含 Codex，避免用户误以为装错应用。

```text
Codex EasyStart

  Codex       已安装 / 未安装
  CC Switch   已安装 / 未安装

请选择需要的能力（可多选，直接回车跳过）：
  1  使用 DeepSeek
  2  识别图片和扫描件
  3  增强法律工作能力
```

每个步骤只做一件事。API Key 使用隐藏输入；外部平台只在确实需要 Key 时打开。完成页按能力显示“已完成 / 已跳过 / 需要处理”，并提示重启 Codex 使插件生效。

重复运行提供检查、安装/升级、修复和卸载。卸载只移除 EasyStart 管理的文件和配置，不卸载用户原有 Codex 或 CC Switch。
