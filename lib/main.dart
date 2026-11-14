import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'folder_pairs.dart';
import 'sync_engine.dart';
import 'sync_page.dart';
import 'ui.dart';
import 'workspace.dart';

void main() => runApp(const FileSyncApp());

class FileSyncApp extends StatelessWidget {
  const FileSyncApp({super.key, this.folderPicker});

  final FolderPicker? folderPicker;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'FileSync',
    debugShowCheckedModeBanner: false,
    theme: appTheme(),
    home: Workspace(folderPicker: folderPicker ?? nativeFolderPicker),
  );
}

enum _Page {
  pairs('文件夹配对', Icons.folder_copy_outlined),
  sync('同步组', Icons.sync_rounded),
  devices('设备', Icons.devices_outlined),
  backups('版本备份', Icons.inventory_2_outlined),
  activity('活动记录', Icons.history_rounded),
  settings('设置', Icons.settings_outlined);

  const _Page(this.label, this.icon);
  final String label;
  final IconData icon;
}

class Workspace extends StatefulWidget {
  const Workspace({super.key, this.folderPicker});

  final FolderPicker? folderPicker;

  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _ActiveSync {
  late final SyncControl control;
  bool atPause = false;
  String? progress;
  final recent = <String>[];
}

class _WorkspaceState extends State<Workspace> {
  final _groups = exampleGroups();
  final _snapshots = ['今天 08:30', '昨天 08:33', '11 月 9 日 08:30'];
  final _backupActivity = <Activity>[];
  final _pairStore = FolderPairStore();
  List<FolderPair>? _pairs;
  bool _pairLoadFailed = false;
  int? _selectedPair;
  final _historyStore = SyncHistoryStore();
  final _activeSyncs = <int, _ActiveSync>{};
  final _pairResults = <int, SyncResult>{};
  final _unsavedLogs = <int, List<SyncResult>>{};
  _Page _page = _Page.pairs;
  int _selected = 0;
  bool _autoSync = true;
  bool _backingUp = false;

  SyncGroup get _group => _groups[_selected];

  void _select(_Page page, {int? group}) {
    setState(() {
      _page = page;
      if (group != null) _selected = group;
    });
  }

  void _notice(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
      );
  }

  @override
  void initState() {
    super.initState();
    _loadPairs();
  }

  Future<void> _loadPairs() async {
    if (_pairLoadFailed) setState(() => _pairLoadFailed = false);
    try {
      final pairs = await _pairStore.load();
      if (!mounted) return;
      setState(() {
        _pairs = pairs;
        _selectedPair = pairs.isEmpty ? null : 0;
      });
    } catch (_) {
      if (mounted) setState(() => _pairLoadFailed = true);
    }
  }

  Future<void> _editPair([int? index]) async {
    final current = _pairs;
    if (current == null) return;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => FolderPairDialog(
        initial: index == null ? null : current[index],
        picker: widget.folderPicker,
        nameTaken: (name) => current.indexed.any(
          (entry) => entry.$1 != index && entry.$2.name == name,
        ),
        save: (pair) async {
          final next = [...current];
          if (index == null) {
            next.add(pair);
          } else {
            next[index] = pair;
          }
          await _pairStore.save(next);
          if (!mounted) return;
          setState(() {
            _pairs = next;
            _selectedPair = index ?? next.length - 1;
            _page = _Page.pairs;
          });
        },
      ),
    );
    if (mounted && saved == true) _notice('配对已保存');
  }

  Future<void> _syncPair(int index, FolderPair pair) async {
    if (_activeSyncs.containsKey(index)) return;
    final active = _ActiveSync();
    active.control = SyncControl(
      onPaused: () {
        if (mounted) setState(() => active.atPause = true);
      },
    );
    setState(() => _activeSyncs[index] = active);
    SyncResult result;
    try {
      result = await syncEndpoints(
        pair.endpoints,
        backupSource: pair.backupSource,
        control: active.control,
        onProgress: (message) {
          if (mounted) setState(() => active.progress = message);
        },
        onTransfer: (message) {
          if (!mounted) return;
          setState(() {
            active.progress = null;
            active.recent.insert(0, message);
            if (active.recent.length > 3) active.recent.removeLast();
          });
        },
      );
    } catch (error) {
      result = SyncResult()
        ..failure = error is SyncException ? error.message : '同步出错：$error';
    }
    try {
      await _historyStore.append(index, result);
    } catch (_) {
      if (mounted) {
        (_unsavedLogs[index] ??= []).insert(0, result);
        _notice('同步日志未能保存到本机，本次打开期间仍可查看');
      }
    } finally {
      if (mounted) {
        setState(() {
          _pairResults[index] = result;
          _activeSyncs.remove(index);
        });
      }
    }
  }

  Future<void> _openHistory(int index, FolderPair pair) async {
    await showDialog<void>(
      context: context,
      builder: (context) => SyncHistoryDialog(
        name: pair.name,
        load: () async {
          final saved = await _historyStore.load(index);
          return [...?_unsavedLogs[index], ...saved]
            ..sort((a, b) => b.finishedAt.compareTo(a.finishedAt));
        },
      ),
    );
  }

  Future<void> _sync() async {
    final group = _group;
    if (!group.canSync) return;
    setState(() => group.syncing = true);
    await Future<void>.delayed(const Duration(milliseconds: 1350));
    if (!mounted) return;
    setState(() {
      final count = group.filesToSync;
      group.syncing = false;
      group.filesToSync = 0;
      group.hasSynced = true;
      group.activity.insert(
        0,
        Activity(
          '在线成员同步完成',
          '${group.availableCount} 个成员 · $count 个文件',
          '刚刚',
          Icons.check_rounded,
        ),
      );
    });
    _notice(group.offlineCount == 0 ? '模拟同步完成' : '在线成员模拟同步完成，离线成员仍在等待');
  }

  Future<void> _resolve() async {
    final group = _group;
    final decision = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('处理文件冲突'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Brief.docx', style: type(15, weight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              'MacBook Pro 和 Windows PC 各有一个修改版本。',
              style: type(13, color: muted),
            ),
            const SizedBox(height: 15),
            for (final choice in [
              '保留两个版本',
              '使用 MacBook Pro 版本',
              '使用 Windows PC 版本',
            ])
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(choice, style: type(13)),
                trailing: const Icon(Icons.chevron_right_rounded, size: 17),
                onTap: () => Navigator.pop(context, choice),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('稍后处理'),
          ),
        ],
      ),
    );
    if (!mounted || decision == null) return;
    setState(() {
      group.conflict = false;
      group.activity.insert(
        0,
        Activity(
          '冲突已处理',
          'Brief.docx · $decision',
          '刚刚',
          Icons.alt_route_rounded,
        ),
      );
    });
  }

  Future<void> _backup() async {
    if (_backingUp) return;
    setState(() => _backingUp = true);
    await Future<void>.delayed(const Duration(milliseconds: 950));
    if (!mounted) return;
    final time = TimeOfDay.now().format(context);
    setState(() {
      _backingUp = false;
      _snapshots.insert(0, '今天 $time');
      _backupActivity.insert(
        0,
        const Activity('备份完成', '个人文档 · 新建快照', '刚刚', Icons.inventory_2_outlined),
      );
    });
    _notice('示例快照已创建');
  }

  Future<void> _restore(String snapshot) async {
    final path = await showDialog<String>(
      context: context,
      builder: (context) => _InputDialog(
        title: '恢复快照',
        description: '个人文档 · $snapshot',
        label: '恢复到',
        hint: '~/Documents/Restored',
        confirm: '预览恢复',
      ),
    );
    if (!mounted || path == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复预览'),
        content: Text('将恢复「个人文档」的示例快照到\n$path'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth >= 780;
            return Row(
              children: [
                if (wide) SizedBox(width: 216, child: _navigation()),
                Expanded(
                  child: Column(
                    children: [
                      _toolbar(wide),
                      Expanded(
                        child: SingleChildScrollView(
                          key: ValueKey((_page, _selected, _selectedPair)),
                          padding: EdgeInsets.fromLTRB(
                            wide ? 32 : 18,
                            wide ? 26 : 22,
                            wide ? 32 : 18,
                            28,
                          ),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1320),
                              child: _body(),
                            ),
                          ),
                        ),
                      ),
                      if (wide && _page != _Page.pairs) const _Footer(),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
      drawer: MediaQuery.sizeOf(context).width < 780
          ? Drawer(
              backgroundColor: sidebar,
              child: SafeArea(child: _navigation(drawer: true)),
            )
          : null,
    );
  }

  Widget _toolbar(bool wide) => Container(
    height: 57,
    padding: EdgeInsets.symmetric(horizontal: wide ? 32 : 12),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: border)),
    ),
    child: Row(
      children: [
        if (!wide)
          Builder(
            builder: (context) => IconButton(
              tooltip: '打开导航',
              icon: const Icon(Icons.menu_rounded, size: 21),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
        if (!wide) const SizedBox(width: 4),
        Icon(_page.icon, size: 15, color: muted),
        const SizedBox(width: 8),
        Text(_page.label, style: type(12, color: muted)),
        if (_page == _Page.sync) ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Icon(Icons.chevron_right_rounded, size: 15, color: muted),
          ),
          Expanded(
            child: Text(
              _group.name,
              overflow: TextOverflow.ellipsis,
              style: type(12, weight: FontWeight.w600),
            ),
          ),
        ] else
          const Spacer(),
        const SizedBox(width: 10),
        if (_page != _Page.pairs) Text('演示模式', style: type(11, color: soft)),
      ],
    ),
  );

  Widget _navigation({bool drawer = false}) => Container(
    decoration: const BoxDecoration(
      color: sidebar,
      border: Border(right: BorderSide(color: border)),
    ),
    child: Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(13, 19, 13, 12),
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Wordmark(),
              ),
              const SizedBox(height: 30),
              Padding(
                padding: const EdgeInsets.only(left: 9),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '已保存的配对',
                        style: type(11, weight: FontWeight.w600, color: muted),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: '新建文件夹配对',
                      icon: const Icon(
                        Icons.add_rounded,
                        size: 18,
                        color: muted,
                      ),
                      onPressed: _pairs == null
                          ? null
                          : () {
                              if (drawer) Navigator.pop(context);
                              _editPair();
                            },
                    ),
                  ],
                ),
              ),
              for (final (index, pair)
                  in (_pairs ?? const <FolderPair>[]).indexed)
                _navItem(
                  pair.name,
                  Icons.folder_copy_outlined,
                  _page == _Page.pairs && _selectedPair == index,
                  () {
                    if (drawer) Navigator.pop(context);
                    setState(() {
                      _selectedPair = index;
                      _page = _Page.pairs;
                    });
                  },
                ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 17),
                child: Divider(height: 1),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(9, 0, 9, 8),
                child: Text(
                  '同步演示',
                  style: type(11, weight: FontWeight.w600, color: muted),
                ),
              ),
              for (final (index, group) in _groups.indexed)
                _navItem(
                  group.name,
                  Icons.folder_outlined,
                  _page == _Page.sync && _selected == index,
                  () {
                    if (drawer) Navigator.pop(context);
                    _select(_Page.sync, group: index);
                  },
                  count: group.members.length,
                ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 17),
                child: Divider(height: 1),
              ),
              for (final page in [_Page.devices, _Page.backups, _Page.activity])
                _navItem(page.label, page.icon, _page == page, () {
                  if (drawer) Navigator.pop(context);
                  _select(page);
                }),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(13, 5, 13, 14),
          child: _navItem(
            '设置',
            _Page.settings.icon,
            _page == _Page.settings,
            () {
              if (drawer) Navigator.pop(context);
              _select(_Page.settings);
            },
          ),
        ),
      ],
    ),
  );

  Widget _navItem(
    String title,
    IconData icon,
    bool selected,
    VoidCallback tap, {
    int? count,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: selected ? const Color(0xffdce8db) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: tap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Icon(icon, color: selected ? green : muted, size: 17),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: type(
                      13,
                      color: selected ? green : ink,
                      weight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (count != null)
                  Text('$count', style: type(11, color: muted)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body() => switch (_page) {
    _Page.pairs => _pairBody(),
    _Page.sync => SyncPage(
      group: _group,
      sync: _sync,
      resolve: _resolve,
      openActivity: () => _select(_Page.activity),
    ),
    _Page.devices => _devices(),
    _Page.backups => _backups(),
    _Page.activity => _secondary(
      '活动记录',
      _group.name,
      ActivityList(entries: [..._backupActivity, ..._group.activity]),
    ),
    _Page.settings => _secondary(
      '设置',
      '同步偏好',
      Panel(
        child: SwitchListTile(
          value: _autoSync,
          onChanged: (value) => setState(() => _autoSync = value),
          title: Text('打开应用时自动同步', style: type(14, weight: FontWeight.w700)),
          subtitle: Text('演示中可切换此设置', style: type(12, color: muted)),
        ),
      ),
    ),
  };

  Widget _pairBody() {
    if (_pairLoadFailed) {
      return _secondary(
        '文件夹配对',
        '未能读取已保存的配对',
        Align(
          alignment: Alignment.centerLeft,
          child: ActionButton('重新读取', onPressed: _loadPairs),
        ),
      );
    }
    final pairs = _pairs;
    if (pairs == null) return const Center(child: CircularProgressIndicator());
    if (_selectedPair case final index?) {
      final pair = pairs[index];
      final active = _activeSyncs[index];
      return FolderPairPage(
        pair: pair,
        edit: () => _editPair(index),
        add: () => _editPair(),
        sync: kIsWeb ? null : () => _syncPair(index, pair),
        syncing: active != null,
        paused: active?.control.paused ?? false,
        atPause: active?.atPause ?? false,
        stopping: active?.control.stopRequested ?? false,
        progress: active?.progress,
        recent: active?.recent ?? const [],
        togglePause: () {
          if (active == null) return;
          setState(() {
            if (active.control.paused) {
              active.atPause = false;
              active.control.resume();
            } else {
              active.control.pause();
            }
          });
        },
        stop: () => setState(() => active?.control.stop()),
        openHistory: () => _openHistory(index, pair),
        lastResult: _pairResults[index],
      );
    }
    return _secondary(
      '文件夹配对',
      '为不同的文件夹各建一组，保存后下次打开可直接使用。',
      Panel(
        padding: const EdgeInsets.all(18),
        child: Text(
          '还没有配对。先添加两台设备，并为每台指定一个对应文件夹。',
          style: type(13, color: muted),
        ),
      ),
      action: ActionButton(
        '新建配对',
        icon: Icons.add_rounded,
        primary: true,
        onPressed: () => _editPair(),
      ),
    );
  }

  Widget _secondary(
    String title,
    String subtitle,
    Widget content, {
    Widget? action,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 12,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: type(34, weight: FontWeight.w700, spacing: -1.4),
              ),
              const SizedBox(height: 6),
              Text(subtitle, style: type(13, color: muted)),
            ],
          ),
          ?action,
        ],
      ),
      const SizedBox(height: 26),
      content,
    ],
  );

  Widget _devices() {
    final devices = <String, Member>{
      for (final group in _groups)
        for (final member in group.members) member.name: member,
    };
    return _secondary(
      '设备',
      '${devices.length} 台已登记设备',
      Panel(
        child: Column(
          children: [
            for (final (index, member) in devices.values.indexed) ...[
              if (index > 0) const Divider(height: 1),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 17,
                  vertical: 7,
                ),
                leading: IconTile(member.kind.icon),
                title: Text(
                  member.name,
                  style: type(14, weight: FontWeight.w700),
                ),
                subtitle: Text(
                  member.kind.label,
                  style: type(12, color: muted),
                ),
                trailing: StatusText(
                  member.available ? '在线' : '未连接',
                  member.available ? green : soft,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _backups() => _secondary(
    '版本备份',
    '个人文档',
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          color: paleGreen,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const IconTile(
                Icons.inventory_2_outlined,
                color: green,
                background: Color(0xffdce9dd),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('本地备份库', style: type(14, weight: FontWeight.w700)),
                    Text(
                      '~/FileSync Vault/Personal',
                      style: type(12, color: muted, mono: true),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 25),
        const SectionHeading('历史快照'),
        const SizedBox(height: 11),
        Panel(
          child: Column(
            children: [
              for (final (index, snapshot) in _snapshots.indexed) ...[
                if (index > 0) const Divider(height: 1),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 5,
                  ),
                  leading: const IconTile(Icons.history_rounded),
                  title: Text(
                    snapshot,
                    style: type(13, weight: FontWeight.w700),
                  ),
                  trailing: TextButton(
                    onPressed: () => _restore(snapshot),
                    child: const Text('恢复…'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
    action: ActionButton(
      _backingUp ? '正在备份…' : '立即备份',
      primary: true,
      icon: Icons.add_rounded,
      onPressed: _backingUp ? null : _backup,
    ),
  );
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) => Container(
    height: 36,
    padding: const EdgeInsets.symmetric(horizontal: 32),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: border)),
    ),
    child: Row(
      children: [
        const StatusText('局域网模式', green),
        const Spacer(),
        const Icon(Icons.laptop_mac_rounded, size: 14, color: muted),
        const SizedBox(width: 7),
        Text('本机 · MacBook Pro', style: type(11, color: muted)),
      ],
    ),
  );
}

class _InputDialog extends StatefulWidget {
  const _InputDialog({
    required this.title,
    required this.label,
    required this.confirm,
    this.hint,
    this.description,
  });

  final String title;
  final String label;
  final String confirm;
  final String? hint;
  final String? description;

  @override
  State<_InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<_InputDialog> {
  final _form = GlobalKey<FormState>();
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _submit() {
    if (_form.currentState!.validate()) {
      Navigator.pop(context, _input.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 335,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.description != null) ...[
              Text(widget.description!, style: type(13, color: muted)),
              const SizedBox(height: 14),
            ],
            TextFormField(
              controller: _input,
              autofocus: true,
              decoration: InputDecoration(
                labelText: widget.label,
                hintText: widget.hint,
              ),
              validator: (value) {
                final text = value?.trim() ?? '';
                return text.isEmpty ? '请输入${widget.label}' : null;
              },
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      ActionButton(widget.confirm, primary: true, onPressed: _submit),
    ],
  );
}
