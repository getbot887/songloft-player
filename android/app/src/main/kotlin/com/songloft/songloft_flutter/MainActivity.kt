package com.songloft.songloft_flutter

import android.app.UiModeManager
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothProfile
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.res.Configuration
import android.media.AudioManager
import android.os.Bundle
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.ryanheise.audioservice.AudioService
import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity() {
    companion object {
        private const val TV_CHANNEL = "com.songloft/tv_detector"
        private const val BT_CHANNEL = "com.songloft/bluetooth_detection"
        private const val BT_LYRICS_CHANNEL = "com.songloft/bluetooth_lyrics"

        // MediaMetadataCompat.METADATA_KEY_lyrics 的字符串值（API 30+）
        private const val METADATA_KEY_LYRICS = "android.media.metadata.LYRICS"
    }

    private var btChannel: MethodChannel? = null
    private var btLyricsChannel: MethodChannel? = null

    // 原始歌曲元数据缓存（用于恢复）
    private var originalTitle: String? = null
    private var originalArtist: String? = null
    private var originalAlbum: String? = null
    private var originalArtUri: String? = null
    private var originalDuration: Long = 0

    private val bluetoothReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                BluetoothAdapter.ACTION_CONNECTION_STATE_CHANGED -> {
                    val state = intent.getIntExtra(BluetoothAdapter.EXTRA_CONNECTION_STATE, BluetoothAdapter.ERROR)
                    val connected = state == BluetoothAdapter.STATE_CONNECTED
                    btChannel?.invokeMethod("onBluetoothStateChanged", connected)

                    // 蓝牙断开时恢复歌词元数据并通知 Flutter
                    if (!connected) {
                        restoreMetadata()
                        btLyricsChannel?.invokeMethod("onBluetoothDisconnected", null)
                    }
                }
                AudioManager.ACTION_SCO_AUDIO_STATE_UPDATED -> {
                    val state = intent.getIntExtra(AudioManager.EXTRA_SCO_AUDIO_STATE, AudioManager.ERROR)
                    val connected = state == AudioManager.SCO_AUDIO_STATE_CONNECTED
                    btChannel?.invokeMethod("onBluetoothStateChanged", connected)
                }
                AudioManager.ACTION_AUDIO_BECOMING_NOISY -> {
                    // 耳机拔出/蓝牙断开时恢复歌词元数据
                    restoreMetadata()
                    btLyricsChannel?.invokeMethod("onBluetoothDisconnected", null)
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        volumeControlStream = AudioManager.STREAM_MUSIC

        // 注册蓝牙状态变化广播
        val filter = IntentFilter().apply {
            addAction(BluetoothAdapter.ACTION_CONNECTION_STATE_CHANGED)
            addAction(AudioManager.ACTION_SCO_AUDIO_STATE_UPDATED)
            addAction(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
        }
        registerReceiver(bluetoothReceiver, filter)
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(bluetoothReceiver)
        } catch (_: Exception) {}
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // TV 检测 Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TV_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "isTvMode") {
                val uiModeManager = getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
                val isTv = uiModeManager.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
                result.success(isTv)
            } else {
                result.notImplemented()
            }
        }

        // 蓝牙检测 Channel
        btChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BT_CHANNEL)
        btChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isBluetoothConnected" -> {
                    result.success(isBluetoothConnected())
                }
                "getConnectedDeviceNames" -> {
                    result.success(getConnectedDeviceNames())
                }
                else -> result.notImplemented()
            }
        }

        // 蓝牙歌词 Channel
        btLyricsChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BT_LYRICS_CHANNEL)
        btLyricsChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "updateLyrics" -> {
                    val lyrics = call.argument<String>("lyrics") ?: ""
                    val title = call.argument<String>("title") ?: ""
                    val artist = call.argument<String>("artist") ?: ""
                    val album = call.argument<String>("album") ?: ""
                    val artUri = call.argument<String>("artUri") ?: ""
                    val duration = call.argument<Number>("duration")?.toLong() ?: 0
                    val compatMode = call.argument<Boolean>("compatMode") ?: false

                    // 缓存原始元数据（首次收到时）
                    if (originalTitle == null && title.isNotEmpty()) {
                        originalTitle = title
                        originalArtist = artist
                        originalAlbum = album
                        originalArtUri = artUri
                        originalDuration = duration
                    }

                    updateLyricsOnMediaSession(lyrics, title, artist, album, artUri, duration, compatMode)
                    result.success(true)
                }

                "restoreMetadata" -> {
                    restoreMetadata()
                    result.success(true)
                }

                "updateSongInfo" -> {
                    // 歌曲切换时更新原始元数据缓存
                    val title = call.argument<String>("title") ?: ""
                    val artist = call.argument<String>("artist") ?: ""
                    val album = call.argument<String>("album") ?: ""
                    val artUri = call.argument<String>("artUri") ?: ""
                    val duration = call.argument<Number>("duration")?.toLong() ?: 0

                    originalTitle = title
                    originalArtist = artist
                    originalAlbum = album
                    originalArtUri = artUri
                    originalDuration = duration

                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }

    /**
     * 通过反射获取 AudioService.instance.mediaSession
     */
    private fun getMediaSession(): MediaSessionCompat? {
        return try {
            val audioServiceClass = AudioService::class.java
            val instanceField = audioServiceClass.getDeclaredField("instance")
            instanceField.isAccessible = true
            val instance = instanceField.get(null) ?: return null

            val mediaSessionField = audioServiceClass.getDeclaredField("mediaSession")
            mediaSessionField.isAccessible = true
            mediaSessionField.get(instance) as? MediaSessionCompat
        } catch (e: Exception) {
            null
        }
    }

    /**
     * 更新 MediaSession 的歌词元数据
     */
    private fun updateLyricsOnMediaSession(
        lyrics: String,
        title: String,
        artist: String,
        album: String,
        artUri: String,
        duration: Long,
        compatMode: Boolean,
    ) {
        val mediaSession = getMediaSession() ?: return

        try {
            val currentMetadata = mediaSession.controller?.metadata
            val builder = if (currentMetadata != null) {
                MediaMetadataCompat.Builder(currentMetadata)
            } else {
                MediaMetadataCompat.Builder()
            }

            if (compatMode) {
                // 兼容模式（障眼法）：将歌词替换歌名，歌手改为 "原歌名 - 原歌手"
                if (lyrics.isNotEmpty()) {
                    builder.putString(MediaMetadataCompat.METADATA_KEY_TITLE, lyrics)
                    val originalInfo = buildString {
                        if (title.isNotEmpty()) append(title)
                        if (artist.isNotEmpty()) {
                            if (isNotEmpty()) append(" - ")
                            append(artist)
                        }
                    }
                    if (originalInfo.isNotEmpty()) {
                        builder.putString(MediaMetadataCompat.METADATA_KEY_ARTIST, originalInfo)
                    }
                } else {
                    // 空歌词时恢复原始歌名
                    builder.putString(MediaMetadataCompat.METADATA_KEY_TITLE, originalTitle ?: title)
                    builder.putString(MediaMetadataCompat.METADATA_KEY_ARTIST, originalArtist ?: artist)
                }
            } else {
                // 标准模式：写入 METADATA_KEY_lyrics
                builder.putString(METADATA_KEY_LYRICS, lyrics)
            }

            mediaSession.setMetadata(builder.build())
        } catch (e: Exception) {
            // 静默失败，不影响播放
        }
    }

    /**
     * 恢复原始歌曲元数据
     */
    private fun restoreMetadata() {
        if (originalTitle == null) return

        val mediaSession = getMediaSession() ?: return

        try {
            val currentMetadata = mediaSession.controller?.metadata
            val builder = if (currentMetadata != null) {
                MediaMetadataCompat.Builder(currentMetadata)
            } else {
                MediaMetadataCompat.Builder()
            }

            // 恢复原始歌名和歌手
            builder.putString(MediaMetadataCompat.METADATA_KEY_TITLE, originalTitle)
            builder.putString(MediaMetadataCompat.METADATA_KEY_ARTIST, originalArtist)
            if (originalAlbum != null) {
                builder.putString(MediaMetadataCompat.METADATA_KEY_ALBUM, originalAlbum)
            }

            // 清除歌词字段
            builder.putString(METADATA_KEY_LYRICS, "")

            mediaSession.setMetadata(builder.build())
        } catch (e: Exception) {
            // 静默失败
        }
    }

    private fun isBluetoothConnected(): Boolean {
        val bluetoothAdapter = BluetoothAdapter.getDefaultAdapter() ?: return false
        // 检查 A2DP（音频）连接状态
        val a2dpState = bluetoothAdapter.getProfileConnectionState(BluetoothProfile.A2DP)
        if (a2dpState == BluetoothProfile.STATE_CONNECTED) return true
        // 检查 SCO（通话音频）连接状态
        val scoState = bluetoothAdapter.getProfileConnectionState(BluetoothProfile.HEADSET)
        if (scoState == BluetoothProfile.STATE_CONNECTED) return true
        return false
    }

    private fun getConnectedDeviceNames(): List<String> {
        val bluetoothAdapter = BluetoothAdapter.getDefaultAdapter() ?: return emptyList()
        val names = mutableListOf<String>()
        val latch = java.util.concurrent.CountDownLatch(2)

        // 获取 A2DP 已连接设备
        try {
            bluetoothAdapter.getProfileProxy(this, object : android.bluetooth.BluetoothProfile.ServiceListener {
                override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
                    for (device in proxy.connectedDevices) {
                        device.name?.let { if (it !in names) names.add(it) }
                    }
                    bluetoothAdapter.closeProfileProxy(profile, proxy)
                    latch.countDown()
                }
                override fun onServiceDisconnected(profile: Int) {
                    latch.countDown()
                }
            }, BluetoothProfile.A2DP)
        } catch (_: SecurityException) { latch.countDown() }

        // 获取 HEADSET 已连接设备（去重）
        try {
            bluetoothAdapter.getProfileProxy(this, object : android.bluetooth.BluetoothProfile.ServiceListener {
                override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
                    for (device in proxy.connectedDevices) {
                        device.name?.let { if (it !in names) names.add(it) }
                    }
                    bluetoothAdapter.closeProfileProxy(profile, proxy)
                    latch.countDown()
                }
                override fun onServiceDisconnected(profile: Int) {
                    latch.countDown()
                }
            }, BluetoothProfile.HEADSET)
        } catch (_: SecurityException) { latch.countDown() }

        // 等待两个 profile 回调完成（最多 3 秒）
        try { latch.await(3, java.util.concurrent.TimeUnit.SECONDS) } catch (_: InterruptedException) {}
        return names
    }
}
