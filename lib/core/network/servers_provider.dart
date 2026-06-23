import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/providers/auth_provider.dart';
import 'base_url_provider.dart';
import 'server_entry.dart';

enum ProbeStatus { unknown, probing, ok, fail }

/// 探测结果摘要，供 StartupGate 写入、首屏 SnackBar 读取。
enum ProbeOutcome { idle, success, fallbackUsed, noServers }

/// 服务器列表的持久化状态。所有 CRUD 走这个 Notifier，保证去重 + 顺序持久化。
class ServersNotifier extends AsyncNotifier<List<ServerEntry>> {
  @override
  Future<List<ServerEntry>> build() async {
    final prefs = await ref.watch(appPreferencesProvider.future);
    return prefs.getApiServers();
  }

  Future<void> _save(List<ServerEntry> next) async {
    final prefs = await ref.read(appPreferencesProvider.future);
    await prefs.setApiServers(next);
    state = AsyncData(prefs.getApiServers());
  }

  Future<void> add(ServerEntry entry) async {
    final current = state.value ?? const <ServerEntry>[];
    if (current.any((e) => e.url == entry.url)) return;
    await _save([...current, entry]);
  }

  Future<void> editEntry(ServerEntry entry) async {
    final current = state.value ?? const <ServerEntry>[];
    final next = current.map((e) => e.id == entry.id ? entry : e).toList();
    await _save(next);
  }

  Future<void> remove(String id) async {
    final current = state.value ?? const <ServerEntry>[];
    final next = current.where((e) => e.id != id).toList();
    await _save(next);
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    final current = [...(state.value ?? const <ServerEntry>[])];
    if (newIndex > oldIndex) newIndex -= 1;
    final item = current.removeAt(oldIndex);
    current.insert(newIndex, item);
    await _save(current);
  }

  Future<void> replace(List<ServerEntry> next) async {
    await _save(next);
  }
}

final serversProvider =
    AsyncNotifierProvider<ServersNotifier, List<ServerEntry>>(
  ServersNotifier.new,
);

/// 探测状态：ServerEntry id → ProbeStatus
class ProbeStatusNotifier extends Notifier<Map<String, ProbeStatus>> {
  @override
  Map<String, ProbeStatus> build() => const <String, ProbeStatus>{};

  void setStatus(String id, ProbeStatus status) {
    state = {...state, id: status};
  }

  void clear() => state = const {};
}

final probeStatusProvider =
    NotifierProvider<ProbeStatusNotifier, Map<String, ProbeStatus>>(
  ProbeStatusNotifier.new,
);

/// 启动探测结果。StartupGate 写入；首屏读取后置回 idle 避免重复弹。
class ProbeOutcomeNotifier extends Notifier<ProbeOutcome> {
  @override
  ProbeOutcome build() => ProbeOutcome.idle;

  void set(ProbeOutcome v) => state = v;
}

final probeOutcomeProvider =
    NotifierProvider<ProbeOutcomeNotifier, ProbeOutcome>(
  ProbeOutcomeNotifier.new,
);

/// 切换到指定服务器（统一入口）：
/// - 选中当前在用 URL：短路无操作
/// - 否则：set baseUrl（dioProvider 自动重建）+ 登出
Future<void> applyServerSelection(WidgetRef ref, ServerEntry entry) async {
  final current = ref.read(baseUrlProvider);
  if (current == entry.url) return;
  ref.read(baseUrlProvider.notifier).set(entry.url);
  await ref.read(authStateProvider.notifier).logout();
}
