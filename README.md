# 杭州配售型保障性住房监控

本项目自动监控杭州市配售型保障性住房的最新官方消息，一手信息来源包括杭州住保房管局官网、杭州市规划和自然资源局等官方渠道，排除自媒体转载。

## 运行规则

- 每天北京时间 08:30 启动检索。
- 只取一手官方信息，排除自媒体转载。
- 有新消息 → 发送完整邮件，包含原文链接和摘要。
- 其他天数 → 不发送邮件，避免空报。
- 热度指标基于公告密度和近期动态综合计算。

## 推送配置

邮件通过 QQ SMTP 发送。首次使用前需配置授权码：

1. 在项目根目录创建 `.secrets/` 目录
2. 在其中存放发送授权信息
3. 编辑 `send_qq_email.py` 中的 `DEFAULT_ADDRESS` 为你的接收邮箱

## LaunchAgent 部署

项目支持通过 macOS LaunchAgent 实现每日自动运行：

```bash
cd launchd
bash install.sh
```

手动触发单次运行：

```bash
launchctl kickstart -k gui/501/com.local.hangzhou.housing.monitor.manual
```

## 项目结构

```
.
├── send_qq_email.py          # 邮件发送脚本（队列 + SMTP）
├── .gitignore                # 排除运行时数据、密钥、生成产物
├── .secrets/                 # 密钥（不上传）
├── .mail-outbox/             # 邮件队列（不上传）
├── logs/                     # 运行日志（不上传）
├── state/                    # 运行时状态（不上传）
└── launchd/
    ├── com.local.hangzhou.housing.monitor.plist       # 每日自动运行
    ├── com.local.hangzhou.housing.monitor.manual.plist # 手动触发
    ├── install.sh             # LaunchAgent 安装脚本
    ├── uninstall.sh           # 卸载脚本
    ├── run_monitor.sh         # 监控主入口
    ├── run_codex_with_timeout.py  # 带超时控制的 Codex 调用
    ├── reconcile_manual_run.py    # 手动运行结果整理
    ├── health_check.sh        # 运行状况检查
    ├── recovery.sh            # 自动恢复脚本
    ├── monitor_prompt.md      # 每日监控提示词
    ├── manual_prompt.md       # 手动干预提示词
    └── memory.md              # 监控记忆/状态记录
```
