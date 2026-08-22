# HHJControl

HHJControl 是面向 iOS 26 的原生 HHJ 尾插控制器。项目使用 UIKit 生命周期、SwiftUI 界面与 UIKit `MKMapView`，通过已验证的 CoreBluetooth GATT 协议连接兼容硬件。

App 本身不能通过公开 iOS API 修改系统定位。实际效果依赖兼容 HHJ 尾插：App 将选择的坐标编码为硬件协议并通过 BLE 写入，随后由硬件向 iPhone 提供 GPS 数据。

## 功能

- 按原版设备名规则筛选 HHJ 尾插，并以服务 UUID 验证兼容性
- 严格的连接、服务发现、认证与有界前台重连状态机
- 地图拖动中心、长按、当前位置与独立地址搜索
- 以 WGS-84 保存和发送位置，并按当前 MapKit 坐标表现校准中国地图选点
- 海拔编辑、收藏、最近记录与遮盖认证信息的诊断日志
- 原生 iOS 26 Tab/Search 与 Liquid Glass
- 本机 Codable JSON 存储；无账号、统计 SDK 或第三方 Framework

## 下载与安装

最新版本与 IPA 下载位于 [Releases](https://github.com/ccyykk666/HHJControl/releases)。下载 IPA 后，请使用自签名方式安装。
