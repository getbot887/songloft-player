import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class WindowTrayManager with WindowListener, TrayListener {
  static final WindowTrayManager _instance = WindowTrayManager._internal();

  factory WindowTrayManager() {
    return _instance;
  }

  WindowTrayManager._internal();

  /// 退出前的清理回调（如释放音频资源），由 main.dart 注入
  Future<void> Function()? onBeforeExit;

  static Future<void> setup() async {
    if (kIsWeb) return;
    // 目前根据 MVP 计划，仅在 Windows 下开启隐藏到托盘功能
    if (!Platform.isWindows) return;

    await windowManager.ensureInitialized();
    
    // 拦截窗口关闭事件
    await windowManager.setPreventClose(true);

    final manager = WindowTrayManager();
    windowManager.addListener(manager);
    trayManager.addListener(manager);

    await manager._initTray();
  }

  Future<void> _initTray() async {
    String getIconPath() {
      if (Platform.isWindows) {
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        final buildPath = '$exeDir\\data\\flutter_assets\\windows\\runner\\resources\\app_icon.ico';
        if (File(buildPath).existsSync()) {
          return buildPath;
        }
        return 'windows/runner/resources/app_icon.ico';
      }
      return 'assets/icons/app_icon.png';
    }

    await trayManager.setIcon(getIconPath());

    Menu menu = Menu(
      items: [
        MenuItem(
          key: 'show_window',
          label: '打开 Songloft',
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'exit_app',
          label: '退出',
        ),
      ],
    );
    await trayManager.setContextMenu(menu);
    await trayManager.setToolTip('Songloft');
  }

  @override
  void onWindowClose() async {
    // 点击 X 按钮时触发，将窗口隐藏而不是退出
    bool isPreventClose = await windowManager.isPreventClose();
    if (isPreventClose) {
      windowManager.hide();
    }
  }

  @override
  void onTrayIconMouseDown() {
    // 左键点击托盘图标：恢复窗口显示
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() {
    // 右键点击托盘图标：弹出上下文菜单
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    if (menuItem.key == 'show_window') {
      windowManager.show();
      windowManager.focus();
    } else if (menuItem.key == 'exit_app') {
      try {
        await onBeforeExit?.call();
      } catch (e) {
        debugPrint('[WindowTrayManager] onBeforeExit error: $e');
      }
      await windowManager.setPreventClose(false);
      await windowManager.close();
    }
  }
}
