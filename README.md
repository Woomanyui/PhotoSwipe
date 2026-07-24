# PhotoSwipe

<p align="center">
  <img src="PhotoSwipe/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="168" alt="PhotoSwipe App Icon">
</p>

<p align="center">
  <strong>把相册整理，变成简单自然的四向滑动。</strong>
</p>

<p align="center">
  <img alt="Platform" src="https://img.shields.io/badge/platform-iOS%2017%2B-black">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5-orange">
  <img alt="UI" src="https://img.shields.io/badge/UI-SwiftUI-blue">
  <img alt="Version" src="https://img.shields.io/badge/version-0.1.0-pink">
</p>

PhotoSwipe 是我为解决自己手机照片越积越多、逐张整理太麻烦的问题而做的一个
iOS 小项目。它用四个方向的滑动完成常见操作，也能按相册、日期和相似程度集中
检查照片。

这是一个本地优先的个人项目：照片和分析结果都留在设备上，不接入服务器、广告
或追踪 SDK。

## 我为什么做它

系统相册很适合查看照片，但大量清理时，频繁点选和切换操作会打断节奏。
PhotoSwipe 把整理过程设计成一组容易记住的手势：

| 操作 | 结果 |
| --- | --- |
| ← 左滑 | 加入待删除队列 |
| → 右滑 | 保留 |
| ↑ 上滑 | 加入系统收藏 |
| ↓ 下滑 | 加入已有相册，或新建相册后加入 |

删除不会立即发生。整理结束后还会显示汇总页面，并再次调用 Apple 的系统确认，
避免误删。

## 功能亮点

- 按全部照片、指定相册或自定义日期范围整理
- 记录已整理照片，下次启动时不会重复出现
- 支持撤销上一步和批量删除前的最终确认
- 自动播放 Live Photo，并可点击标记再次播放
- 查找当前范围内的相似照片，分组并排比较
- 显示相似照片的日期、文件大小、组内空间占比和分辨率
- 支持一次选择多张相似照片，但保证每组至少保留一张
- 支持 iPhone 镜像和外接键盘方向键操作
- 可管理相册权限、清除本地整理记录和待删除队列

## 技术实现

- **SwiftUI**：界面、导航、手势和键盘交互
- **PhotoKit**：照片授权、相册读取、收藏、归类和删除
- **差异哈希（dHash）**：在设备本地生成图像指纹并检查相似照片
- **UserDefaults**：保存已整理照片的本地标识
- **MVVM**：分离照片服务、整理状态和界面展示

相似照片检查最多分析当前范围内 500 张可在本机读取的照片，以控制等待时间和
设备资源消耗。

## 本地运行

### 环境

- macOS 与 Xcode 26 或更新版本
- iOS 17 或更新版本的 iPhone
- 一个可用于签名的 Apple ID

### 步骤

1. 克隆仓库并打开 `PhotoSwipe.xcodeproj`。
2. 在 Xcode 的 **Signing & Capabilities** 中选择自己的 Team。
3. 将 Bundle Identifier 改成属于自己的唯一标识。
4. 连接 iPhone，选择真机后点击 Run。
5. 首次启动时允许照片读写权限。

模拟器也可以运行，但需要先向模拟器照片图库添加测试照片。若这台 Mac 首次使用
Xcode，可能需要先在终端执行 `sudo xcodebuild -license` 并接受许可协议。

## 隐私设计

- 照片、缩略图和相似度分析结果不会上传
- App 不包含账号系统、广告、分析或追踪 SDK
- 只在设备本地保存已整理照片的 PhotoKit 标识
- 用户可以随时清除整理记录，且该操作不会删除照片
- 照片删除始终需要经过待删除队列和系统确认

更多信息见 [SECURITY.md](SECURITY.md)。

## 项目状态

当前版本为 **0.1.0**，已经完成核心整理流程并在 iPhone 真机运行。它目前是我
持续打磨的个人项目，还没有提交 App Store。

接下来计划：

- 补充单元测试和 UI 测试
- 优化大相册下的加载和相似照片分析速度
- 增加更完整的无障碍与多语言支持
- 准备 App Store 截图、隐私政策页面和审核材料

版本记录见 [CHANGELOG.md](CHANGELOG.md)。

## 作者

由 [@Woomanyui](https://github.com/Woomanyui) 设计与开发。

如果这个项目给了你一些灵感，欢迎点一个 Star。
