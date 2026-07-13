import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/debug_log_service.dart';

/// 调试日志查看页面
class DebugLogPage extends StatefulWidget {
  const DebugLogPage({super.key});

  @override
  State<DebugLogPage> createState() => _DebugLogPageState();
}

class _DebugLogPageState extends State<DebugLogPage> {
  final DebugLogService _logService = DebugLogService();
  final TextEditingController _serverUrlController = TextEditingController();
  String _filterTag = 'all';
  bool _isUploading = false;

  static const _tags = ['all', 'other', 'BTLyrics'];
  static const _tagLabels = {'all': '全部', 'other': '播放控制', 'BTLyrics': 'BTLyrics'};
  static const _serverUrlKey = 'debug_log_server_url';

  @override
  void initState() {
    super.initState();
    _logService.onLogAdded = () {
      if (mounted) setState(() {});
    };
    _loadServerUrl();
  }

  @override
  void dispose() {
    _logService.onLogAdded = null;
    _serverUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_serverUrlKey) ?? '';
    _serverUrlController.text = url;
  }

  Future<void> _saveServerUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverUrlKey, url);
  }

  Future<void> _uploadLogs() async {
    final serverUrl = _serverUrlController.text.trim();
    if (serverUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入日志服务地址')),
      );
      return;
    }

    setState(() => _isUploading = true);

    try {
      final result = await _logService.uploadLogs(serverUrl);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('上传失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final logs = _filterTag == 'all'
        ? _logService.logs
        : _filterTag == 'other'
            ? _logService.logs.where((e) => e.tag != 'BTLyrics').toList()
            : _logService.getLogsByTag(_filterTag);

    return Scaffold(
      appBar: AppBar(
        title: const Text('调试日志'),
        actions: [
          // 标签过滤
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (tag) => setState(() => _filterTag = tag),
            itemBuilder: (_) => _tags
                .map((tag) => PopupMenuItem(
                      value: tag,
                      child: Text(_tagLabels[tag] ?? tag),
                    ))
                .toList(),
          ),
          // 复制全部
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: '复制全部日志',
            onPressed: () {
              final text = _logService.toText(
                tag: _filterTag == 'all' ? null : _filterTag,
              );
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制到剪贴板')),
              );
            },
          ),
          // 上传日志
          IconButton(
            icon: _isUploading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_upload_outlined),
            tooltip: '上传日志到服务端',
            onPressed: _isUploading ? null : _uploadLogs,
          ),
          // 清空
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '清空日志',
            onPressed: () {
              _logService.clear();
              setState(() {});
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 日志服务地址配置
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                const Icon(Icons.dns, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _serverUrlController,
                    decoration: const InputDecoration(
                      hintText: '日志服务地址',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    style: const TextStyle(fontSize: 13),
                    onChanged: _saveServerUrl,
                  ),
                ),
              ],
            ),
          ),
          // 日志统计
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: Row(
              children: [
                Text(
                  '共 ${logs.length} 条日志',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                if (_logService.logFilePath != null)
                  Text(
                    '文件: ${_logService.logFilePath!.split('/').last}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
              ],
            ),
          ),
          // 日志列表
          Expanded(
            child: logs.isEmpty
                ? const Center(child: Text('暂无日志'))
                : ListView.builder(
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final entry = logs[index];
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant
                                  .withValues(alpha: 0.3),
                            ),
                          ),
                        ),
                        child: SelectableText(
                          entry.toText(),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
