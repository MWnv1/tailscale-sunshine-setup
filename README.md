# Tailscale + Sunshine 一键部署（Windows）

一条命令，把 Windows 电脑变成**可以从任何网络串流的被控端**：自动装好 Tailscale 与 Sunshine、放行防火墙、读取虚拟内网 IP，并生成手机端客户端的下载二维码。

不需要公网 IP，不需要端口映射，不需要碰光猫。

---

## 它做了什么

| 步骤 | 内容 |
|---|---|
| 1 | 用 winget 安装或升级 Tailscale（官方最新稳定版） |
| 2 | 拉起 Tailscale 登录流程，读取本机 `100.x.x.x` 虚拟 IP |
| 3 | 用 winget 安装或升级 Sunshine |
| 4 | 放行 47981 / 47984 / 47985 / 47986 / 47989 / 47990（TCP + UDP） |
| 5 | 重启 Sunshine 服务，确认开机自启 |
| 6 | 通过 GitHub API 取 Moonlight 最新 release 直链 |
| 7 | 本地生成 Moonlight / Tailscale 下载二维码 PNG 到桌面 |

脚本执行完会打印 Tailscale IP、Sunshine 管理地址、以及配对的四个步骤。

---

## 快速开始

```powershell
# 管理员身份打开 PowerShell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser    # 只需执行一次

.\Install-Tailscale-Sunshine.ps1
```

跑完桌面上会出现二维码 PNG，手机扫码即可下载客户端。

### 参数

```powershell
.\Install-Tailscale-Sunshine.ps1 -QrTarget android -TsQrTarget android -QrOutDir D:\qr
```

| 参数 | 可选值 | 说明 |
|---|---|---|
| `-QrTarget` | `android`（默认）/ `windows` / `both` / `page` | Moonlight 控制端二维码指向 |
| `-TsQrTarget` | `android`（默认）/ `ios` / `both` / `page` | Tailscale 客户端二维码指向 |
| `-QrOutDir` | 任意路径 | 二维码保存目录，默认桌面 |

### 生成的二维码

| 文件 | 内容 |
|---|---|
| `Moonlight_QR_Android.png` | Moonlight 官方最新 APK 直链 |
| `Moonlight_QR_Windows.png` | Moonlight PC 安装包直链（`-QrTarget windows/both` 时生成） |
| `Tailscale_QR_Android.png` | Tailscale Google Play 商店页 |
| `Tailscale_QR_iOS.png` | Tailscale 官方 iOS 下载页（`-TsQrTarget ios/both` 时生成） |

---

## 脚本跑完之后，还有三步必须手动做

**这三步替代不了，必须你本人操作。**

1. **Tailscale 两端登录同一个账号** — 电脑和手机登不同账号 = 两个永不相通的网
2. **后台关掉设备密钥过期** — `login.tailscale.com/admin/machines` → 三个点 → Disable key expiry。不关的话 90 天后突然断连，极难排查
3. **Sunshine 设管理账号 + Moonlight 配对** — 浏览器开 `http://localhost:47990` 设账号；手机 Moonlight 里添加主机填 `100.x.x.x`，电脑弹 4 位 PIN，手机输入完成配对

完整的组网、配置、配对、排错流程见 **[README-Setup.md](README-Setup.md)**。

---

## 环境要求

- Windows 10 / 11
- PowerShell 5.1 或更高（系统自带即可）
- 管理员权限（脚本用了 `#Requires -RunAsAdministrator`）
- 可用的 `winget`（Microsoft Store 里的「应用安装助手 / App Installer」）

---

## 技术细节

**二维码生成完全本地。** 使用 QRCoder 的 `PngByteQRCode`（纯托管实现，不依赖 GDI），首次运行时自动从 NuGet 下载一次并缓存到 `%LOCALAPPDATA%\pstools-qrcoder`。失败时依次回退到在线接口、最后兜底复制链接到剪贴板。你的网络信息不会外传。

**Moonlight 版本自动获取。** 不硬编码版本号，走 GitHub API 的 `releases/latest` 取资产直链，用后缀 + 关键词匹配（`.apk` 优先 arm64/universal，`.exe` 优先 Setup）。拿不到资产时回退到商店页或官网，不会卡死。

**GitHub API 匿名限流每小时 60 次。** 反复执行可能撞限流，表现为"查询失败→回退官网页"。想避开就设环境变量：

```powershell
$env:GITHUB_TOKEN = "ghp_xxxx"
```

脚本会读取这个变量，带 token 的配额高得多。

---

## 已知限制

- **仅支持 Windows。** 依赖 `winget`、`New-NetFirewallRule`、`Get-Service` 等 Windows 专有组件，Linux / macOS 跑不了。
- **首次运行需要联网。** 装软件、取版本、下 QRCoder 都要网络；之后的二维码生成是离线的。
- **防火墙规则会长期留在系统里。** 脚本建立的 6 条 TCP + 6 条 UDP 规则不会自动清理，卸载时需手动删除（规则名 `Sunshine-TCP-<端口>` / `Sunshine-UDP-<端口>`）。

### 验证状态说明

出于透明，明确区分哪些跑过、哪些没有：

| 部分 | 状态 |
|---|---|
| 脚本语法 | 已用 PowerShell 7.4.6 解析器验证通过（零错误） |
| 二维码生成 | 已实际运行，生成 PNG 并用 OpenCV 解码回读，内容与目标 URL 一致 |
| `winget` 安装 / 防火墙规则 / 服务重启 | **未在 Windows 实机验证**，逻辑沿用常见写法，请首次执行后自行核对 |

---

## 免责声明

本脚本会**安装第三方软件**并**修改系统防火墙规则**，均需要管理员权限。执行前请自行评估。

- 只从 `winget` 官方源安装 Tailscale 与 Sunshine
- 只新增入站放行规则，不改动现有规则
- 不上传任何本机信息到第三方服务器（除 GitHub API 查询版本号外）

Tailscale、Sunshine、Moonlight 均为各自的独立开源项目，本仓库只做安装编排，与它们无隶属关系，也不对其行为负责。

---

## License

[Apache License 2.0](LICENSE) © 2026 MWnv1

## 致谢

- [Tailscale](https://tailscale.com/) — 虚拟内网组网
- [Sunshine](https://github.com/LizardByte/Sunshine)（LizardByte）— 游戏串流服务端
- [Moonlight](https://github.com/moonlight-stream) — 串流客户端
- [QRCoder](https://github.com/codebude/QRCoder) — 二维码生成
