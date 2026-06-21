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
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity() {
    companion object {
        private const val TV_CHANNEL = "com.songloft/tv_detector"
        private const val BT_CHANNEL = "com.songloft/bluetooth_detection"
    }

    private var btChannel: MethodChannel? = null

    private val bluetoothReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                BluetoothAdapter.ACTION_CONNECTION_STATE_CHANGED -> {
                    val state = intent.getIntExtra(BluetoothAdapter.EXTRA_CONNECTION_STATE, BluetoothAdapter.ERROR)
                    val connected = state == BluetoothAdapter.STATE_CONNECTED
                    btChannel?.invokeMethod("onBluetoothStateChanged", connected)
                }
                AudioManager.ACTION_SCO_AUDIO_STATE_UPDATED -> {
                    val state = intent.getIntExtra(AudioManager.EXTRA_SCO_AUDIO_STATE, AudioManager.ERROR)
                    val connected = state == AudioManager.SCO_AUDIO_STATE_CONNECTED
                    btChannel?.invokeMethod("onBluetoothStateChanged", connected)
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
        // 获取 A2DP 已连接设备
        try {
            val a2dpDevices = bluetoothAdapter.getConnectedDevices(BluetoothProfile.A2DP)
            for (device in a2dpDevices) {
                device.name?.let { names.add(it) }
            }
        } catch (_: SecurityException) {}
        // 获取 HEADSET 已连接设备（去重）
        try {
            val headsetDevices = bluetoothAdapter.getConnectedDevices(BluetoothProfile.HEADSET)
            for (device in headsetDevices) {
                device.name?.let { if (it !in names) names.add(it) }
            }
        } catch (_: SecurityException) {}
        return names
    }
}
