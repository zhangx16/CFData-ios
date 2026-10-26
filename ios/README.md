# CFData for iOS — 未签名 IPA

在 iPhone/iPad 当前网络上运行 Cloudflare IP 扫描、TCP/HTTP 延迟测试、测速和筛选。基于 PoemMisty/CFData-WEB；保留上游 GPL-3.0-or-later 许可。

## 从 GitHub 下载 IPA

直接打开 [最新 Release](https://github.com/zhangx16/CFData-ios/releases/latest)，下载 `CFData-ios-unsigned.ipa` 和 SHA-256 校验文件。每次构建成功后会自动创建 Release 并上传 IPA，无需 Apple 证书或 GitHub Secrets。

也可通过 **Actions → Build unsigned iOS IPA → Run workflow** 手动构建；Actions Artifacts 同样保留一份压缩包（30 天）。

**此 IPA 未签名，不能直接点击安装。** 下载后用自己的有效签名方式签名，再安装到允许的设备。支持 iOS/iPadOS 16.0 及以上、ARM64 真机；不包含模拟器。

## 使用

- 首次启动会下载数据中心等数据，需要网络；数据和缓存位于应用沙盒。
- 扫描和测速由嵌入应用进程的 Go 核心执行，测量的是手机当前网络到目标 IP 的链路。
- 导入支持“文件”选择器；导出通过系统分享菜单，可保存到“文件”。复制使用系统剪贴板。
- 切到后台或锁屏会取消正在运行的任务；返回前台可重新开始。WebKit 仍存活时保留已有表格；应用重启后可恢复最近一次结果（最多 1000 条），完整结果请及时导出。
- 扫描/测速期间尽量保持前台。测速会消耗流量，多 IP 同时测速会互相竞争带宽。
- 本项目不提供 VPN、系统流量接管或全局 IP 切换。

## 架构与构建

`prepare_core.py` 从 `combined_refactor/` 生成独立 Go 模块 `build/mobile`，不修改上游桌面/Android 源码。生成时添加沙盒路径、任务生命周期和本机服务认证适配，并在上游结构不匹配时直接报错。

Swift/UIKit + WKWebView 调用 gomobile 生成的静态 XCFramework。Go 核心在同一进程监听 `127.0.0.1:13335`，固定 origin 保持网页设置；随机启动令牌建立 HttpOnly Cookie，WebSocket 校验 Origin。

macOS 上安装 Xcode、与 `combined_refactor/go.mod` 匹配的 Go、XcodeGen，安装与工作流版本一致的 gomobile/gobind 并执行 `gomobile init`，然后：

```bash
bash ios/scripts/build_unsigned.sh
```

流水线先执行 Go 适配测试，再生成 XCFramework、构建真机 `.app`、检查 IPA 结构并上传产物。构建不运行任何 iPhone 硬件测试；下载 IPA 后仍需签名和真机验收。

## 真机验收

1. 签名安装、首次启动，确认界面和本机服务连接正常。
2. 导入少量已知目标，完成 TCP/HTTP 延迟测试和单 IP 下载测速。
3. 检查 IPv4/IPv6、Wi-Fi/蜂窝网络切换后的行为；切后台后任务应停止。
4. 复制结果，导出 CSV/TXT 到“文件”，重新打开应用确认设置保留。

## 来源

上游：https://github.com/PoemMisty/CFData-WEB

初始源码快照：`49d5571f4e44d1fe265c44f9fa289bc296b865f3`。上游文档见根目录 `README-upstream.md`，许可见 `LICENSE`。本改造包含完整源码，构建产物不包含 Apple 签名材料。
