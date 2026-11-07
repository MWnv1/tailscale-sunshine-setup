# Tailscale 组网 + Sunshine 串流 + Moonlight 配对：完整配置手册

配套脚本：`Install-Tailscale-Sunshine.ps1`

脚本能自动装软件、开防火墙、出二维码，但它**替代不了账号登录和配对**这两步 —— 这两件事必须你本人操作。本文就是补上这部分。

---

## 0. 先理清楚这套东西在干什么

```
[手机 Moonlight]                    [家里电脑 Sunshine]
       │                                    │
       │  ① 输入 100.x.x.x 这个地址          │
       └───────────┐        ┌───────────────┘
                   ↓        ↓
            ┌─────────────────────┐
            │   Tailscale 虚拟内网  │   ← 两台设备都登录同一个账号
            │  （100.64.0.0/10）   │
            └─────────────────────┘
                     ↓
              ② 电脑弹 4 位 PIN
              ③ 手机输入 PIN → 配对成功
              ④ 手机开始串流游戏画面
```

**核心认知：Tailscale 不是 VPN 服务器，是一个"把设备拉进同一个虚拟局域网"的组网工具。** 你不需要公网 IP、不需要碰光猫、不需要端口映射。两台设备登录同一账号，就自动在一个网里，互相能直连。

**Sunshine 是"被控端"（跑在电脑上），Moonlight 是"控制端"（跑在手机/另一台电脑上）。**

---

## 1. 第一步：跑脚本，让它做完能自动做的部分

```powershell
# 管理员身份打开 PowerShell
cd D:\你放脚本的目录
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser   # 只需执行一次
.\Install-Tailscale-Sunshine.ps1 -QrTarget android -TsQrTarget android
```

跑完你会得到：

- Tailscale 和 Sunshine 装好并升级到最新
- Sunshine 开机自启服务已注册
- 防火墙 47981 / 47984 / 47985 / 47986 / 47989 / 47990 已放行（TCP + UDP）
- 桌面上两张二维码 PNG：`Moonlight_QR_Android.png`、`Tailscale_QR_Android.png`
- 终端里打印出本机 Tailscale IP（形如 `100.x.x.x`）

> **如果脚本报 `tailscale up` 需要登录**，这是正常的，下一步处理。

---

## 2. Tailscale 配网（详细）

### 2.1 注册账号

浏览器打开 `https://login.tailscale.com/start`，用 Google / GitHub / Microsoft 账号直接登录，或邮箱注册。

**关键：手机端和电脑端必须登录同一个账号。** 这是整套方案能通的前提，登录不同账号 = 两个永不相通的网。

免费额度：个人版 3 台设备 / 100 台设备（Personal Plus 免费额度更大），家用完全够。

### 2.2 电脑端登录

脚本已经跑过 `tailscale up`，但可能停在"等待授权"。如果没有，手动执行：

```powershell
# 管理员 PowerShell
cd "C:\Program Files\Tailscale"
.\tailscale.exe up
```

它会打印一个 URL，复制到浏览器打开，点 **Connect / 授权**。

登录成功后验证：

```powershell
.\tailscale.exe status
```

输出里能看到 `100.x.x.x` 就是通了。也可以用：

```powershell
.\tailscale.exe ip -4
```

直接取这个 IP，一会儿 Moonlight 要填。

### 2.3 手机端安装并登录（扫码）

用手机扫桌面上那张 `Tailscale_QR_Android.png`：

- 安卓 → 跳 Google Play 商店页
- iOS → 跳 Tailscale 官方 iOS 下载页（中国区 App Store 可能搜不到，需切换其他区账号）

装好后打开 Tailscale，**用同一个账号登录**，点开关按钮打开 VPN 连接（手机会弹"允许建立 VPN 连接"，点允许）。

### 2.4 验证组网成功

三个地方都能看：

1. **电脑端**：`tailscale status`，能看到手机那台设备在线
2. **手机端**：Tailscale 应用里能看到电脑那台
3. **网页端**：`https://login.tailscale.com/admin/machines`，所有设备一览

手机上最简单的一招：再装个 `Termux` 或者用浏览器访问 `http://100.x.x.x:47990`（Sunshine 管理页），能打开就说明通。

### 2.5 必做：关掉密钥过期

这是最常见、最坑人的问题。

Tailscale 设备密钥**默认 90 天过期**。过期后设备显示 offline，你以为是网络坏了，折腾半天才发现是 key 掉了。

**必须在后台关掉：**

1. 打开 `https://login.tailscale.com/admin/machines`
2. 找到你要长期当被控端的那台电脑
3. 三个点 → **Disable key expiry**

手机端同样处理。不然每三个月要手动 re-auth 一次。

### 2.6 常见问题

| 现象 | 原因 | 处理 |
|---|---|---|
| `tailscale status` 显示 `Logged out` | 没完成授权 | `tailscale up` 重新走一遍浏览器授权 |
| 设备列表里有，但显示 `offline` | 电脑休眠/关机，或 key 过期 | 检查电源设置，关掉 key expiry |
| 手机端一直转圈 | 手机 Tailscale 没打开 VPN 开关 | 应用里把顶部开关打开 |
| 两台设备互相 ping 不通 | 登的不是同一个账号 | 检查后台 machines 页面，是不是分属两个 tailnet |
| 能 ping 通但端口连不上 | 电脑防火墙拦了 | 脚本已放行，若手动装过 Sunshine 需手动加规则 |
| 速度很慢（走 DERP 中转） | 双方 NAT 类型太严，打不通点对点 | 参见 2.7 |

### 2.7 进阶（可选，不影响基础使用）

**查看走的是直连还是中转：**

```powershell
tailscale ping 100.x.x.x
```

- 显示 `via 1.2.3.4:41641` → 点对点直连，速度最好
- 显示 `via DERP(某地区)` → 走中继服务器，延迟高

**加速直连：** 在路由器上开 UDP 41641 端口转发到这台电脑，能显著提高打洞成功率。家里有公网 IPv6 的话，Tailscale 会自动优先走 IPv6 直连。

**自建 DERP（折腾向）：** 有公网 VPS 可以自建中继服务器，国内延迟能降不少。不折腾就用官方 DERP，能用。

**远程访问整个局域网（Subnet Router）：** 让一台设备当网关，手机能访问家里所有设备（NAS、打印机等），不只是这一台电脑：

```powershell
# 在要当网关的那台 Windows 上
tailscale up --advertise-routes=192.168.1.0/24
```

然后去后台 `admin/machines` 那台机器上点 Edit route → 勾选通过。

---

## 3. Sunshine 首次配置

### 3.1 打开管理界面

**必须在电脑本机浏览器打开**（不是手机）：

```
http://localhost:47990
```

第一次打开会让你创建 Web 管理账号（用户名 + 密码，至少 8 位）。这个账号只用于管理界面，和 Moonlight 无关，记住就行。

### 3.2 设置里的三项关键配置

进入 **Configuration → Audio/Video**：

**① 编码器（Encoder）**

| 你的显卡 | 选这个 | 说明 |
|---|---|---|
| NVIDIA | `nvenc` | 硬件编码，延迟最低 |
| Intel 核显 | `quicksync` | 你的 Ultra5 选这个 |
| AMD | `amf` 或 `vaapi` | |
| 都没有 / 报错 | `software` | 软件编码，CPU 吃满但能用 |

保存后如果串流黑屏，第一个怀疑的就是编码器选错 —— 换成 `software` 试试，能出画面就说明是硬编配置问题。

**② 分辨率与刷新率**：设成和你的显示器一致。不要为了让手机流畅而降低，Moonlight 端可以单独调。

**③ 码率**：局域网/Tailscale 内串流，建议 20~50 Mbps。1080p60 建议 30 Mbps 起步。太低会糊，太高会卡。

### 3.3 应用列表

**Configuration → Applications**，默认有个 `Desktop`（整个桌面）。想直接串游戏，可以点 `+` 添加指定程序。

最简单的用法：**直接用 Desktop 就行**，进去之后自己开游戏。

### 3.4 确认服务在跑

```powershell
Get-Service Sunshine
```

状态应该是 `Running`。不是的话：

```powershell
Start-Service Sunshine
```

---

## 4. Moonlight 配对 Sunshine（重点）

### 4.1 手机装 Moonlight

扫 `Moonlight_QR_Android.png`，或去 GitHub 下 APK（脚本会打印最新直链）。

iOS 用户去 App Store 搜 `Moonlight Game Streaming`。

### 4.2 添加主机

打开 Moonlight，右上角 **+** 号：

```
电脑名称：随便填（比如"我的电脑"）
IP 地址：100.x.x.x         ← 这里是关键，填 Tailscale IP
```

**注意：绝对不能填 `192.168.x.x`。** 那是局域网地址，手机在 4G/5G 下根本到不了。除非你手机连的是同一个 WiFi 并且 Tailscale 关了 —— 那不是这套方案的本意。

IP 从哪来：

```powershell
tailscale ip -4
```

或者在后台 machines 页面看。

### 4.3 完成 PIN 配对

点添加后，手机会显示"正在配对..."，此时**电脑上会弹出 4 位 PIN**：

- 出现在 Sunshine 系统托盘图标的通知里
- 或出现在 `http://localhost:47990` 的 PIN 页面

在手机上输入这 4 位数字，配对完成。

成功后手机会出现电脑上配置的应用列表（Desktop 等）。

### 4.4 配对失败的排查表

这是绝大多数人卡住的地方，按顺序查：

| 现象 | 真正原因 | 怎么修 |
|---|---|---|
| 点添加后一直"正在配对"，电脑没弹 PIN | 手机根本没连到电脑 | 先在手机浏览器开 `http://100.x.x.x:47990`，打不开就是网络问题，回去查 Tailscale |
| 能打开 47990，但配对无反应 | 端口 47984/47989 被拦 | 检查防火墙规则是否存在（脚本建了 6 条） |
| 弹了 PIN，输入后报错 | PIN 超时（只有 60 秒） | 重新点添加，快一点输 |
| 报 "Unable to connect" | 编码器或显卡驱动问题 | 换 `software` 编码器再试 |
| 配对成功了但串流黑屏 | 编码器不对 / 显示器休眠 | 换编码器；把电源计划设成"高性能"，关掉显示器休眠 |
| 串流几秒就断 | 码率超过带宽 | 码率降到 15 Mbps 试 |
| 手机能看到电脑但列表是空的 | Sunshine 没配置任何应用 | 去 WebUI 的 Applications 加一个 Desktop |

### 4.5 首次串流建议设置

Moonlight 里点齿轮：

- **分辨率**：1080p
- **帧率**：60 FPS
- **码率**：20 Mbps（先低后高，稳定了再往上加）
- **HDR**：先关，跑通了再开
- **视频解码**：手机上选硬件解码（Hardware）

---

## 5. 两个二维码分别干什么

脚本会在桌面生成：

| 文件 | 内容 | 什么时候扫 |
|---|---|---|
| `Moonlight_QR_Android.png` | Moonlight 官方最新 APK 直链 | 手机装控制端时 |
| `Moonlight_QR_Windows.png` | Moonlight PC 安装包直链 | 用另一台电脑当控制端时 |
| `Tailscale_QR_Android.png` | Google Play 商店页 | 手机装组网客户端时 |
| `Tailscale_QR_iOS.png` | Tailscale 官方 iOS 下载页 | 苹果手机装组网客户端时 |

生成逻辑：Moonlight 走 GitHub API 取最新 release 的资产直链（拿不到就退商店/官网），Tailscale 走官方商店或下载页。全部本地画二维码，不外传你的任何信息。

---

## 6. 整条链路自检顺序

出问题时，**从下往上**查，别跳步：

```
① 两台设备 tailscale status 都显示 online？
       ↓ 是
② 手机浏览器能打开 http://100.x.x.x:47990 ？
       ↓ 是
③ 电脑 Get-Service Sunshine 是 Running ？
       ↓ 是
④ Moonlight 添加主机后电脑弹 PIN ？
       ↓ 是
⑤ 输入 PIN 成功，出现应用列表 ？
       ↓ 是
⑥ 进串流后画面正常不黑屏 ？
       ↓ 否 → 编码器
```

哪一步断了就停在哪一步修，前面的一定是好的。

---

## 7. 日常使用

- **电脑要保持开机**（睡眠可以，但要在电源设置里允许网络唤醒，或者干脆关掉睡眠）
- **手机连不上的第一件事**：看手机 Tailscale 是不是断开了（iOS 后台会被杀，安卓相对稳）
- **换网络不影响**：家里 WiFi、公司 WiFi、4G/5G，只要 Tailscale 连着就能串，这正是它的价值
- **更新**：直接重跑一遍脚本，会自动 upgrade

---

## 8. 一句话总结

**脚本负责"装好"，你负责"登录 + 配对"。** 剩下的坑基本都在两个地方：填错 IP（填了 192.168 而不是 100.x）、编码器选错。这两条占了九成故障。
