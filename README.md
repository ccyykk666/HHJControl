# HHJControl

HHJControl 是面向 iOS 26 的原生 HHJ 尾插控制器。项目使用 UIKit 生命周期、SwiftUI 界面与 UIKit `MKMapView`，通过已验证的 CoreBluetooth GATT 协议连接兼容硬件。

App 本身不能通过公开 iOS API 修改系统定位。实际效果依赖兼容 HHJ 尾插：App 将选择的坐标编码为硬件协议并通过 BLE 写入，随后由硬件向 iPhone 提供 GPS 数据。

## 功能

- 按原版设备名规则筛选 HHJ 尾插，并以服务 UUID 验证兼容性
- 严格的连接、服务发现、认证与有界前台重连状态机
- 地图拖动中心、长按、当前位置与独立地址搜索
- 中国范围 GCJ‑02 → WGS‑84，境外原样发送
- 海拔编辑、收藏、最近记录与遮盖认证信息的诊断日志
- 原生 iOS 26 Tab/Search 与 Liquid Glass
- 本机 Codable JSON 存储；无账号、自建网络请求、统计 SDK 或第三方 Framework

## 本地生成工程

需要 macOS 26、Xcode 26、XcodeGen：

```sh
brew install xcodegen
xcodegen generate
open HHJControl.xcodeproj
```

Bundle ID 固定为 `app.sagittarius9983.grape3949`，最低系统为 iOS 26.0。

## OTA 构建

工作流 `OTA Build` 只接受与 Bundle ID 精确匹配的手动签名材料。当前描述文件类型为 ad-hoc；如果选择 enterprise，工作流会在签名前明确失败。

首次建立仓库后，在 Windows PowerShell 中交互写入 Secrets（密码不会显示或进入 Git）：

```powershell
.\scripts\setup-secrets.ps1 -CertificatePath "C:\path\cert.p12" -ProvisioningProfilePath "C:\path\profile.mobileprovision"
```

然后运行：

```sh
gh workflow run "OTA Build" -R ccyykk666/HHJControl -f method=ad-hoc -f bundleId=app.sagittarius9983.grape3949 -f appName=HHJControl
gh run watch --exit-status -R ccyykk666/HHJControl
```

成功后，安装页位于 <https://ccyykk666.github.io/HHJControl/>，Release 标签为 `build-N`。

## 安全与隐私

仓库不包含原 IPA 的反编译代码、资源、README 或脚本，不包含证书、描述文件、Base64、密码或 Token。应用不声明蓝牙后台模式，不开放 ATS，不进行自建网络请求或数据上传；地点搜索与地址解析仅使用系统 MapKit。应用不跟踪或收集用户数据。
