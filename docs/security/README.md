# 安全扫描记录

这里存放 TungBox 的安全扫描报告和配套工件。

每次完整扫描建议按扫描 ID 建目录，例如：

```text
docs/security/20260603T080239Z-d91424b/
```

目录内保留：

- `security_report.md`：主报告
- `artifacts/01_context/`：威胁模型和上下文
- `artifacts/02_discovery/`：候选问题
- `artifacts/03_coverage/`：覆盖清单
- `artifacts/04_reconciliation/`：验证记录

不要只把安全报告放在 `/tmp`，临时目录可能被清理。
