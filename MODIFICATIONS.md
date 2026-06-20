# 本 Fork 修改说明

基于 [songloft-org/songloft-player](https://github.com/songloft-org/songloft-player) 的修改版本。

---

## 修改内容

### 1. 修复：默认音乐应用识别

**问题：** APK 安装后在系统「设置 → 默认应用 → 音乐播放器」列表中无法发现 Songloft。

**修复：** 在 `AndroidManifest.xml` 中添加 `APP_MUSIC` intent-filter，使系统能将本应用识别为音乐播放器。

**修改文件：** `android/app/src/main/AndroidManifest.xml`

---

### 2. 新增：蓝牙车载歌词功能

播放歌曲时，通过蓝牙 AVRCP 协议向车机发送歌词，支持两种模式：

#### 标准模式
- 将歌词写入 Android `MediaSession` 的 `METADATA_KEY_lyrics` 字段
- 需要车机支持 AVRCP 1.6+

#### 兼容模式（障眼法）
- 将歌词替换歌名显示，原始歌名+歌手移到歌手字段
- 兼容老旧车机，只要车机能显示歌名就能显示歌词

#### 功能设置
在「设置 → 播放设置」中新增「车载蓝牙歌词」区域：
- **开启蓝牙歌词** — 主开关
- **歌词兼容模式** — 子开关，适用于不支持 AVRCP 1.6 的老车机

#### 自动恢复
- 蓝牙断开时自动恢复通知栏显示的真实歌名/歌手
- 歌曲切换时自动更新元数据

---

## 修改文件清单

| # | 文件路径 | 操作 | 说明 |
|---|---------|------|------|
| 1 | `android/app/src/main/AndroidManifest.xml` | 修改 | 添加 APP_MUSIC intent-filter |
| 2 | `lib/core/storage/app_preferences.dart` | 修改 | 新增蓝牙歌词设置项 |
| 3 | `lib/features/settings/presentation/providers/settings_provider.dart` | 修改 | 新增蓝牙歌词 Provider |
| 4 | `lib/features/settings/presentation/settings_page.dart` | 修改 | 新增车载蓝牙歌词设置 UI |
| 5 | `android/app/src/main/kotlin/com/songloft/songloft_flutter/MainActivity.kt` | 重写 | 蓝牙歌词 MethodChannel 原生实现 |
| 6 | `lib/core/platform/bluetooth_lyrics_service.dart` | **新建** | Flutter 端蓝牙歌词服务 |
| 7 | `lib/features/player/presentation/providers/lyric_provider.dart` | 修改 | 集成蓝牙歌词推送 |
| 8 | `lib/core/audio/audio_service.dart` | 修改 | 歌曲切换时通知蓝牙歌词服务 |
| 9 | `lib/main.dart` | 修改 | 初始化蓝牙歌词服务 |
| 10 | `.github/workflows/build-apk.yml` | **新建** | GitHub Actions 自动构建 APK |

---

## 技术实现

### 数据流

```
歌词行切换 (lyric_provider)
  → 检查蓝牙歌词开关
    → BluetoothLyricsService.updateLyrics()
      → MethodChannel → MainActivity.kt
        → 反射获取 AudioService.mediaSession
          → 标准模式：METADATA_KEY_lyrics
          → 兼容模式：替换 title / artist
            → 蓝牙 AVRCP → 车机显示
```

### 核心组件

- **BluetoothLyricsService** (`lib/core/platform/bluetooth_lyrics_service.dart`) — Flutter 端服务，封装 MethodChannel 调用
- **MainActivity.kt** — Android 原生端，通过反射访问 audio_service 插件的 MediaSession，写入歌词元数据
- **lyric_provider.dart** — 歌词 Provider，在歌词行切换时触发蓝牙歌词更新

---

## 构建说明

本 Fork 配置了 GitHub Actions 自动构建：

1. Push 到 `main` 分支后自动触发构建
2. 也可在 Actions 页面手动触发（Run workflow）
3. 构建完成后在 Artifacts 中下载 APK

---

## 兼容性

| 条件 | 说明 |
|------|------|
| Android 系统 | ≥ 9 (API 28) |
| 标准模式 | 需车机支持 AVRCP 1.6+ |
| 兼容模式 | 适用于绝大多数车机 |
| iOS / Web / 桌面 | 不受影响，蓝牙歌词仅 Android 生效 |

---

## 原项目地址

https://github.com/songloft-org/songloft-player
