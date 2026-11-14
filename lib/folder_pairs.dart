import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sync_engine.dart';
import 'sync_page.dart';
import 'ui.dart';

typedef FolderPicker = Future<String?> Function(String? initialDirectory);

FolderPicker? get nativeFolderPicker {
  if (kIsWeb || defaultTargetPlatform == TargetPlatform.iOS) return null;
  return (directory) => getDirectoryPath(
    initialDirectory: directory,
    confirmButtonText: '选择此文件夹',
  );
}

class FolderEndpoint {
  const FolderEndpoint(this.device, this.path);

  final String device;
  final String path;

  Map<String, String> toJson() => {'device': device, 'path': path};

  factory FolderEndpoint.fromJson(Map<String, dynamic> data) =>
      FolderEndpoint(data['device'] as String, data['path'] as String);
}

class FolderPair {
  FolderPair(this.name, Iterable<FolderEndpoint> endpoints, {this.backupSource})
    : endpoints = List.unmodifiable(endpoints);

  static const minimumDevices = 2;

  final String name;
  final List<FolderEndpoint> endpoints;

  final String? backupSource;

  Map<String, Object> toJson() => {
    'name': name,
    'endpoints': endpoints,
    if (backupSource case final source?) 'backupSource': source,
  };

  factory FolderPair.fromJson(Map<String, dynamic> data) {
    final endpoints = data['endpoints'] as List<dynamic>?;
    return FolderPair(
      data['name'] as String,
      endpoints?.map(
            (item) => FolderEndpoint.fromJson(item as Map<String, dynamic>),
          ) ??
          [
            FolderEndpoint('设备 1', data['first'] as String),
            FolderEndpoint('设备 2', data['second'] as String),
          ],
      backupSource: data['backupSource'] as String?,
    );
  }
}

class FolderPairStore {
  static const _key = 'folder_pairs_v1';

  Future<List<FolderPair>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key);
    if (value == null) return [];
    return (jsonDecode(value) as List<dynamic>)
        .map((item) => FolderPair.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> save(List<FolderPair> pairs) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(_key, jsonEncode(pairs))) {
      throw StateError('Folder pairs could not be saved');
    }
  }
}

class SyncHistoryStore {
  // Pairs keep their saved order when edited and new pairs are appended.
  String _key(int index) => 'sync_history_v1_$index';

  Future<List<SyncResult>> load(int index) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key(index)) ?? [])
        .map(
          (entry) =>
              SyncResult.fromJson(jsonDecode(entry) as Map<String, dynamic>),
        )
        .toList();
  }

  Future<void> append(int index, SyncResult result) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _key(index);
    final history = prefs.getStringList(key) ?? [];
    if (!await prefs.setStringList(key, [jsonEncode(result), ...history])) {
      throw StateError('无法保存同步日志');
    }
  }
}

class FolderPairDialog extends StatefulWidget {
  const FolderPairDialog({
    super.key,
    required this.initial,
    required this.picker,
    required this.nameTaken,
    required this.save,
  });

  final FolderPair? initial;
  final FolderPicker? picker;
  final bool Function(String) nameTaken;
  final Future<void> Function(FolderPair) save;

  @override
  State<FolderPairDialog> createState() => _FolderPairDialogState();
}

class _EndpointFields {
  _EndpointFields([FolderEndpoint? endpoint])
    : device = TextEditingController(text: endpoint?.device),
      path = TextEditingController(text: endpoint?.path);

  final TextEditingController device;
  final TextEditingController path;

  void dispose() {
    device.dispose();
    path.dispose();
  }
}

class _FolderPairDialogState extends State<FolderPairDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _endpoints =
      widget.initial?.endpoints.map(_EndpointFields.new).toList() ??
      List.generate(FolderPair.minimumDevices, (_) => _EndpointFields());
  late bool _oneWay = widget.initial?.backupSource != null;
  late _EndpointFields? _backupSource = _endpoints
      .where((endpoint) => endpoint.device.text == widget.initial?.backupSource)
      .firstOrNull;
  bool _browsing = false;
  bool _saving = false;
  String? _error;
  bool get _busy => _browsing || _saving;

  @override
  void dispose() {
    _name.dispose();
    for (final endpoint in _endpoints) {
      endpoint.dispose();
    }
    super.dispose();
  }

  Future<void> _browse(TextEditingController field) async {
    if (_busy) return;
    setState(() {
      _browsing = true;
      _error = null;
    });
    try {
      final selected = await widget.picker!(
        field.text.trim().isEmpty ? null : field.text.trim(),
      );
      if (!mounted || selected == null || selected.isEmpty) return;
      field.text = selected;
    } catch (_) {
      if (mounted) setState(() => _error = '无法打开文件夹选择器。请重试，或直接输入路径。');
    } finally {
      if (mounted) setState(() => _browsing = false);
    }
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (_oneWay && _backupSource == null) {
      setState(() => _error = '请在下方选一台设备作为备份来源。');
      return;
    }
    final pair = FolderPair(
      _name.text.trim(),
      _endpoints.map(
        (endpoint) => FolderEndpoint(
          endpoint.device.text.trim(),
          endpoint.path.text.trim(),
        ),
      ),
      backupSource: _oneWay ? _backupSource!.device.text.trim() : null,
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.save(pair);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '配对未能保存。你选的路径还在，可以重试。';
      });
    }
  }

  Widget _folderField(TextEditingController field) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: TextFormField(
          controller: field,
          enabled: !_busy,
          decoration: const InputDecoration(labelText: '文件夹路径'),
          validator: (value) =>
              (value ?? '').trim().isEmpty ? '请选择或输入文件夹' : null,
        ),
      ),
      if (widget.picker != null) ...[
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: ActionButton(
            '浏览…',
            onPressed: _busy ? null : () => _browse(field),
          ),
        ),
      ],
    ],
  );

  void _removeEndpoint(_EndpointFields endpoint) {
    setState(() {
      _endpoints.remove(endpoint);
      if (_backupSource == endpoint) _backupSource = null;
    });
    // The removed text fields detach from their controllers on the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => endpoint.dispose());
  }

  Widget _endpointField(int index, _EndpointFields endpoint) => Column(
    key: ObjectKey(endpoint),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              _oneWay
                  ? (_backupSource == endpoint ? '备份来源' : '设备 ${index + 1}')
                  : '设备 ${index + 1}',
              style: type(13, weight: FontWeight.w700),
            ),
          ),
          if (_oneWay && _backupSource != endpoint)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _backupSource = endpoint;
                      _error = null;
                    }),
              child: const Text('设为备份来源'),
            ),
          if (_endpoints.length > FolderPair.minimumDevices)
            IconButton(
              tooltip: '移除设备 ${index + 1}',
              onPressed: _busy ? null : () => _removeEndpoint(endpoint),
              icon: const Icon(Icons.remove_circle_outline, size: 18),
            ),
        ],
      ),
      const SizedBox(height: 8),
      TextFormField(
        controller: endpoint.device,
        enabled: !_busy,
        decoration: const InputDecoration(
          labelText: '设备名称',
          hintText: '例如：MacBook、Windows PC 或移动硬盘',
        ),
        validator: (value) {
          final name = (value ?? '').trim();
          if (name.isEmpty) return '请输入设备名称';
          if (_endpoints.any(
            (other) =>
                other != endpoint &&
                other.device.text.trim().toLowerCase() == name.toLowerCase(),
          )) {
            return '设备名称不能重复';
          }
          return null;
        },
      ),
      const SizedBox(height: 10),
      _folderField(endpoint.path),
    ],
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(widget.initial == null ? '新建文件夹配对' : '编辑文件夹配对'),
      scrollable: true,
      content: SizedBox(
        width: 460,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.picker == null
                    ? '每组至少两台设备，可继续添加。此平台请手动输入路径。'
                    : '每组至少两台设备，每台指定一个对应文件夹。可以继续添加设备。',
                style: type(13, color: muted),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: '配对名称',
                  hintText: '例如：项目资料',
                ),
                validator: (value) {
                  final name = value?.trim() ?? '';
                  if (name.isEmpty) return '请输入配对名称';
                  if (widget.nameTaken(name)) return '已存在同名配对';
                  return null;
                },
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('单向备份'),
                subtitle: Text(
                  _oneWay ? '选定来源。其他设备只接收文件，保留各自的历史文件。' : '双向同步，各设备互相补齐。',
                ),
                value: _oneWay,
                onChanged: _busy
                    ? null
                    : (value) => setState(() {
                        _oneWay = value;
                        _error = null;
                      }),
              ),
              for (final (index, endpoint) in _endpoints.indexed) ...[
                const SizedBox(height: 18),
                const Divider(height: 1),
                const SizedBox(height: 8),
                _endpointField(index, endpoint),
              ],
              if (_error case final message?) ...[
                const SizedBox(height: 12),
                Text(
                  message,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        ActionButton(
          '添加设备',
          icon: Icons.add_rounded,
          onPressed: _busy
              ? null
              : () => setState(() => _endpoints.add(_EndpointFields())),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ActionButton(
          _saving ? '正在保存…' : '保存配对',
          primary: true,
          onPressed: _busy ? null : _submit,
        ),
      ],
    ),
  );
}

class FolderPairPage extends StatelessWidget {
  const FolderPairPage({
    super.key,
    required this.pair,
    required this.edit,
    required this.add,
    required this.sync,
    this.syncing = false,
    this.paused = false,
    this.atPause = false,
    this.stopping = false,
    this.progress,
    this.recent = const [],
    required this.togglePause,
    required this.stop,
    required this.openHistory,
    this.lastResult,
  });

  final FolderPair pair;
  final VoidCallback edit;
  final VoidCallback add;
  final VoidCallback? sync;
  final bool syncing;
  final bool paused;
  final bool atPause;
  final bool stopping;
  final String? progress;
  final List<String> recent;
  final VoidCallback togglePause;
  final VoidCallback stop;
  final VoidCallback openHistory;
  final SyncResult? lastResult;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 14,
        runSpacing: 12,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                pair.name,
                style: type(34, weight: FontWeight.w700, spacing: -1.4),
              ),
              const SizedBox(height: 6),
              Text('已保存到本机', style: type(13, color: muted)),
              if (pair.backupSource case final source?)
                Text('单向备份 · $source → 其余设备', style: type(13, color: muted)),
            ],
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ActionButton('新建配对', icon: Icons.add_rounded, onPressed: add),
              ActionButton(
                '同步日志',
                icon: Icons.history_rounded,
                onPressed: openHistory,
              ),
              if (syncing) ...[
                ActionButton(
                  paused ? '继续' : '暂停',
                  onPressed: stopping ? null : togglePause,
                ),
                ActionButton(
                  '停止',
                  icon: Icons.stop_rounded,
                  onPressed: stopping ? null : stop,
                ),
              ] else
                ActionButton(
                  pair.backupSource == null ? '开始同步' : '开始备份',
                  icon: Icons.sync_rounded,
                  primary: true,
                  onPressed: sync,
                ),
            ],
          ),
        ],
      ),
      const SizedBox(height: 25),
      _status(context),
      const SizedBox(height: 28),
      SectionHeading(
        '对应文件夹（${pair.endpoints.length} 台设备）',
        trailing: ActionButton(
          '编辑配对',
          icon: Icons.edit_outlined,
          onPressed: syncing ? null : edit,
        ),
      ),
      const SizedBox(height: 11),
      Panel(
        child: Column(
          children: [
            for (final (index, endpoint) in pair.endpoints.indexed) ...[
              if (index > 0) const Divider(height: 1),
              _folder(
                pair.backupSource == null
                    ? endpoint.device
                    : '${endpoint.device} · ${endpoint.device == pair.backupSource ? '来源' : '目标'}',
                endpoint.path,
              ),
            ],
          ],
        ),
      ),
    ],
  );

  Widget _status(BuildContext context) {
    final IconData icon;
    final String title;
    final List<String> details;
    var color = green;
    var background = paleGreen;
    final result = lastResult;
    if (syncing) {
      icon = Icons.sync_rounded;
      title = stopping
          ? '正在停止'
          : paused
          ? (atPause ? '已暂停' : '正在暂停')
          : '正在同步';
      details = [
        if (paused && atPause)
          '点「继续」恢复本轮同步。'
        else ...[
          if (paused || stopping) '当前文件处理完后生效。',
          progress ?? '正在检查下一项',
        ],
        if (recent.isNotEmpty) '最近完成',
        ...recent,
      ];
    } else if (result != null) {
      final time = TimeOfDay.fromDateTime(result.finishedAt.toLocal())
          .format(context);
      final problems = result.incomplete;
      icon = problems ? Icons.warning_amber_rounded : Icons.check_rounded;
      if (problems) {
        color = amber;
        background = const Color(0xfff4eee2);
      }
      title = result.stopped
          ? '已停止 · $time'
          : problems
          ? '同步有未处理项 · $time'
          : '同步完成 · $time';
      details = [
        ?result.failure,
        '共 ${result.scanned} 个文件，新增 ${result.copied} 个，更新 ${result.updated} 个'
            '${result.updated > 0 ? '（旧版本已备份到 $metaDirName/versions）' : ''}',
        if (result.newerTargets.isNotEmpty)
          '保留了 ${result.newerTargets.length} 个较新的目标版本，可在同步日志查看。',
        if (result.unreachable.isNotEmpty)
          '未连接，已跳过：${result.unreachable.join('、')}',
        if (result.conflicts.isNotEmpty)
          '${result.conflicts.length} 个文件修改时间接近但大小不同，未覆盖：'
              '${result.conflicts.take(3).join('；')}'
              '${result.conflicts.length > 3 ? ' 等' : ''}',
        if (result.errors.isNotEmpty)
          '${result.errors.length} 个文件复制失败：${result.errors.first}',
      ];
    } else {
      icon = Icons.hub_outlined;
      title = pair.backupSource == null ? '尚未同步' : '尚未备份';
      details = [
        pair.backupSource == null
            ? '点击「开始同步」，各文件夹会以修改时间最新的版本为准互相补齐。删除不会同步。'
            : '按相对路径备份。目标独有的文件和较新的目标版本会保留。',
      ];
    }
    return Panel(
      color: background,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          syncing
              ? SizedBox(
                  width: 43,
                  height: 43,
                  child: Padding(
                    padding: const EdgeInsets.all(11),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: color,
                    ),
                  ),
                )
              : IconTile(
                  icon,
                  size: 43,
                  background: Colors.white,
                  color: color,
                ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: type(15, weight: FontWeight.w700, color: color),
                ),
                for (final line in details) ...[
                  const SizedBox(height: 3),
                  SelectableText(line, style: type(12, color: muted)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _folder(String label, String path) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    leading: const IconTile(Icons.folder_outlined),
    title: Text(label, style: type(13, weight: FontWeight.w700)),
    subtitle: SelectableText(path, style: type(12, color: muted, mono: true)),
  );
}

class SyncHistoryDialog extends StatefulWidget {
  const SyncHistoryDialog({super.key, required this.name, required this.load});

  final String name;
  final Future<List<SyncResult>> Function() load;

  @override
  State<SyncHistoryDialog> createState() => _SyncHistoryDialogState();
}

class _SyncHistoryDialogState extends State<SyncHistoryDialog> {
  late final _history = widget.load();
  SyncResult? _selected;

  String _date(BuildContext context, DateTime date) {
    final local = date.toLocal();
    final material = MaterialLocalizations.of(context);
    return '${material.formatCompactDate(local)} '
        '${TimeOfDay.fromDateTime(local).format(context)}';
  }

  String _outcome(SyncResult run) {
    if (run.stopped) return '已停止';
    if (run.failure != null) return '同步失败';
    if (run.incomplete) return '有未处理项';
    return '已完成';
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${widget.name} · 同步日志'),
    content: SizedBox(
      width: 620,
      height: 420,
      child: FutureBuilder<List<SyncResult>>(
        future: _history,
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Text('无法读取同步日志');
          final runs = snapshot.data;
          if (runs == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (runs.isEmpty) return const Text('还没有日志。新版同步结束后会保存明细。');
          final run = _selected;
          if (run == null) {
            return ListView.builder(
              itemCount: runs.length,
              itemBuilder: (context, index) {
                final item = runs[index];
                return ListTile(
                  title: Text(
                    '${_date(context, item.finishedAt)} · ${_outcome(item)}',
                  ),
                  subtitle: Text('新增 ${item.copied} · 更新 ${item.updated}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => setState(() => _selected = item),
                );
              },
            );
          }
          final entries = [
            '${_date(context, run.finishedAt)} · ${_outcome(run)}',
            '扫描 ${run.scanned} · 新增 ${run.copied} · 更新 ${run.updated}',
            ?run.failure,
            for (final device in run.unreachable) '未连接，已跳过 $device',
            for (final item in run.newerTargets) '保留较新目标 $item',
            for (final conflict in run.conflicts) '冲突 $conflict',
            for (final error in run.errors) '复制失败 $error',
            ...run.transfers,
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextButton.icon(
                onPressed: () => setState(() => _selected = null),
                icon: const Icon(Icons.arrow_back),
                label: const Text('返回日志列表'),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: SelectableText(entries[index]),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  );
}
