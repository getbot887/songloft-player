import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/lyric_cache_service.dart';
import '../../../shared/models/song.dart';
import '../../library/presentation/providers/songs_provider.dart';
import '../domain/lyric_parser.dart';

/// 歌词调整页
///
/// 用户在播放页发现歌词与音乐不同步时，点「调整」进入本页面，做：
///  1. 全局时间偏移（整体平移所有 LRC 时间戳，处理整首歌的 offset）
///  2. 逐行时间微调（处理单行错位）
///
/// 保存时把所有调整应用到原 LRC，前端重新组装文本，PUT 给后端的
/// `/api/v1/songs/{id}/lyrics`（lyric_source=manual）。
/// 后端会同步把主歌词写入音频文件 USLT/LYRICS（写入失败时仅落库），
/// 并以 `file_write_status` 字段告知客户端。
///
/// 仅对 type=local 的歌曲开放（入口由 LyricsView 控制）。
class LyricAdjustPage extends ConsumerStatefulWidget {
  /// 待编辑的歌曲（用其 id/lyricUrl）
  final Song song;

  /// 原始 LRC 文本（由调用方在打开本页前已拉好，避免再请求一次）
  final String originalLyric;

  const LyricAdjustPage({
    super.key,
    required this.song,
    required this.originalLyric,
  });

  @override
  ConsumerState<LyricAdjustPage> createState() => _LyricAdjustPageState();
}

class _LyricAdjustPageState extends ConsumerState<LyricAdjustPage> {
  /// 解析后的原始歌词行（time 不会变，所有调整都叠加到它之上）
  List<LyricLine> _baseLines = const [];

  /// 全局整体偏移，毫秒
  int _globalOffsetMs = 0;

  /// 每行额外的偏移（key 是 _baseLines 索引，value 是毫秒）
  final Map<int, int> _perLineDeltaMs = {};

  bool _saving = false;

  static const int _globalRange = 10000; // ±10s

  @override
  void initState() {
    super.initState();
    _baseLines = LyricParser.parse(widget.originalLyric);
  }

  bool get _hasChanges =>
      _globalOffsetMs != 0 ||
      _perLineDeltaMs.values.any((v) => v != 0);

  void _resetAll() {
    setState(() {
      _globalOffsetMs = 0;
      _perLineDeltaMs.clear();
    });
  }

  Duration _adjustedTime(int index) {
    final base = _baseLines[index].time;
    final delta = Duration(
      milliseconds: _globalOffsetMs + (_perLineDeltaMs[index] ?? 0),
    );
    final result = base + delta;
    return result < Duration.zero ? Duration.zero : result;
  }

  String _formatTime(Duration d) {
    final ms = d.inMilliseconds;
    final m = (ms ~/ 60000).toString().padLeft(2, '0');
    final s = ((ms ~/ 1000) % 60).toString().padLeft(2, '0');
    final mss = (ms % 1000).toString().padLeft(3, '0');
    return '$m:$s.$mss';
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      // 把所有调整应用到原行，重组 LRC
      final adjusted = <LyricLine>[
        for (final entry in _baseLines.asMap().entries)
          LyricLine(time: _adjustedTime(entry.key), text: entry.value.text),
      ];
      final newLrc = LyricParser.stringify(adjusted);

      final repo = ref.read(songsRepositoryProvider);
      final result = await repo.updateSongLyrics(
        widget.song.id,
        lyricSource: 'manual',
        lyric: newLrc,
      );

      // 清掉调整前的歌词缓存，确保 LyricsView 下次打开拉到新文本
      final lyricUrl = widget.song.lyricUrl;
      if (lyricUrl != null && lyricUrl.isNotEmpty) {
        await LyricCacheService().remove(lyricUrl);
      }

      if (!mounted) return;

      final msg = switch (result.fileWriteStatus) {
        'written' => '已保存，已写入音频文件',
        'failed' => '已保存到数据库，但写入音频文件失败',
        _ => '已保存到数据库（文件未更新）',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_hasChanges) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('放弃修改？'),
        content: const Text('当前调整尚未保存，确定要离开吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('继续编辑'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Widget _buildGlobalOffsetCard(ThemeData theme) {
    final sign = _globalOffsetMs >= 0 ? '+' : '';
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('全局偏移', style: theme.textTheme.titleSmall),
                Text(
                  '$sign$_globalOffsetMs ms',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            Slider(
              min: -_globalRange.toDouble(),
              max: _globalRange.toDouble(),
              divisions: 200, // 100ms 粒度
              value: _globalOffsetMs.toDouble().clamp(
                -_globalRange.toDouble(),
                _globalRange.toDouble(),
              ),
              label: '$sign$_globalOffsetMs ms',
              onChanged: (v) => setState(() => _globalOffsetMs = v.round()),
              semanticFormatterCallback: (value) => '歌词偏移 ${value.round()} 毫秒',
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final delta in const [-500, -100, 100, 500])
                  OutlinedButton(
                    onPressed: () {
                      setState(() {
                        final next = (_globalOffsetMs + delta).clamp(
                          -_globalRange,
                          _globalRange,
                        );
                        _globalOffsetMs = next;
                      });
                    },
                    child: Text(delta > 0 ? '+${delta}ms' : '${delta}ms'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '提示：歌词整体早出现，用负偏移（-）；整体晚出现，用正偏移（+）',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLine(int index, ThemeData theme) {
    final base = _baseLines[index];
    final delta = _perLineDeltaMs[index] ?? 0;
    final adjusted = _adjustedTime(index);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          // 时间戳（调整后）
          SizedBox(
            width: 84,
            child: Text(
              '[${_formatTime(adjusted)}]',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          // 行文本
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  base.text.isEmpty ? '(空行)' : base.text,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (delta != 0)
                  Text(
                    '行偏移 ${delta > 0 ? '+' : ''}${delta}ms',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
              ],
            ),
          ),
          // 微调按钮
          IconButton(
            icon: const Icon(Icons.remove, size: 18),
            tooltip: '-100ms',
            onPressed: () {
              setState(() {
                _perLineDeltaMs[index] = (delta - 100);
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 18),
            tooltip: '+100ms',
            onPressed: () {
              setState(() {
                _perLineDeltaMs[index] = (delta + 100);
              });
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _confirmDiscard();
        if (!shouldPop || !mounted) return;
        // 使用 State 自身的 context，避免 lint 抱怨 async 后 context 跨越
        Navigator.of(this.context).pop(false);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('调整歌词'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '重置',
              onPressed: _hasChanges ? _resetAll : null,
            ),
            TextButton(
              onPressed: (_saving || !_hasChanges) ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存'),
            ),
          ],
        ),
        body: _baseLines.isEmpty
            ? const Center(child: Text('暂无可调整的歌词'))
            : Column(
                children: [
                  _buildGlobalOffsetCard(theme),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _baseLines.length,
                      itemBuilder: (_, i) => _buildLine(i, theme),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
