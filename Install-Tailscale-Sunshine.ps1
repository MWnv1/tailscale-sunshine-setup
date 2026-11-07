<#
.SYNOPSIS
  Tailscale + Sunshine 一键自动化部署，并自动生成 Moonlight 最新版下载二维码。

.DESCRIPTION
  1. 用 winget 自动拉取 Tailscale / Sunshine 官方最新稳定版（已装则升级）
  2. 启动 Tailscale 并引导登录，读取本机 Tailscale 虚拟 IP
  3. 放行 Sunshine 所需防火墙端口，重启服务
  4. 通过 GitHub API 自动获取 Moonlight 最新 release 的直链
  5. 把 Moonlight 与 Tailscale 的下载链接分别生成二维码 PNG，手机扫码即可下载

.PARAMETER QrTarget
  二维码指向哪个平台的最新安装包：
    android  - Moonlight Android APK（手机扫码，默认）
    windows  - Moonlight PC 的 Windows 安装包
    both     - 两个二维码都生成
    page     - 不取安装包，直接指向 Moonlight 官方下载页

.PARAMETER TsQrTarget
  Tailscale 手机客户端的下载二维码：
    android  - Google Play 商店页（默认）
    ios      - Tailscale 官方 iOS 下载页
    both     - 两个都生成
    page     - 官方总下载页

.PARAMETER QrOutDir
  二维码 PNG 的保存目录，默认当前用户桌面。

.EXAMPLE
  .\Install-Tailscale-Sunshine.ps1

.EXAMPLE
  .\Install-Tailscale-Sunshine.ps1 -QrTarget both -QrOutDir D:\qr
#>

#Requires -RunAsAdministrator
param(
    [ValidateSet("android", "windows", "both", "page")]
    [string]$QrTarget = "android",

    [ValidateSet("android", "ios", "both", "page")]
    [string]$TsQrTarget = "android",

    [string]$QrOutDir = [Environment]::GetFolderPath("Desktop")
)

$ErrorActionPreference = "Stop"

# -------------------------- 配置区 --------------------------
$SunshineFirewallPorts = @("47981", "47984", "47985", "47986", "47989", "47990")
$TailscaleExe = "C:\Program Files\Tailscale\tailscale.exe"
$LogFile = Join-Path $env:USERPROFILE "sunshine_tailscale_install.log"
$MoonlightPcRepo = "moonlight-stream/moonlight-qt"
$MoonlightAndroidRepo = "moonlight-stream/moonlight-android"
$MoonlightPageUrl = "https://moonlight-stream.org/"
$MoonlightAndroidStoreUrl = "https://play.google.com/store/apps/details?id=com.limelight"
$TailscaleDownloadUrl = "https://tailscale.com/download"
$TailscaleAndroidUrl = "https://play.google.com/store/apps/details?id=com.tailscale.ipn"
$TailscaleIosUrl = "https://tailscale.com/download/ios"
# -----------------------------------------------------------

function Write-Log {
    param([string]$Msg, [string]$Color = "Gray")
    $t = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$t] $Msg"
    Write-Host $line -ForegroundColor $Color
    try { Add-Content -Path $LogFile -Value $line -Encoding UTF8 } catch { }
}

function Test-Winget {
    try {
        Get-Command winget -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function Install-Or-Upgrade {
    param([string]$Id, [string]$Name)
    try {
        $listed = winget list --id $Id --accept-source-agreements 2>$null
        if ($listed -match [regex]::Escape($Id)) {
            Write-Log "检测到 $Name 已安装，执行升级" "Cyan"
            winget upgrade --id $Id -e --silent --accept-package-agreements --accept-source-agreements
        }
        else {
            Write-Log "开始安装 $Name" "Cyan"
            winget install --id $Id -e --silent --accept-package-agreements --accept-source-agreements
        }
        Write-Log "$Name 处理完成" "Green"
    }
    catch {
        Write-Log "$Name 安装/升级异常：$($_.Exception.Message)" "Yellow"
    }
}

function Get-TailscaleIps {
    try {
        if (-not (Test-Path $TailscaleExe)) { return $null }
        $json = & $TailscaleExe status --json 2>$null | Out-String
        $obj = $json | ConvertFrom-Json
        return $obj.Self.TailscaleIPs
    }
    catch {
        return $null
    }
}

function Get-LatestRelease {
    param([string]$Repo)
    $headers = @{ "User-Agent" = "sunshine-installer-script" }
    if ($env:GITHUB_TOKEN) { $headers["Authorization"] = "token $env:GITHUB_TOKEN" }
    return Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" `
        -Headers $headers -TimeoutSec 30
}

function Select-Asset {
    param(
        [object]$Release,
        [string]$Pattern,
        [string[]]$Prefer
    )
    $assets = $Release.assets
    if (-not $assets) { return $null }

    $matched = $assets | Where-Object { $_.name -match $Pattern }
    if (-not $matched) { return $null }

    if ($Prefer) {
        foreach ($kw in $Prefer) {
            $hit = $matched | Where-Object { $_.name -match $kw } | Select-Object -First 1
            if ($hit) { return $hit }
        }
    }
    return ($matched | Select-Object -First 1)
}

function Get-QRCoderDll {
    $cache = Join-Path $env:LOCALAPPDATA "pstools-qrcoder"
    $dll = Join-Path $cache "QRCoder.dll"
    if (Test-Path $dll) { return $dll }

    try {
        Write-Log "首次运行，下载本地二维码生成库 QRCoder" "DarkGray"
        New-Item -ItemType Directory -Force -Path $cache | Out-Null
        $pkg = Join-Path $cache "qrcoder.zip"
        Invoke-WebRequest -Uri "https://www.nuget.org/api/v2/package/QRCoder" `
            -OutFile $pkg -UseBasicParsing -TimeoutSec 40
        Expand-Archive -Path $pkg -DestinationPath $cache -Force

        $candidates = @(
            (Join-Path $cache "lib\netstandard2.0\QRCoder.dll"),
            (Join-Path $cache "lib\net40\QRCoder.dll"),
            (Join-Path $cache "lib\netstandard1.3\QRCoder.dll"),
            (Join-Path $cache "lib\net6.0\QRCoder.dll")
        )
        foreach ($c in $candidates) {
            if (Test-Path $c) {
                Copy-Item $c $dll -Force
                return $dll
            }
        }
    }
    catch {
        Write-Log "QRCoder 下载/解压失败，将退回在线生成" "Yellow"
    }
    return $null
}

function Test-PngFile {
    param([string]$Path)
    try {
        if (-not (Test-Path $Path)) { return $false }
        if ((Get-Item $Path).Length -lt 200) { return $false }
        $head = [System.IO.File]::ReadAllBytes($Path)
        if ($head.Length -lt 8) { return $false }
        # PNG 魔数 0x89 0x50 0x4E 0x47
        return ($head[0] -eq 0x89 -and $head[1] -eq 0x50 -and $head[2] -eq 0x4E -and $head[3] -eq 0x47)
    }
    catch {
        return $false
    }
}

function New-QrPng {
    param(
        [string]$Text,
        [string]$OutFile
    )

    # 方案一：本地 QRCoder（PngByteQRCode 为纯托管实现，不依赖 GDI）
    # 注意：这里必须用 byte[] 重载，QRCoder 的 string 重载带可选参数，PowerShell 匹配不上
    try {
        $dll = Get-QRCoderDll
        if ($dll) {
            if (-not ("QRCoder.QRCodeGenerator" -as [type])) {
                [System.Reflection.Assembly]::LoadFrom($dll) | Out-Null
            }
            $gen = [QRCoder.QRCodeGenerator]::new()
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
            $data = $gen.CreateQrCode($bytes, [QRCoder.QRCodeGenerator+ECCLevel]::Q)
            $png = [QRCoder.PngByteQRCode]::new()
            $png.SetQRCodeData($data)
            [System.IO.File]::WriteAllBytes($OutFile, $png.GetGraphic(12, $true))
            if (Test-PngFile -Path $OutFile) { return $true }
        }
    }
    catch {
        Write-Log "本地生成二维码失败：$($_.Exception.Message)" "Yellow"
    }

    # 方案二：在线二维码接口
    $apis = @(
        "https://api.qrserver.com/v1/create-qr-code/?size=640x640&margin=16&data=",
        "https://api.pwmqr.com/qrcode/create/?size=640&url="
    )
    foreach ($api in $apis) {
        try {
            Invoke-WebRequest -Uri ($api + [Uri]::EscapeDataString($Text)) `
                -OutFile $OutFile -UseBasicParsing -TimeoutSec 25
            if (Test-PngFile -Path $OutFile) { return $true }
        }
        catch {
            continue
        }
    }

    # 方案三：兜底，至少把链接交到手上
    try {
        Set-Clipboard -Value $Text
        Start-Process $Text
    }
    catch { }
    return $false
}

function Convert-Moonlight {
    param(
        [string]$Target,
        [string]$OutDir
    )

    $results = @()

    if ($Target -eq "page") {
        $results += [pscustomobject]@{
            Platform = "官方下载页"
            Version  = "-"
            Url      = $MoonlightPageUrl
        }
        return $results
    }

    if ($Target -eq "android" -or $Target -eq "both") {
        try {
            Write-Log "查询 Moonlight Android 最新版本" "Cyan"
            $rel = Get-LatestRelease $MoonlightAndroidRepo
            $asset = Select-Asset -Release $rel -Pattern "\.apk$" -Prefer @("arm64", "universal")
            if (-not $asset) {
                Write-Log "Android release 里没有 APK，二维码改为指向 Google Play" "Yellow"
                $results += [pscustomobject]@{
                    Platform = "Android（Google Play）"
                    Version  = $rel.tag_name
                    Url      = $MoonlightAndroidStoreUrl
                }
            }
            else {
                $results += [pscustomobject]@{
                    Platform = "Android"
                    Version  = $rel.tag_name
                    Url      = $asset.browser_download_url
                }
            }
        }
        catch {
            Write-Log "查询 Android 版本失败：$($_.Exception.Message)" "Yellow"
            $results += [pscustomobject]@{
                Platform = "Android（Google Play）"
                Version  = "-"
                Url      = $MoonlightAndroidStoreUrl
            }
        }
    }

    if ($Target -eq "windows" -or $Target -eq "both") {
        try {
            Write-Log "查询 Moonlight PC 最新版本" "Cyan"
            $rel = Get-LatestRelease $MoonlightPcRepo
            $asset = Select-Asset -Release $rel -Pattern "\.exe$" -Prefer @("Setup", "x64", "win")
            if (-not $asset) {
                Write-Log "没在 PC release 里找到 .exe，退回官方下载页" "Yellow"
                $results += [pscustomobject]@{
                    Platform = "Windows（官方页）"
                    Version  = $rel.tag_name
                    Url      = $MoonlightPageUrl
                }
            }
            else {
                $results += [pscustomobject]@{
                    Platform = "Windows"
                    Version  = $rel.tag_name
                    Url      = $asset.browser_download_url
                }
            }
        }
        catch {
            Write-Log "查询 Windows 版本失败：$($_.Exception.Message)" "Yellow"
            $results += [pscustomobject]@{
                Platform = "Windows（官方页）"
                Version  = "-"
                Url      = $MoonlightPageUrl
            }
        }
    }

    return $results
}

function Convert-Tailscale {
    param([string]$Target)

    $android = [pscustomobject]@{ Platform = "Android"; Version = "官方最新"; Url = $TailscaleAndroidUrl }
    $ios     = [pscustomobject]@{ Platform = "iOS";     Version = "官方最新"; Url = $TailscaleIosUrl }
    $page    = [pscustomobject]@{ Platform = "下载页";  Version = "-";        Url = $TailscaleDownloadUrl }

    switch ($Target) {
        "android" { return @($android) }
        "ios"     { return @($ios) }
        "both"    { return @($android, $ios) }
        "page"    { return @($page) }
        default   { return @($android) }
    }
}

function New-QrBatch {
    param(
        [object[]]$Targets,
        [string]$Prefix,
        [string]$OutDir
    )

    $files = @()
    if (-not $Targets) { return $files }

    foreach ($t in $Targets) {
        if (-not $t -or -not $t.Url) { continue }
        $safeName = ($t.Platform -replace '[\\/:*?"<>|]', '_')
        $pngPath = Join-Path $OutDir ($Prefix + "_QR_" + $safeName + ".png")
        Write-Log "生成二维码：$Prefix - $($t.Platform)  $($t.Version)" "Cyan"
        if (New-QrPng -Text $t.Url -OutFile $pngPath) {
            $files += $pngPath
            Write-Log "  -> $pngPath" "Green"
        }
        else {
            Write-Log "  -> 二维码生成失败，已复制链接并尝试打开" "Yellow"
        }
    }
    return $files
}

# ======================= 主流程 =======================

Write-Log "======= 开始部署 Tailscale + Sunshine =======" "White"

if (-not (Test-Winget)) {
    Write-Log "未检测到 winget。请先在 Microsoft Store 更新「应用安装程序」。" "Red"
    Read-Host "按回车退出"
    exit 1
}
Write-Log "winget 就绪" "Green"

# 1. Tailscale
Install-Or-Upgrade -Id "Tailscale.Tailscale" -Name "Tailscale"

# 2. 启动并登录
Write-Log "启动 Tailscale 服务" "Cyan"
try { Start-Service Tailscale -ErrorAction SilentlyContinue } catch { }
if (Test-Path $TailscaleExe) {
    Write-Log "执行 tailscale up，请在弹窗/浏览器完成账号授权" "Cyan"
    try { & $TailscaleExe up } catch { Write-Log "tailscale up 需要你手动完成登录" "Yellow" }
    Start-Sleep -Seconds 3
}

$tsIps = Get-TailscaleIps

# 3. Sunshine
Install-Or-Upgrade -Id "LizardByte.Sunshine" -Name "Sunshine"

# 4. 防火墙
Write-Log "配置防火墙放行 Sunshine 端口（TCP + UDP）" "Cyan"
foreach ($p in $SunshineFirewallPorts) {
    $tcpName = "Sunshine-TCP-$p"
    $udpName = "Sunshine-UDP-$p"

    if (-not (Get-NetFirewallRule -Name $tcpName -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name $tcpName -DisplayName $tcpName -Direction Inbound `
            -Protocol TCP -LocalPort $p -Action Allow -Profile Any | Out-Null
    }
    if (-not (Get-NetFirewallRule -Name $udpName -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name $udpName -DisplayName $udpName -Direction Inbound `
            -Protocol UDP -LocalPort $p -Action Allow -Profile Any | Out-Null
    }
}
Write-Log "防火墙规则已配置" "Green"

# 5. 重启服务
try {
    Restart-Service Sunshine -ErrorAction Stop
    Write-Log "Sunshine 服务已重启" "Green"
}
catch {
    Write-Log "Sunshine 服务重启失败，请在服务面板手动启动" "Yellow"
}

# 6. Moonlight / Tailscale 最新直链 + 二维码
if (-not (Test-Path $QrOutDir)) {
    New-Item -ItemType Directory -Force -Path $QrOutDir | Out-Null
}

$moonTargets = @(Convert-Moonlight -Target $QrTarget -OutDir $QrOutDir)
$tsTargets = @(Convert-Tailscale -Target $TsQrTarget)

$qrFiles = @()
$qrFiles += @(New-QrBatch -Targets $moonTargets -Prefix "Moonlight" -OutDir $QrOutDir)
$qrFiles += @(New-QrBatch -Targets $tsTargets -Prefix "Tailscale" -OutDir $QrOutDir)

# ======================= 汇总 =======================

Write-Host ""
Write-Host "==================== 部署结果 ====================" -ForegroundColor White

if ($tsIps) {
    Write-Host "本机 Tailscale IP：" -ForegroundColor Green
    foreach ($ip in $tsIps) { Write-Host "   $ip" -ForegroundColor Green }
    Write-Host "Moonlight 里添加主机时，直接填上面任意一个 IP"
}
else {
    Write-Host "未读到 Tailscale IP：确认 tailscale up 已登录成功，然后手动执行 tailscale ip" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Sunshine 管理界面： http://localhost:47990" -ForegroundColor Cyan
Write-Host "首次进入需设置用户名密码，之后在 Moonlight 端输入配对 PIN 完成配对"

Write-Host ""
Write-Host "Moonlight（串流客户端）下载：" -ForegroundColor Cyan
foreach ($t in $moonTargets) {
    Write-Host ("   [{0}] {1}  {2}" -f $t.Platform, $t.Version, $t.Url)
}

Write-Host ""
Write-Host "Tailscale（手机端）下载：" -ForegroundColor Cyan
foreach ($t in $tsTargets) {
    Write-Host ("   [{0}] {1}  {2}" -f $t.Platform, $t.Version, $t.Url)
}

Write-Host ""
Write-Host "接下来怎么连（详见 README-Setup.md）：" -ForegroundColor White
Write-Host "  1. 手机装 Moonlight + Tailscale，Tailscale 登录和这台电脑同一个账号"
Write-Host "  2. 电脑浏览器开 http://localhost:47990 设好 Sunshine 账号密码"
Write-Host "  3. Moonlight 里点 + 添加主机，地址填上面那串 Tailscale IP"
Write-Host "  4. 电脑 Sunshine 界面会弹出 4 位 PIN，在手机 Moonlight 里输入即完成配对"

if ($qrFiles.Count -gt 0) {
    Write-Host ""
    Write-Host "二维码已生成，手机扫码直接下载：" -ForegroundColor Green
    foreach ($f in $qrFiles) { Write-Host "   $f" }
    try { Start-Process (Split-Path $qrFiles[0] -Parent) } catch { }
}

Write-Host ""
Write-Host "日志文件： $LogFile" -ForegroundColor DarkGray
Write-Host "==================================================" -ForegroundColor White

Read-Host "按回车关闭窗口"
