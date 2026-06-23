import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_dimensions.dart';
import '../../../shared/utils/responsive_snackbar.dart';
import 'widgets/section_card.dart';
import '../../jsplugin/data/jsplugin_api.dart';
import '../../jsplugin/presentation/providers/jsplugin_provider.dart';
import '../../jsplugin/presentation/widgets/plugin_icon.dart';
import '../data/settings_api.dart';
import 'providers/settings_provider.dart';

class TabConfigPage extends ConsumerWidget {
  const TabConfigPage({super.key});

  static const int _maxTabs = 12;
  static const int _fixedTabs = 2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabConfigAsync = ref.watch(tabConfigProvider);
    final pluginsAsync = ref.watch(jsPluginsProvider);
    final config = tabConfigAsync.value ?? TabConfig.defaultConfig();
    final plugins = pluginsAsync.value ?? [];
    final activePlugins = plugins
        .where((p) =>
            p.isActive &&
            p.entryPath != null &&
            p.entryPath!.isNotEmpty)
        .toList();

    final usedCount = _fixedTabs + config.optionalCount;
    final atLimit = usedCount >= _maxTabs;

    return Scaffold(
      appBar: AppBar(title: const Text('菜单设置')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          SectionCard(
            title: '内置页面',
            icon: Icons.dashboard_outlined,
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.library_music_outlined),
                title: const Text('歌曲库'),
                value: config.showLibrary,
                onChanged: atLimit && !config.showLibrary
                    ? null
                    : (value) => _updateConfig(
                          context,
                          ref,
                          config.copyWith(showLibrary: value),
                          atLimit && value,
                        ),
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.queue_music_outlined),
                title: const Text('歌单'),
                value: config.showPlaylists,
                onChanged: atLimit && !config.showPlaylists
                    ? null
                    : (value) => _updateConfig(
                          context,
                          ref,
                          config.copyWith(showPlaylists: value),
                          atLimit && value,
                        ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: '插件入口',
            icon: Icons.extension_outlined,
            children: activePlugins.isEmpty
                ? [
                    const ListTile(
                      leading: Icon(Icons.info_outline),
                      title: Text('暂无可用插件'),
                      subtitle: Text('请先在设置中安装并启用插件'),
                    ),
                  ]
                : _buildPluginTiles(context, ref, config, activePlugins, atLimit),
          ),
          if (config.pluginTabs.length > 1) ...[
            const SizedBox(height: 16),
            SectionCard(
              title: '插件排序',
              icon: Icons.reorder,
              children: [
                _PluginTabReorderList(
                  config: config,
                  plugins: plugins,
                  onReorder: (newConfig) =>
                      _updateConfig(context, ref, newConfig, false),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          Center(
            child: Text(
              '已启用 $usedCount 个标签（首页和设置固定显示）'
              '${usedCount > 5 ? '\n移动端超出 5 个时将折叠到「更多」菜单' : ''}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  List<Widget> _buildPluginTiles(
    BuildContext context,
    WidgetRef ref,
    TabConfig config,
    List<JSPlugin> activePlugins,
    bool atLimit,
  ) {
    final widgets = <Widget>[];
    for (var i = 0; i < activePlugins.length; i++) {
      final plugin = activePlugins[i];
      final isEnabled = config.pluginTabs
          .any((pt) => pt.entryPath == plugin.entryPath);

      if (i > 0) widgets.add(const Divider(height: 1));
      widgets.add(
        SwitchListTile(
          secondary: PluginNavIcon(
            iconUrl: plugin.iconUrl,
            size: 24,
            fallbackIcon: const Icon(Icons.extension_outlined),
          ),
          title: Text(plugin.displayName),
          subtitle: plugin.version != null ? Text('v${plugin.version}') : null,
          value: isEnabled,
          onChanged: atLimit && !isEnabled
              ? null
              : (value) {
                  final newPluginTabs = List<PluginTabEntry>.from(config.pluginTabs);
                  if (value) {
                    newPluginTabs.add(PluginTabEntry(
                      pluginId: plugin.id,
                      entryPath: plugin.entryPath!,
                      name: plugin.displayName,
                    ));
                  } else {
                    newPluginTabs.removeWhere(
                        (pt) => pt.entryPath == plugin.entryPath);
                  }
                  _updateConfig(
                    context,
                    ref,
                    config.copyWith(pluginTabs: newPluginTabs),
                    atLimit && value,
                  );
                },
        ),
      );
    }
    return widgets;
  }

  Future<void> _updateConfig(
    BuildContext context,
    WidgetRef ref,
    TabConfig config,
    bool wouldExceedLimit,
  ) async {
    if (wouldExceedLimit) {
      ResponsiveSnackBar.showError(context, message: '最多显示 $_maxTabs 个标签');
      return;
    }
    try {
      await ref.read(tabConfigProvider.notifier).updateConfig(config);
    } catch (e) {
      if (context.mounted) {
        ResponsiveSnackBar.showError(context, message: '保存失败: $e');
      }
    }
  }
}

class _PluginTabReorderList extends StatelessWidget {
  final TabConfig config;
  final List<JSPlugin> plugins;
  final ValueChanged<TabConfig> onReorder;

  const _PluginTabReorderList({
    required this.config,
    required this.plugins,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    final pluginTabs = config.pluginTabs;
    final colorScheme = Theme.of(context).colorScheme;

    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: pluginTabs.length,
      onReorder: (oldIndex, newIndex) {
        if (newIndex > oldIndex) newIndex--;
        final newList = List<PluginTabEntry>.from(pluginTabs);
        final item = newList.removeAt(oldIndex);
        newList.insert(newIndex, item);
        onReorder(config.copyWith(pluginTabs: newList));
      },
      proxyDecorator: (child, index, animation) {
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) => Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            child: child,
          ),
          child: child,
        );
      },
      itemBuilder: (context, index) {
        final pt = pluginTabs[index];
        final plugin = plugins
            .where((p) => p.entryPath == pt.entryPath)
            .firstOrNull;

        return ListTile(
          key: ValueKey(pt.entryPath),
          leading: PluginNavIcon(
            iconUrl: plugin?.iconUrl,
            size: 24,
            fallbackIcon: const Icon(Icons.extension_outlined),
          ),
          title: Text(pt.name),
          trailing: ReorderableDragStartListener(
            index: index,
            child: Icon(
              Icons.drag_handle,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        );
      },
    );
  }
}
