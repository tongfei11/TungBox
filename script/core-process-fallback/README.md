# macOS 进程识别测试 Core

基于 SagerNet/sing-box **v1.14.4**（`c005f35300ce76427dc285481ec5695f5b179cd2`）的实验补丁。上游源码按其 GPL-3.0-or-later 许可证使用；本目录中的补丁同样按 GPL-3.0-or-later 提供。

在 macOS 27.0.1 上复现：通过 `open` 启动的 `.app` 所派生的 Core，其 `net.inet.tcp.pcblist_n` 查询只返回 48 字节首尾框架，没有连接条目。同一个 Core 从命令行启动则能取得完整表。应用的“本地网络”权限已允许仍可能遇到。该测试结果不代表所有系统版本都受影响。

补丁保留原 sysctl 查询，仅在未找到进程时尝试 libproc 文件描述符查询。它不提升权限，不请求 Apple 私有 entitlement，不修改系统网络或隐私设置。无法访问的进程继续返回未找到。快照短暂缓存，缺失时重新读取一次，避免新连接被旧快照遗漏。

构建（在 macOS 上，需 Go、Xcode Command Line Tools）：

```sh
script/build_process_core.sh /absolute/path/sing-box
python3 script/test_process_core.py /absolute/path/sing-box
```

构建脚本通过 Go module 校验下载上游源码，追加此目录中的源码，并对查询入口应用一个最小补丁。测试只使用随机 loopback 端口和本地 HTTP 服务，不连接实际节点。

这是独立测试 Core（版本 `1.14.4-tungbox.1`），不会由 app 自动替换用户安装的 Core。可在设置 → Core 中导入；恢复时重新安装官方 Core。标准测试构建包含 gVisor、QUIC、DHCP、WireGuard、uTLS、ACME 和 Clash API；不适用于使用其他可选协议的配置。
