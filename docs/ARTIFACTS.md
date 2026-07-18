# 制品与镜像

`config/artifacts.json` 是安装器唯一信任的远程制品清单。发布时，`scripts/build.ps1` 生成带真实 SHA-256 的 `dist/manifest.json`，所有 URL 均指向 `https://plugin.yuniannian.asia`。

## 分级

| `offlineReady` | 含义 |
| --- | --- |
| `true` | 文件已完整镜像，安装阶段不访问境外下载站 |
| `false` | 只镜像厂商启动器或入口，后续仍可能访问厂商网络 |

## 收录原则

- Codex：镜像官方 Store 启动器，`offlineReady: false`。
- CC Switch：镜像固定版本 Windows MSI，`offlineReady: true`。
- EasyStart：安装脚本、核心包、两个插件全部镜像，`offlineReady: true`。
- Skills：仅镜像许可证允许再分发的固定版本。无许可证项目保留元数据但不公开复制，安装器自动隐藏不可用项。
- 北大法宝与百炼：插件代码离线可装，实际调用仍需访问各自境内 API 并由用户提供 Key。

## 更新步骤

1. 在 `config/artifacts.json` 更新上游版本和来源。
2. 运行 `scripts/sync-artifacts.ps1` 下载并核验上游摘要。
3. 运行 `scripts/build.ps1` 生成发布目录和最终清单。
4. 运行测试，并人工检查 `dist/manifest.json` 中的 URL、大小和哈希。

