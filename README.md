<p align="center">
  <img src="Sources/TungBox/Resources/Tray/logo.png" alt="TungBox" width="128" height="128">
</p>

<h1 align="center">TungBox</h1>

<p align="center">
  <strong>macOS 原生 sing-box 图形客户端</strong>
</p>

<p align="center">
  <a href="https://github.com/tongfei11/TungBox/releases/latest"><img src="https://img.shields.io/github/v/release/tongfei11/TungBox?label=release&color=blue" alt="Release"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B-silver" alt="Platform">
  <img src="https://img.shields.io/badge/swift-6.0-orange" alt="Swift">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
</p>

---

## 简介

TungBox 是 [sing-box](https://github.com/SagerNet/sing-box) 的 macOS 原生客户端，使用 Swift 6 + AppKit 构建，适配 macOS 13 及以上版本。支持订阅管理、规则分流、节点选择、TUN 模式、状态栏控制等日常代理需求。内置 sing-box Core，开箱即用。

> 当前版本 **0.1.1** — 核心代理功能已稳定，日常使用可用。更完整的竞品功能对齐见 [TODO.md](TODO.md)。

## 功能

### 代理

- 系统代理开关 + TUN 模式开关，一键切换
- 规则 / 全局 / 直连三种出站模式
- 实时上传/下载速率、活跃连接数
- 流量统计（今日 / 近 7 天 / 近 30 天）

### 订阅

- 添加、编辑、删除、刷新订阅
- 支持 sing-box JSON、Base64 编码节点列表
- 按订阅自动生成托管配置文件
- 订阅自动定时刷新

### 节点

- 代理分组卡片展示（Selector / URLTest）
- 单节点 / 批量 URLTest 延迟测试
- 自动选择最快节点
- 手动切换即时生效

### 规则

- 规则列表搜索、浏览、命中概览
- SRS 规则集下载与展开
- 自定义规则添加与删除（按订阅独立存储）
- 订阅刷新后自动合并自定义规则

### TUN

- LaunchDaemon 安装 / 卸载
- 启用 / 禁用无感切换
- 退出时不误停 TUN Daemon，崩溃时自动恢复

### Core 管理

- 自动检测系统 / 内置 / 自定义 Core
- 一键安装最新版 / 旧版测试
- 手动导入可执行文件
- GitHub Release 版本号自动识别

### 其他

- 状态栏菜单：系统代理、TUN、出站模式、代理组快速切换
- 后台运行：关闭窗口最小化到状态栏，点击恢复
- 开机自启动 + 静默启动（仅状态栏）
- MD3 风格深浅色主题

## 安装

从 [Releases](https://github.com/tongfei11/TungBox/releases/latest) 下载 `TungBox-x.x.x-macos-arm64.dmg`，挂载后将 `TungBox.app` 拖入 `/Applications`。

首次打开时，macOS Gatekeeper 可能提示"无法验证开发者"。请在 **系统设置 → 隐私与安全性** 中点击"仍要打开"。

> TungBox 内置 sing-box Core，无需额外安装。TUN 功能需要管理员密码授权安装系统服务。

## 构建

```bash
# 要求 Xcode 16+ / Swift 6.0+
git clone https://github.com/tongfei11/TungBox.git
cd TungBox

# 调试运行
swift run

# 发布打包
bash script/package_app.sh
# → dist/TungBox-x.x.x-macos-arm64.dmg
```

## 项目结构

```
Sources/TungBox/
├── Core/              # 数据模型、存储、工具
├── MainWindow/        # 各页面视图控制器扩展
├── Networking/        # Clash API 客户端、订阅导入
├── Services/          # sing-box Runner、Core 更新、TUN 管理
├── MD3Views.swift     # MD3 设计系统组件
└── main.swift         # 入口 + 窗口管理
script/
└── package_app.sh     # 打包脚本
```

## 许可

MIT License

## 致谢

- [sing-box](https://github.com/SagerNet/sing-box) — 核心代理引擎
- [Clash Verge Rev](https://github.com/clash-verge-rev/clash-verge-rev) — UI 设计参考
