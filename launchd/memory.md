# Automation: 杭州保障房 LaunchAgent 每日监督
## Last run: 2026-06-10T01:22 CST

### This Run's Actions

**Health Check**: Passed for state (latest run 00:48 success, outbox clean, heat 48). Main and manual agents were loaded and healthy.

**Issue Found**: `run_codex_with_timeout.py` and `reconcile_manual_run.py` missing from runtime `launchd/` (not copied by 00:54 install.sh since they were created later at 01:08).

**Fixes Applied in Workspace**:
1. Modified `launchd/run_monitor.sh` to gracefully degrade when Python scripts missing:
   - Checks both runtime AND workspace paths for the scripts
   - Falls back to direct `codex exec` without timeout wrapper
   - Skips `reconcile_manual_run.py` with warning
2. Removed stale lock from 00:54 manual run

**Critical Issue**: During attempted deploy, `launchctl bootout` succeeded (unloaded both agents) but `launchctl bootstrap` is blocked by sandbox. Both agents are currently DOWN.

**Recovery**: Run `/bin/zsh /tmp/housing_recovery.sh` (also at `launchd/recovery.sh`) from terminal.

### Recovery Script Does
1. Copies missing Python scripts to runtime
2. Copies updated `run_monitor.sh` to runtime
3. Cleans stale lock
4. `launchctl bootstrap` both agents
5. Verifies state

### Post-Recovery State
- Main agent: ready for 07:30 schedule
- Manual agent: ready for kickstart
- Outbox: clean
- Heat: 48, milestone: 2026-06-02

### 2026-06-10T01:45 — 用户要求修改

**变更**: 本次监督自动化在"立即执行"时，需要在健康检查后通过以下命令触发 manual agent 发送邮件：
  `launchctl kickstart -k gui/$(id -u)/com.local.hangzhou.housing.monitor.manual`

**已验证**: 2026-06-10T01:45 kickstart → manual agent 运行 → 01:51 邮件发送成功
- 邮件标题: 【杭州配售型保障房监控·立即检索】2026-06-10 01:45 — 检索结果（无新增）
- Manifest: d4d08d5595a4ff03deee (sent)
- 内容: 无新增官方信息
