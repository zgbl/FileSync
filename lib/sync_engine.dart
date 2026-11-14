import 'dart:async';
import 'dart:io';

import 'folder_pairs.dart';

/// Folder inside every synced root that holds FileSync's own data.
const metaDirName = '.filesync';
const _tempSuffix = '.filesync-tmp';
const _ignoredNames = {'.DS_Store', 'Thumbs.db', 'desktop.ini'};

/// FAT/exFAT drives store modification times with 2-second precision.
const _timeTolerance = Duration(seconds: 2);

class SyncException implements Exception {
  const SyncException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SyncControl {
  SyncControl({this.onPaused});

  final void Function()? onPaused;
  Completer<void>? _pause;
  bool _stopRequested = false;

  bool get stopRequested => _stopRequested;

  bool get paused => _pause != null;

  void pause() {
    if (!stopRequested) _pause ??= Completer<void>();
  }

  void resume() {
    final pause = _pause;
    _pause = null;
    pause?.complete();
  }

  void stop() {
    _stopRequested = true;
    resume();
  }

  Future<void> checkpoint() async {
    while (_pause != null) {
      final pending = _pause!;
      onPaused?.call();
      await pending.future;
    }
    if (stopRequested) throw const _SyncStopped();
  }
}

class _SyncStopped implements Exception {
  const _SyncStopped();
}

class SyncResult {
  DateTime finishedAt = DateTime.now();
  int scanned = 0;
  bool stopped = false;
  String? failure;
  final List<String> transfers = [];
  final List<String> newerTargets = [];
  bool get incomplete =>
      stopped ||
      failure != null ||
      unreachable.isNotEmpty ||
      conflicts.isNotEmpty ||
      errors.isNotEmpty;
  int copied = 0;
  int updated = 0;
  final List<String> unreachable = [];
  final List<String> conflicts = [];
  final List<String> errors = [];

  int get changed => copied + updated;

  Map<String, Object?> toJson() => {
    'finishedAt': finishedAt.toUtc().toIso8601String(),
    'scanned': scanned,
    'copied': copied,
    'updated': updated,
    'stopped': stopped,
    'failure': failure,
    'transfers': transfers,
    'newerTargets': newerTargets,
    'unreachable': unreachable,
    'conflicts': conflicts,
    'errors': errors,
  };

  factory SyncResult.fromJson(Map<String, dynamic> json) => SyncResult()
    ..finishedAt = DateTime.parse(json['finishedAt'] as String)
    ..scanned = json['scanned'] as int
    ..copied = json['copied'] as int
    ..updated = json['updated'] as int
    ..stopped = json['stopped'] as bool
    ..failure = json['failure'] as String?
    ..transfers.addAll((json['transfers'] as List).cast<String>())
    ..newerTargets.addAll((json['newerTargets'] as List? ?? []).cast<String>())
    ..unreachable.addAll((json['unreachable'] as List).cast<String>())
    ..conflicts.addAll((json['conflicts'] as List).cast<String>())
    ..errors.addAll((json['errors'] as List).cast<String>());

  SyncResult();
}

class _Entry {
  const _Entry(this.size, this.modified);
  final int size;
  final DateTime modified;
}

String expandHome(String path) {
  if (path == '~' || path.startsWith('~/')) {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home != null) return home + path.substring(1);
  }
  return path;
}

String _join(String root, String relative) =>
    root +
    Platform.pathSeparator +
    relative.replaceAll('/', Platform.pathSeparator);

Future<Map<String, _Entry>> _scan(String root, SyncControl control) async {
  final files = <String, _Entry>{};
  final prefix = root.endsWith(Platform.pathSeparator)
      ? root.length
      : root.length + 1;
  await for (final entity in Directory(
    root,
  ).list(recursive: true, followLinks: false)) {
    await control.checkpoint();
    if (entity is! File) continue;
    final relative = entity.path
        .substring(prefix)
        .replaceAll(Platform.pathSeparator, '/');
    final parts = relative.split('/');
    if (parts.first == metaDirName) continue;
    final name = parts.last;
    if (_ignoredNames.contains(name) || name.endsWith(_tempSuffix)) continue;
    final stat = await entity.stat();
    files[relative] = _Entry(stat.size, stat.modified);
  }
  return files;
}

Future<_Entry?> _targetEntry(String root, String relative) async {
  var path = root;
  final components = relative.split('/');
  for (final (index, component) in components.indexed) {
    path = _join(path, component);
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return null;
    if (index == components.length - 1 && type == FileSystemEntityType.file) {
      final stat = await File(path).stat();
      if (stat.type == FileSystemEntityType.file) {
        return _Entry(stat.size, stat.modified);
      }
    } else if (index < components.length - 1 &&
        type == FileSystemEntityType.directory) {
      continue;
    }
    throw FileSystemException('目标路径包含链接、类型不符或已发生变化', path);
  }
  return null;
}

bool _overlap(String first, String second) {
  final separator = Platform.pathSeparator;
  String prefix(String path) =>
      path.endsWith(separator) ? path : '$path$separator';
  if (Platform.isWindows || Platform.isMacOS) {
    first = first.toLowerCase();
    second = second.toLowerCase();
  }
  return first == second ||
      first.startsWith(prefix(second)) ||
      second.startsWith(prefix(first));
}

bool _sameTime(DateTime a, DateTime b) =>
    a.difference(b).abs() <= _timeTolerance;

String _stamp(DateTime time) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${time.year}${two(time.month)}${two(time.day)}-'
      '${two(time.hour)}${two(time.minute)}${two(time.second)}';
}

Future<void> _stageCopy(File source, File staged, _Entry expected) async {
  await source.copy(staged.path);
  final after = await source.stat();
  if (after.type != FileSystemEntityType.file ||
      after.size != expected.size ||
      after.modified != expected.modified ||
      await staged.length() != expected.size) {
    throw FileSystemException('文件在同步期间发生变化或副本不完整', source.path);
  }
  await staged.setLastModified(expected.modified);
}

Future<void> _discardScratch(Directory scratch) async {
  try {
    await scratch.delete(recursive: true);
  } on FileSystemException {
    // The scanner ignores staged files if a volume disconnects during cleanup.
  }
}

Future<void> _copy(
  String from,
  String to,
  _Entry source, {
  required _Entry? existing,
  required String? backup,
}) async {
  final destination = File(to);
  await destination.parent.create(recursive: true);
  final scratch = await destination.parent.createTemp('.filesync-');
  try {
    final temp = File(_join(scratch.path, 'new$_tempSuffix'));
    await _stageCopy(File(from), temp, source);
    if (backup != null) {
      if (await FileSystemEntity.type(to, followLinks: false) !=
          FileSystemEntityType.file) {
        throw FileSystemException('目标文件在同步期间发生变化', to);
      }
      final version = File(backup);
      await version.parent.create(recursive: true);
      final backupScratch = await version.parent.createTemp('.filesync-');
      try {
        final staged = File(_join(backupScratch.path, 'backup$_tempSuffix'));
        await _stageCopy(destination, staged, existing!);
        await staged.rename(version.path);
      } finally {
        await _discardScratch(backupScratch);
      }
    } else if (await FileSystemEntity.type(to, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw FileSystemException('目标文件在同步期间出现，已跳过覆盖', to);
    }
    // Publish by rename on the destination filesystem. The previous file
    // stays at its original path until the complete new copy is available.
    await temp.rename(to);
  } finally {
    await _discardScratch(scratch);
  }
}

/// Two-way sync of every reachable endpoint: the newest copy of each file
/// wins. Files that would be overwritten are first copied into
/// `<root>/.filesync/versions/<time>/`. Deletions are not propagated.
Future<SyncResult> syncEndpoints(
  List<FolderEndpoint> endpoints, {
  String? backupSource,
  SyncControl? control,
  void Function(String message)? onProgress,
  void Function(String message)? onTransfer,
}) async {
  final session = control ?? SyncControl();
  final result = SyncResult();
  try {
    await _sync(
      endpoints,
      backupSource,
      session,
      result,
      onProgress,
      onTransfer,
    );
    result.stopped = session.stopRequested;
  } on _SyncStopped {
    result.stopped = true;
  } finally {
    result.finishedAt = DateTime.now();
  }
  return result;
}

Future<void> _sync(
  List<FolderEndpoint> endpoints,
  String? backupSource,
  SyncControl control,
  SyncResult result,
  void Function(String message)? onProgress,
  void Function(String message)? onTransfer,
) async {
  final started = DateTime.now();
  final roots = <String, String>{}; // device -> root
  for (final endpoint in endpoints) {
    await control.checkpoint();
    final root = expandHome(endpoint.path);
    if (await Directory(root).exists()) {
      roots[endpoint.device] = root;
    } else {
      result.unreachable.add(endpoint.device);
    }
  }
  if (backupSource != null && !roots.containsKey(backupSource)) {
    throw SyncException('备份来源「$backupSource」无法访问。');
  }
  if (roots.length < 2) {
    throw SyncException(
      roots.isEmpty
          ? '所有文件夹都无法访问，请检查硬盘或网络共享是否已连接。'
          : '只有「${roots.keys.single}」可以访问，至少需要两个文件夹才能同步。',
    );
  }

  if (backupSource != null) {
    // Resolve aliases and reject nested roots before writing any files.
    final resolved = <String>[];
    for (final root in roots.values) {
      await control.checkpoint();
      final canonical = await Directory(root).resolveSymbolicLinks();
      if (resolved.any((other) => _overlap(other, canonical))) {
        throw const SyncException('备份组的文件夹不能相同或互相包含。');
      }
      resolved.add(canonical);
    }
  }

  final listings = <String, Map<String, _Entry>>{};
  for (final MapEntry(key: device, value: root) in roots.entries) {
    if (backupSource != null && device != backupSource) continue;
    try {
      await control.checkpoint();
      onProgress?.call('正在扫描 $device');
      listings[device] = await _scan(root, control);
    } on FileSystemException catch (error) {
      throw SyncException(
        '无法读取「$device」：${error.osError?.message ?? error.message}',
      );
    }
  }

  final allFiles = {for (final files in listings.values) ...files.keys};
  result.scanned = allFiles.length;
  final backupStamp = '${_stamp(started)}-${started.microsecondsSinceEpoch}';

  for (final relative in allFiles) {
    // Pick the newest copy as the source.
    String? source;
    _Entry? newest;
    for (final MapEntry(key: device, value: files) in listings.entries) {
      final entry = files[relative];
      if (entry == null) continue;
      if (newest == null || entry.modified.isAfter(newest.modified)) {
        source = device;
        newest = entry;
      }
    }
    final latest = newest!;
    final sourcePath = _join(roots[source]!, relative);

    for (final MapEntry(key: device, value: root) in roots.entries) {
      await control.checkpoint();
      if (device == source) continue;
      final target = _join(root, relative);
      final direction = '$source → $device';
      try {
        final existing = backupSource == null
            ? listings[device]![relative]
            : await _targetEntry(root, relative);
        await control.checkpoint();
        if (existing != null && _sameTime(existing.modified, latest.modified)) {
          if (existing.size != latest.size) {
            result.conflicts.add('$relative（$direction）');
          }
          continue;
        }
        if (backupSource != null &&
            existing != null &&
            existing.modified.isAfter(latest.modified)) {
          result.newerTargets.add('$relative（$direction）');
          continue;
        }
        // Once announced, finish the replacement and logging before pausing.
        final action = existing == null ? '新增' : '更新';
        onProgress?.call('$action $relative\n$direction');
        final backup = existing == null
            ? null
            : _join(root, '$metaDirName/versions/$backupStamp/$relative');
        await _copy(
          sourcePath,
          target,
          latest,
          existing: existing,
          backup: backup,
        );
        if (existing == null) {
          result.copied++;
        } else {
          result.updated++;
        }
        final entry = '$action $relative\n$direction';
        result.transfers.add(entry);
        onTransfer?.call(entry);
      } on FileSystemException catch (error) {
        result.errors.add(
          '$relative（$direction）：${error.osError?.message ?? error.message}',
        );
      }
    }
  }
}
