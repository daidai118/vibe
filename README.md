# Vibe

Vibe 是一个 macOS 菜单栏音频工具,用于接管单个应用的系统输出音频,并在实时 DSP 链中做单应用音量、静音、输出设备路由和全局音效增强。

它基于 macOS Core Audio **Process Tap** API,因此可以在系统级捕获指定进程的音频,处理后再输出到目标设备。

## 功能特性

- 单应用音量控制:0–150%
- 单应用静音
- 单应用输出设备路由
- 全局 10 段 EQ
- 清晰度激励
- 动感响度
- 空间环绕
- 临场感混响
- 纯净低音增强
- 末级常开 lookahead 限幅器和软削波,避免叠加音效后明显破音
- 设置持久化到:

```text
~/Library/Application Support/Vibe/settings.json
```

## 系统要求

- macOS 14.4 或更高版本
- Xcode 15.3+ 或对应 Command Line Tools
- Swift 5.9+
- 首次运行需要授予「系统音频录制」权限

授权位置:

```text
系统设置 → 隐私与安全性 → 屏幕录制与系统音频录制
```

## 构建与运行

不要直接使用 `swift run` 运行。裸可执行文件没有完整 app bundle,系统音频录制权限弹窗可能不会正常出现,从而导致 Process Tap 创建失败。

请使用脚本构建 `.app`:

```bash
./scripts/build-app.sh
open build/Vibe.app
```

构建脚本会:

1. 执行 `swift build -c release`
2. 组装 `build/Vibe.app`
3. 写入 `Info.plist`
4. 使用 ad-hoc 签名

签名命令为:

```bash
codesign --force --sign - build/Vibe.app
```

其中 `--sign -` 表示 ad-hoc 签名。

## 打包 DMG

生成可分发的 DMG:

```bash
./scripts/package-dmg.sh
```

输出文件:

```text
dist/Vibe.dmg
```

DMG 内包含:

- `Vibe.app`
- `Applications` 快捷方式
- `使用说明.txt`

当前 DMG 中的 app 使用 ad-hoc 签名,适合自用或测试分发。如果在其他 Mac 上打开时提示「无法打开」「来自身份不明的开发者」或「App 已损坏」,将 app 拖入 Applications 后执行:

```bash
xattr -dr com.apple.quarantine /Applications/Vibe.app
```

然后重新打开 Vibe。

如果要正式公开分发,需要使用 Apple Developer ID 证书签名并进行 notarization。

## 使用方式

1. 启动 Vibe 后,菜单栏会出现波形图标。
2. 在「应用」页找到正在发声的应用。
3. 打开该应用的接管开关。
4. 调整音量、静音、输出设备或全局音效。
5. 关闭接管后,该应用立即恢复系统原始输出。

## 工作原理

```text
应用原始输出
  → Core Audio Process Tap(muteBehavior = mutedWhenTapped)
  → 私有聚合设备(tap 输入 + 目标输出设备)
  → 实时 DSP 链
  → 目标输出设备
```

每个被接管应用都有独立音频管线和独立 DSP 链。音效参数是全局共享的,音量、静音和输出设备按应用独立保存。

DSP 链顺序:

```text
EQ → 动感响度 → 清晰度激励 → 纯净低音 → 空间环绕 → 临场感 → 应用音量 → 限幅保护
```

## 目录结构

```text
Sources/Vibe/
├── VibeApp.swift
├── Audio/     # Core Audio 工具、设备/进程枚举、Process Tap 管线、音频引擎
├── DSP/       # EQ、音效模块、混响、限幅器、DSP 链
├── Model/     # 参数、预设、设置持久化
└── UI/        # 应用列表、音效、预设等界面

scripts/
├── build-app.sh      # 构建 Vibe.app
├── package-dmg.sh    # 打包 dist/Vibe.dmg
└── Info.plist        # app bundle 元信息与权限说明
```

## 已知限制

- 依赖 macOS 14.4+ 的 Process Tap API。
- Chrome 等多进程应用可能会以 Helper 进程形式出现多行。
- 应用暂停发声后可能会从 Core Audio 进程列表中消失,但已接管的应用会保留。
- 使用独占模式直接写硬件的专业音频应用可能无法被 Process Tap 接管。
- 链路存在设备缓冲和 lookahead 限幅器带来的少量延迟,日常播放通常无感,节奏游戏等低延迟场景建议关闭接管。
- BBE、SRS、LifeVibes、Concert Sound 等名称属于各自权利人;本项目只实现相似风格的独立音效算法,分发时不应使用这些名称进行宣传。

## License

未指定。使用、修改或分发前请先确认授权方式。
