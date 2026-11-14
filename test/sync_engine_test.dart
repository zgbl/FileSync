import 'dart:async';
import 'dart:io';

import 'package:file_sync/folder_pairs.dart';
import 'package:file_sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late Directory a;
  late Directory b;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('filesync_test');
    a = await Directory('${temp.path}/a').create();
    b = await Directory('${temp.path}/b').create();
  });
  tearDown(() => temp.delete(recursive: true));

  Future<File> write(
    Directory root,
    String name,
    String text,
    DateTime at,
  ) async {
    final file = File('${root.path}/$name');
    await file.parent.create(recursive: true);
    await file.writeAsString(text);
    await file.setLastModified(at);
    return file;
  }

  test('copies missing files both ways and newest version wins', () async {
    final old = DateTime(2026, 1, 1);
    final recent = DateTime(2026, 6, 1);
    await write(a, 'only-a.txt', 'A', old);
    await write(b, 'sub/only-b.txt', 'B', old);
    await write(a, 'shared.txt', 'old', old);
    await write(b, 'shared.txt', 'new', recent);

    final result = await syncEndpoints([
      FolderEndpoint('A', a.path),
      FolderEndpoint('B', b.path),
      FolderEndpoint('Offline', '${temp.path}/missing'),
    ]);

    expect(result.copied, 2);
    expect(result.updated, 1);
    expect(result.unreachable, ['Offline']);
    expect(await File('${b.path}/only-a.txt').readAsString(), 'A');
    expect(await File('${a.path}/sub/only-b.txt').readAsString(), 'B');
    expect(await File('${a.path}/shared.txt').readAsString(), 'new');
    final backups = Directory('${a.path}/$metaDirName/versions')
        .listSync(recursive: true)
        .whereType<File>()
        .toList();
    expect(backups.single.readAsStringSync(), 'old');

    final again = await syncEndpoints([
      FolderEndpoint('A', a.path),
      FolderEndpoint('B', b.path),
    ]);
    expect(again.changed, 0);
  });

  test('pause blocks the next file, resume proceeds, and stop keeps completed transfers', () async {
    final time = DateTime(2026, 1, 1);
    for (final name in ['one.txt', 'two.txt', 'three.txt']) {
      await write(a, name, name, time);
    }
    final control = SyncControl();
    final paused = Completer<void>();
    final entries = <String>[];
    final progress = <String>[];
    final task = syncEndpoints(
      [FolderEndpoint('A', a.path), FolderEndpoint('B', b.path)],
      control: control,
      onProgress: progress.add,
      onTransfer: (entry) {
        entries.add(entry);
        if (entries.length == 1) {
          control.pause();
          paused.complete();
        } else {
          control.stop();
        }
      },
    );
    await paused.future;
    expect(await b.list().length, 1);
    expect(progress.last, entries.single);
    control.resume();
    final result = await task;
    expect(result.stopped, isTrue);
    expect(result.copied, 2);
    expect(result.transfers, entries);
    expect(await b.list().length, 2);
  });

  test('stop wakes a paused sync without starting another file', () async {
    final control = SyncControl()..pause();
    final task = syncEndpoints([
      FolderEndpoint('A', a.path),
      FolderEndpoint('B', b.path),
    ], control: control);
    control.stop();
    expect((await task).stopped, isTrue);
    expect(await b.list().isEmpty, isTrue);
  });

  for (final stop in [false, true]) {
    test(
      '${stop ? 'stop' : 'pause'} during replacement commits the file and its backup',
      () async {
        final old = DateTime(2026, 1, 1);
        final newer = DateTime(2026, 6, 1);
        final c = await Directory('${temp.path}/c').create();
        await write(a, 'shared.txt', 'new contents', newer);
        final destination = await write(b, 'shared.txt', 'old contents', old);
        final next = await write(c, 'shared.txt', 'other contents', old);
        final paused = Completer<void>();
        final control = SyncControl(onPaused: paused.complete);
        final progress = <String>[];
        final task = syncEndpoints(
          [
            FolderEndpoint('A', a.path),
            FolderEndpoint('B', b.path),
            FolderEndpoint('C', c.path),
          ],
          control: control,
          onProgress: (message) {
            if (!message.startsWith('更新 ')) return;
            progress.add(message);
            if (progress.length != 1) return;
            expect(destination.readAsStringSync(), 'old contents');
            if (stop) {
              control.stop();
            } else {
              control.pause();
            }
          },
        );

        if (stop) {
          await task;
        } else {
          await Future.any([paused.future, task]);
          expect(paused.isCompleted, isTrue);
        }
        expect(await destination.readAsString(), 'new contents');
        expect(await next.readAsString(), 'other contents');
        final backup = await Directory('${b.path}/$metaDirName/versions')
            .list(recursive: true)
            .where((entry) => entry is File)
            .single;
        expect(await File(backup.path).readAsString(), 'old contents');
        if (!stop) control.resume();
        final result = await task;
        expect(result.stopped, stop);
        expect(result.updated, stop ? 1 : 2);
        expect(result.errors, isEmpty);
        expect(result.transfers.first, '更新 shared.txt\nA → B');
      },
    );
  }

  test(
    'a source changed after scanning cannot replace the destination',
    () async {
      final source = await write(a, 'shared.txt', 'new', DateTime(2026, 6, 1));
      final destination = await write(
        b,
        'shared.txt',
        'old',
        DateTime(2026, 1, 1),
      );
      final result = await syncEndpoints(
        [FolderEndpoint('A', a.path), FolderEndpoint('B', b.path)],
        onProgress: (message) {
          if (message.startsWith('更新 ')) {
            source.writeAsStringSync('modified after scan');
          }
        },
      );
      expect(result.errors, hasLength(1));
      expect(result.updated, 0);
      expect(await destination.readAsString(), 'old');
      expect(await b.list().length, 1);
    },
  );

  test('one-way backup merges year folders without reading target history into the source', () async {
    final old = DateTime(2026, 1, 1);
    final recent = DateTime(2026, 6, 1);
    await write(a, '2026/new.jpg', 'new photo', recent);
    await write(a, '2026/update.jpg', 'new edit', recent);
    await write(a, '2026/keep.jpg', 'old edit', old);
    await write(b, '2026/update.jpg', 'old edit', old);
    await write(b, '2026/keep.jpg', 'new edit', recent);
    await write(b, '2026/other.jpg', 'same year', old);
    await write(b, '1999/archive.jpg', 'history', old);
    final progress = <String>[];
    final result = await syncEndpoints(
      [FolderEndpoint('Computer', a.path), FolderEndpoint('Drive', b.path)],
      backupSource: 'Computer',
      onProgress: progress.add,
    );

    expect(result.scanned, 3);
    expect(result.copied, 1);
    expect(result.updated, 1);
    expect(result.errors, isEmpty);
    expect(result.newerTargets, ['2026/keep.jpg（Computer → Drive）']);
    expect(progress, isNot(contains('正在扫描 Drive')));
    expect(await File('${a.path}/2026/other.jpg').exists(), isFalse);
    expect(await Directory('${a.path}/1999').exists(), isFalse);
    expect(await File('${b.path}/1999/archive.jpg').readAsString(), 'history');
    expect(await File('${b.path}/2026/other.jpg').readAsString(), 'same year');
    expect(await File('${b.path}/2026/new.jpg').readAsString(), 'new photo');
    expect(await File('${b.path}/2026/update.jpg').readAsString(), 'new edit');
    expect(await File('${b.path}/2026/keep.jpg').readAsString(), 'new edit');
    expect(await File('${a.path}/2026/keep.jpg').readAsString(), 'old edit');
    final backup = await Directory('${b.path}/$metaDirName/versions')
        .list(recursive: true)
        .where((entry) => entry is File)
        .single;
    expect(await File(backup.path).readAsString(), 'old edit');
  });

  test(
    'one-way backup cannot write to a folder nested inside its source',
    () async {
      final nested = await Directory('${a.path}/nested').create();
      await write(a, 'photo.jpg', 'photo', DateTime(2026, 1, 1));
      await expectLater(
        syncEndpoints([
          FolderEndpoint('Computer', a.path),
          FolderEndpoint('Drive', nested.path),
        ], backupSource: 'Computer'),
        throwsA(isA<SyncException>()),
      );
      expect(await nested.list().isEmpty, isTrue);
    },
  );

  test('needs two reachable folders', () async {
    expect(
      () => syncEndpoints([
        FolderEndpoint('A', a.path),
        FolderEndpoint('X', '${temp.path}/nope'),
      ]),
      throwsA(isA<SyncException>()),
    );
  });
}
