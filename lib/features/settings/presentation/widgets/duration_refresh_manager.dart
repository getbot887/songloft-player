import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings_api.dart';
import '../providers/settings_provider.dart';

class DurationRefreshManager extends ConsumerStatefulWidget {
  const DurationRefreshManager({super.key});

  @override
  ConsumerState<DurationRefreshManager> createState() =>
      _DurationRefreshManagerState();
}

class _DurationRefreshManagerState
    extends ConsumerState<DurationRefreshManager> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(durationRefreshProvider.notifier).refreshProgress();
    });
  }

  @override
  Widget build(BuildContext context) {
    final progress = ref.watch(durationRefreshProvider);
    final theme = Theme.of(context);

    if (progress.isRunning) {
      return _buildRunningState(progress, theme);
    }
    if (progress.isDone && progress.total > 0) {
      return _buildDoneState(progress, theme);
    }
    return _buildIdleState(theme);
  }

  Widget _buildIdleState(ThemeData theme) {
    return ListTile(
      leading: Icon(Icons.timer_outlined, color: theme.colorScheme.primary),
      title: const Text('刷新网络歌曲时长'),
      subtitle: const Text('探测所有时长未知的网络歌曲'),
      trailing: FilledButton.tonal(
        onPressed: () {
          ref.read(durationRefreshProvider.notifier).startRefresh();
        },
        child: const Text('开始'),
      ),
    );
  }

  Widget _buildRunningState(DurationRefreshProgress progress, ThemeData theme) {
    final label = progress.total > 0
        ? '${progress.completedCount} / ${progress.total}'
        : '准备中...';
    return ListTile(
      leading: SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          value: progress.total > 0 ? progress.progress : null,
        ),
      ),
      title: const Text('正在刷新时长'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: progress.total > 0 ? progress.progress : null,
          ),
          const SizedBox(height: 4),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
      trailing: TextButton(
        onPressed: () {
          ref.read(durationRefreshProvider.notifier).cancel();
        },
        child: const Text('取消'),
      ),
    );
  }

  Widget _buildDoneState(DurationRefreshProgress progress, ThemeData theme) {
    final statusText = progress.status == 'cancelled'
        ? '已取消'
        : progress.status == 'failed'
            ? '执行失败'
            : '已完成';
    final detail =
        '成功 ${progress.processed} 首${progress.failed > 0 ? '，失败 ${progress.failed} 首' : ''}';
    return ListTile(
      leading: Icon(
        progress.status == 'done' ? Icons.check_circle : Icons.info_outlined,
        color: progress.status == 'done'
            ? theme.colorScheme.primary
            : theme.colorScheme.outline,
      ),
      title: Text('刷新时长$statusText'),
      subtitle: Text(detail),
      trailing: FilledButton.tonal(
        onPressed: () {
          ref.read(durationRefreshProvider.notifier).startRefresh();
        },
        child: const Text('重新刷新'),
      ),
    );
  }
}
