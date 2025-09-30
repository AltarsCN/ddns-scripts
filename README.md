# ddns-scripts

<details>
<summary><strong>English</strong></summary>

## Overview
`ddns-scripts` provides the core shell helpers that refresh public DNS records for OpenWrt systems. It drives the `/etc/init.d/ddns` service, polls your current IPv4/IPv6 addresses, and invokes provider-specific update endpoints so that hostnames always resolve to the router's latest IP.

## Features
- Supports dozens of popular dynamic DNS providers via pluggable update scripts.
- Handles IPv4 and IPv6 addresses, including SLAAC neighbours and custom detection URLs.
- Flexible IP source selection: network interfaces, devices, external web checks, or custom scripts.
- Extensive logging with per-service log files and optional syslog integration.
- Sample configuration snippets under `samples/` to accelerate onboarding.

## Requirements
- OpenWrt 21.02 or newer (earlier releases may work but are untested).
- `busybox`, `wget` or `curl`, and appropriate SSL libraries for HTTPS-based providers.
- Optional helpers: `bind-host`, `drill`, or `knot-host` when custom DNS lookups are required.

## Installation
```sh
opkg update
opkg install ddns-scripts
# Install extra providers as needed
opkg install ddns-scripts_cloudflare-v4 ddns-scripts_godaddy
```

If you are developing locally, copy the files in `files/` to the OpenWrt root and restart the service:
```sh
/etc/init.d/ddns restart
```

## Configuration
1. Create or edit `/etc/config/ddns` using the examples in `samples/ddns.config_sample`.
2. Define one or more `service` sections with at least:
   - `service_name` (or `update_url/update_script` for custom providers)
   - `lookup_host`
   - `use_ipv6` (0 or 1)
3. Adjust advanced options such as `ip_source`, `interface`, `bind_network`, and retry intervals.
4. Reload the service: `/etc/init.d/ddns reload`

> Tip: Enable detailed logs with `option use_logfile '1'` and inspect `/var/log/ddns/<section>.log`.

## Development Notes
- Core helper logic lives in `files/usr/lib/ddns/`, including the generic updater and provider adapters.
- Utility scripts such as `dynamic_dns_functions.sh` can be sourced in custom provider implementations.
- Run `./files/usr/bin/ddns.sh --help` on the router to inspect available CLI parameters.

## Contributing
1. Fork the repository and create a feature branch.
2. Add or update provider scripts under `files/usr/lib/ddns/`.
3. Update `files/etc/config/ddns` defaults when new options are introduced.
4. Provide relevant translations and documentation.
5. Submit a pull request with testing notes (provider, IPv4/IPv6 path, etc.).

## License
The scripts follow the licensing model used by OpenWrt packages (typically GPL-2.0). Refer to the file headers for exact terms.

## Differences from ImmortalWrt
- Enhanced IPv6 neighbour handling: helper utilities expose richer metadata consumed by the companion LuCI app (see `../luci-app-ddns`).
- Documentation now highlights IPv6-specific configuration paths and verification workflows.
- Base logic otherwise tracks ImmortalWrt; any bug fixes are contributed upstream when possible.

</details>

<details>
<summary><strong>中文</strong></summary>

## 项目简介
`ddns-scripts` 是 OpenWrt 平台上用于刷新动态 DNS 记录的核心脚本集合。它作为 `/etc/init.d/ddns` 服务的后台程序，自动检测当前 IPv4/IPv6 地址，并调用各个运营商的更新接口，确保域名始终解析到路由器最新的公网地址。

## 功能亮点
- 通过可插拔脚本支持数十家常见的动态 DNS 服务商。
- 同时处理 IPv4、IPv6 地址，支持 SLAAC 邻居及自定义检测 URL。
- 多种 IP 源选择：网络接口、设备、外部网页检测或自定义脚本。
- 详细的日志机制：每个服务独立 log 文件，并可选同步到 syslog。
- `samples/` 目录提供示例配置，方便快速上手。

## 环境要求
- 建议使用 OpenWrt 21.02 或更新版本（旧版本未全面验证）。
- 需具备 `busybox`，以及 `wget` 或 `curl`（部分 HTTPS 服务需额外安装 SSL 库）。
- 如果需要自定义 DNS 查询，建议安装 `bind-host`、`drill` 或 `knot-host` 等工具。

## 安装部署
```sh
opkg update
opkg install ddns-scripts
# 根据需要额外安装具体服务脚本
opkg install ddns-scripts_cloudflare-v4 ddns-scripts_godaddy
```

开发调试时，可将 `files/` 下的文件同步到路由器根目录，然后重启服务：
```sh
/etc/init.d/ddns restart
```

## 配置步骤
1. 参考 `samples/ddns.config_sample` 创建或编辑 `/etc/config/ddns`。
2. 针对每个服务定义所需字段：
   - `service_name`（或自定义 `update_url` / `update_script`）
   - `lookup_host`
   - `use_ipv6`（0 或 1）
3. 视需求调整高级选项，如 `ip_source`、`interface`、`bind_network`、重试间隔等。
4. 执行 `/etc/init.d/ddns reload` 使配置生效。

> 小提示：开启 `option use_logfile '1'` 可在 `/var/log/ddns/<section>.log` 查看详细日志。

## 开发者须知
- 核心实现位于 `files/usr/lib/ddns/`，包含通用更新逻辑与各服务适配器。
- `dynamic_dns_functions.sh` 等工具脚本可在自定义服务脚本中复用。
- 在路由器上执行 `./files/usr/bin/ddns.sh --help` 可查看命令行参数说明。

## 参与贡献
1. Fork 仓库并创建功能分支。
2. 在 `files/usr/lib/ddns/` 中新增或更新服务脚本。
3. 若引入新配置项，请同步更新 `files/etc/config/ddns` 默认设置。
4. 记得完善相关文档与翻译。
5. 提交 Pull Request 时附上测试说明（服务商、IPv4/IPv6 测试路径等）。

## 许可协议
脚本遵循 OpenWrt 软件包通用的授权方式（通常为 GPL-2.0）。具体条款请参考各文件头部声明。

## 与 ImmortalWrt 原版的差异
- 强化 IPv6 邻居处理：工具脚本输出更丰富的信息，供配套的 LuCI 前端（见 `../luci-app-ddns`）使用。
- 文档重点说明 IPv6 的配置路径与校验流程，方便部署者快速上手。
- 其余核心逻辑与 ImmortalWrt 主线保持一致，若有修复会尽量回馈上游。

</details>
