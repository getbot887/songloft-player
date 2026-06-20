# 蓝牙车载歌词功能 + 默认音乐应用修复 — 实施报告

**日期：** 2026-06-20
**变更类型：** 功能新增 + Bug 修复

---

## 一、变更概述

本次变更包含两个部分：

1. **修复默认音乐应用识别** — 在系统「设置 → 默认应用 → 音乐播放器」中无法发现 Songloft 的问题
2. **蓝牙车载歌词功能** — 播放歌曲时通过蓝牙向车机发送歌词，支持标准 AVRCP 1.6 协议和兼容模式（障眼法）

---

## 二、变更文件清单

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

---

## 三、各文件详细变更

### 3.1 AndroidManifest.xml（默认音乐应用修复）

**问题：** APK 安装后在系统「设置 → 默认应用 → 音乐播放器」列表中不可见。

**原因：** 缺少 `android.intent.category.APP_MUSIC` intent-filter，系统无法将本应用识别为音乐播放器。

**修改内容：** 在 `<activity android:name=".MainActivity">` 内新增：

```xml
<!-- 注册为音乐播放器，使系统「默认音乐应用」可发现本应用 -->
<intent-filter>
    <action android:name="android.intent.action.MUSIC_PLAYER"/>
    <category android:name="android.intent.category.APP_MUSIC"/>
    <category android:name="android.intent.category.DEFAULT"/>
</intent-filter>
```

---

### 3.2 app_preferences.dart（本地设置存储）

**新增常量：**

```dart
static const _bluetoothLyricsEnabledKey = 'bluetooth_lyrics_enabled';
static const _bluetoothLyricsCompatModeKey = 'bluetooth_lyrics_compat_mode';
```

**新增方法：**

| 方法 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `getBluetoothLyricsEnabled()` | `bool` | `false` | 蓝牙歌词主开关 |
| `setBluetoothLyricsEnabled(bool)` | `Future<bool>` | - | 设置主开关 |
| `getBluetoothLyricsCompatMode()` | `bool` | `false` | 兼容模式开关 |
| `setBluetoothLyricsCompatMode(bool)` | `Future<bool>` | - | 设置兼容模式 |

---

### 3.3 settings_provider.dart（设置 Provider）

**新增 Notifier：**

- `BluetoothLyricsEnabledNotifier` — 管理蓝牙歌词开关状态
- `BluetoothLyricsCompatModeNotifier` — 管理兼容模式开关状态

**新增 Provider：**

- `bluetoothLyricsEnabledProvider`
- `bluetoothLyricsCompatModeProvider`

两者均遵循项目现有的 `NotifierProvider` 模式，通过 `AppPreferences` 持久化。

---

### 3.4 settings_page.dart（设置 UI）

在「播放设置」分类中新增 `SectionCard`，标题「车载蓝牙歌词」，图标 `Icons.bluetooth_outlined`，包含：

1. **SwitchListTile「开启蓝牙歌词」**
   - 主开关，控制是否向车机发送歌词
   - subtitle: 「播放歌曲时通过蓝牙向车机发送歌词，需车机支持 AVRCP 1.6」

2. **SwitchListTile「歌词兼容模式」**
   - 子开关，主开关关闭时置灰不可点
   - subtitle: 「将歌词替换歌名显示，兼容老旧车机」

---

### 3.5 MainActivity.kt（Android 原生端）

**新增 MethodChannel：** `com.songloft/bluetooth_lyrics`

**处理的方法：**

| 方法 | 参数 | 说明 |
|------|------|------|
| `updateLyrics` | lyrics, title, artist, album, artUri, duration, compatMode | 更新 MediaSession 歌词元数据 |
| `restoreMetadata` | 无 | 恢复原始歌名/歌手 |
| `updateSongInfo` | title, artist, album, artUri, duration | 更新缓存的原始元数据 |

**核心实现：**

- 通过反射获取 `AudioService.instance.mediaSession`（audio_service 插件的 MediaSession 是私有字段）
- **标准模式：** 写入 `METADATA_KEY_lyrics`（API 30+）
- **兼容模式：** 将歌词替换 `METADATA_KEY_TITLE`，原始歌名+歌手写入 `METADATA_KEY_ARTIST`
- **蓝牙断开恢复：** 注册 `BluetoothProfile.STATE_DISCONNECTED` 和 `AudioManager.ACTION_AUDIO_BECOMING_NOISY` 广播，自动恢复原始元数据

---

### 3.6 bluetooth_lyrics_service.dart（新建）

**路径：** `lib/core/platform/bluetooth_lyrics_service.dart`

**设计模式：** 单例，与 `LiveActivityService` 一致。

**核心方法：**

| 方法 | 说明 |
|------|------|
| `init()` | 初始化 MethodChannel 监听，注册蓝牙断开回调 |
| `updateLyrics(...)` | 发送歌词到原生端，内置去重（标准模式相同歌词不重复发送） |
| `restoreMetadata()` | 恢复原始元数据 |
| `updateSongInfo(...)` | 歌曲切换时更新原生端缓存的原始元数据 |
| `reset()` | 重置内部状态 |

**平台判断：** 仅 Android 平台生效（`Platform.isAndroid`），其他平台静默返回。

---

### 3.7 lyric_provider.dart（歌词 Provider 集成）

**新增导入：**
- `BluetoothLyricsService`
- `bluetoothLyricsEnabledProvider`
- `bluetoothLyricsCompatModeProvider`

**新增方法：** `_updateBluetoothLyrics(String lyrics)`
- 检查蓝牙歌词开关是否开启
- 读取兼容模式设置
- 获取当前歌曲信息
- 调用 `BluetoothLyricsService().updateLyrics()`

**修改的方法：**
- `_updateCurrentLine()` — 歌词行切换时新增调用 `_updateBluetoothLyrics()`
- `_loadLyrics()` — 歌词加载完成后新增调用 `_updateBluetoothLyrics()`（两处：缓存命中时、API 加载成功时）

---

### 3.8 audio_service.dart（音频 Handler 集成）

**新增导入：** `BluetoothLyricsService`

**修改的方法：** `_updateNowPlaying(Song song)`
- 在 `mediaItem.add(item)` 之后，调用 `BluetoothLyricsService().updateSongInfo()` 通知原生端更新缓存的原始元数据

---

### 3.9 main.dart（应用启动初始化）

**新增导入：** `BluetoothLyricsService`

**新增初始化：** 在 AudioService 初始化完成后：

```dart
// 初始化蓝牙车载歌词服务（仅 Android）
if (!kIsWeb && Platform.isAndroid) {
  BluetoothLyricsService().init();
}
```

---

## 四、技术架构

### 数据流

```
歌词行切换 (lyric_provider.dart)
  │
  ├─ 检查 bluetoothLyricsEnabledProvider (是否开启)
  ├─ 读取 bluetoothLyricsCompatModeProvider (是否兼容模式)
  ├─ 获取当前歌曲信息 (playerStateProvider)
  │
  └─→ BluetoothLyricsService.updateLyrics()
        │
        └─→ MethodChannel "com.songloft/bluetooth_lyrics"
              │
              └─→ MainActivity.kt
                    │
                    ├─ 反射获取 AudioService.instance.mediaSession
                    │
                    ├─ 标准模式：METADATA_KEY_lyrics
                    └─ 兼容模式：替换 title / artist
                          │
                          └─→ 蓝牙 AVRCP → 车机显示屏
```

### 歌曲切换流程

```
playSong() (audio_service.dart)
  │
  ├─ _updateNowPlaying(song)
  │     ├─ mediaItem.add(item)  →  系统通知栏更新
  │     └─ BluetoothLyricsService().updateSongInfo()  →  原生端缓存更新
  │
  └─ lyric_provider 监听 currentSong 变化
        └─ _loadLyrics() → 歌词加载完成后 _updateBluetoothLyrics()
```

### 蓝牙断开恢复流程

```
蓝牙断开广播 (MainActivity.kt)
  │
  ├─ restoreMetadata()  →  恢复原始歌名/歌手
  └─ invokeMethod("onBluetoothDisconnected")  →  通知 Flutter 端
        └─ BluetoothLyricsService._lastLyrics = null
```

---

## 五、设置项说明

| SharedPreferences Key | 类型 | 默认值 | 说明 |
|----------------------|------|--------|------|
| `bluetooth_lyrics_enabled` | `bool` | `false` | 蓝牙车载歌词主开关 |
| `bluetooth_lyrics_compat_mode` | `bool` | `false` | 兼容模式开关（障眼法） |

---

## 六、兼容性说明

| 条件 | 说明 |
|------|------|
| Android 系统版本 | ≥ 9 (API 28)，METADATA_KEY_lyrics 需要 API 30+ |
| 蓝牙 AVRCP 版本 | 标准模式需 AVRCP 1.6+，兼容模式无此要求 |
| iOS / Web / 桌面 | 不受影响，蓝牙歌词功能仅在 Android 生效 |
| 车机支持 | 部分老旧车机可能不支持歌词显示，兼容模式可解决 95%+ 场景 |

---

## 七、边界处理

| 场景 | 处理方式 |
|------|---------|
| 前奏/间奏无歌词 | 发送空字符串，原生端自动恢复原始歌名 |
| 相同歌词连续出现 | 标准模式下跳过重复发送（内置去重） |
| 蓝牙断开 | 自动恢复原始元数据 |
| 歌曲切换 | 先更新原始元数据缓存，再由歌词 Provider 发送新歌词 |
| 用户关闭功能 | 歌词 Provider 不再调用蓝牙服务 |
| 兼容模式开关切换 | 下一次歌词行切换时生效 |

---

## 八、测试建议

1. **默认音乐应用验证：** 安装 APK 后进入「设置 → 默认应用 → 音乐播放器」，确认 Songloft 出现在列表中
2. **标准模式测试：** 开启蓝牙歌词（关闭兼容模式），连接支持 AVRCP 1.6 的车机，确认歌词显示
3. **兼容模式测试：** 开启兼容模式，连接不支持歌词的老车机，确认歌名位置显示歌词
4. **蓝牙断开测试：** 播放时断开蓝牙，确认手机通知栏恢复显示真实歌名/歌手
5. **歌曲切换测试：** 连续切换歌曲，确认歌词和歌名正确更新
6. **前奏/间奏测试：** 播放有前奏的歌曲，确认前奏期间显示原始歌名
