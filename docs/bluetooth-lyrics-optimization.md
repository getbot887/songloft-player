# 蓝牙歌词优化建议

## 背景

当前蓝牙歌词功能实现了五种模式（关闭/仅歌词界面/蓝牙自动/指定设备/强制），解决了"不在歌词页面也能推送歌词到车机"的核心需求。功能完整，设计合理。

以下优化建议**不改变功能目的**，只提升代码质量和性能。

---

## 建议 1：消除重复歌词加载（可选，非推荐）

### 现状

两套代码各自独立加载歌词：

- `lyric_provider.dart` — 歌词界面用，加载歌词 + 追踪当前行
- `bluetooth_lyrics_provider.dart` — 蓝牙推送用，**也加载歌词** + 追踪当前行

同一首歌会发两次网络请求、两次缓存读取。

### 改法

让 `bluetooth_lyrics_provider` 不自己加载歌词，改为 watch `lyricStateProvider` 的数据。

依赖关系：

```
main.dart watch bluetoothLyricsProvider  → 蓝牙推送始终存活
bluetoothLyricsProvider watch lyricStateProvider → 歌词界面始终存活
lyricStateProvider 始终存活 → 歌曲切换时自动加载歌词
bluetoothLyricsProvider 借用歌词数据 → 推送到车机
```

### 效果

- 少一次网络请求
- 少一次缓存读取
- 歌词数据完全一致，不会出现两边不同步
- 功能和目的不变，不管在哪个页面都能推送

### ⚠️ 权衡

**当前方案更可靠。** 各自独立意味着互不影响，蓝牙推送不依赖歌词界面的状态。优化后多了一层依赖，歌词界面出问题会连带影响蓝牙推送。

**车机场景下，可靠比简洁更重要。此优化可选，非必须。**

---

## 建议 2：统一蓝牙歌词推送入口

### 现状

两处都在推送蓝牙歌词：

- `lyric_provider.dart` 的 `_pushBluetoothLyrics()` — 处理 `lyrics_screen_only` 模式
- `bluetooth_lyrics_provider.dart` 的 `_sendLyricsToBluetooth()` — 处理其他模式

两条路径都调用同一个 `BluetoothLyricsService().updateLyrics()`，容易产生竞态。

### 改法

删除 `lyric_provider.dart` 中的 `_pushBluetoothLyrics()`，所有模式统一由 `bluetooth_lyrics_provider` 处理。

### 效果

- 职责清晰，一个地方管所有蓝牙推送
- 消除竞态风险
- 更容易维护

---

## 建议 3：缓存蓝牙歌词模式设置

### 现状

`bluetooth_lyrics_provider.dart` 在每次播放进度变化时都异步读取 SharedPreferences：

```dart
final prefs = await ref.read(appPreferencesProvider.future);
final mode = prefs.getBluetoothLyricsMode();
```

播放进度每秒更新多次，每次都读 SP 是不必要的 I/O。

### 改法

通过 `ref.listen(bluetoothLyricsModeProvider)` 监听模式变化，缓存到 state 中。进度更新时直接读 state，不再每次读 SP。

### 效果

- 减少不必要的磁盘 I/O
- 响应更及时

---

## 建议 4：添加发送频率限制

### 现状

歌词行切换时立即推送到蓝牙，没有节流。如果歌词时间戳密集（如逐字歌词），会导致蓝牙高频写入。

### 改法

添加最小间隔（建议 200ms），间隔内的推送跳过。

### 效果

- 减少蓝牙写入频率
- 避免车机显示闪烁
- 对用户体验无感知影响（200ms 人眼分辨不出）

---

## 建议 5：支持兼容模式配置

### 现状

`BluetoothLyricsService.updateLyrics()` 支持 `compatMode` 参数（将歌词替换歌名显示，适用于老旧车机），但设置界面没有提供开关，用户无法使用。

### 改法

在设置页的蓝牙歌词区域添加"兼容模式"开关，存入 SharedPreferences，Provider 读取后传入。

### 效果

- 老旧车机也能显示歌词
- 用户可自行选择

---

## 建议 6：反射调用增加警告日志

### 现状

Android 原生层通过反射获取 `AudioService.instance.mediaSession`，依赖 `audio_service` 库的内部字段名。版本升级后字段名可能变化。

```kotlin
val instanceField = AudioService::class.java.getDeclaredField("instance")
val mediaSessionField = AudioService::class.java.getDeclaredField("mediaSession")
```

### 改法

在 catch 块中添加警告日志，提示可能需要适配新版本：

```kotlin
} catch (e: Exception) {
    android.util.Log.w("BluetoothLyrics", "反射获取 MediaSession 失败，可能需要适配 audio_service 新版本", e)
    null
}
```

### 效果

- 问题发生时能快速定位原因
- 不影响现有功能

---

## 优先级

| 建议 | 优先级 | 说明 |
|------|--------|------|
| 1. 消除重复加载 | 高 | 减少网络请求，提升性能 |
| 2. 统一推送入口 | 高 | 消除竞态，降低维护成本 |
| 3. 缓存模式设置 | 中 | 减少 I/O，锦上添花 |
| 4. 发送频率限制 | 中 | 防止极端情况 |
| 5. 兼容模式配置 | 低 | 扩展功能 |
| 6. 反射警告日志 | 低 | 可观测性 |

---

## 总结

以上优化**不会改变蓝牙歌词的核心功能**：

- 不管在哪个页面，歌词照样推送到车机
- 五种模式照样生效
- 蓝牙断开照样恢复元数据

改动的是实现细节，不是用户体验。
