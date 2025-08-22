# 语音转文字 iOS 应用

这是一个iOS应用，可以自动录制音频、发送到web服务器进行语音转文字，并保存转换结果。

## 功能特性

- 🎤 自动连续录音
- 🔇 智能静音检测（2秒静音后自动停止）
- ⏱️ 最大录音时长限制（30秒）
- 🌐 自动发送音频到web服务器
- 💾 本地存储转换结果
- 🔄 循环录音直到手动停止

## 技术架构

- **SwiftUI**: 现代化UI框架
- **SwiftData**: 本地数据存储
- **AVFoundation**: 音频录制
- **Combine**: 响应式编程
- **URLSession**: 网络请求

## 文件结构

```
mike/
├── ContentView.swift          # 主界面
├── RecordingManager.swift     # 录音管理协调器
├── AudioRecorder.swift        # 音频录制核心
├── TranscriptionService.swift # 网络服务
├── Item.swift                # 数据模型
└── Info.plist               # 权限配置
```

## 配置说明

### 1. Web服务器配置

在 `TranscriptionService.swift` 中修改 `baseURL` 为你的实际服务器地址：

```swift
private let baseURL = "http://your-server.com:8000"
```

### 2. 录音参数配置

在 `AudioRecorder.swift` 中可以调整以下参数：

```swift
let maxRecordingDuration: TimeInterval = 30.0  // 最大录制时长
let silenceThreshold: TimeInterval = 2.0       // 静音检测阈值
let silenceLevel: Float = -50.0                // 静音分贝阈值
```

## 使用方法

1. 启动应用
2. 点击"开始连续录音"按钮
3. 应用会自动开始录音
4. 当检测到静音或达到最大时长时，自动停止并发送到服务器
5. 获取转换结果后，立即开始下一段录音
6. 点击"停止录音"按钮结束连续录音

## 权限要求

应用需要以下权限：
- 麦克风访问权限（用于录音）

## 注意事项

- 确保web服务器正在运行且可访问
- 网络连接稳定以确保音频文件传输成功
- 首次使用时会请求麦克风权限

## 开发环境

- Xcode 15.0+
- iOS 17.0+
- Swift 5.9+

