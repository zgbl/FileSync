import 'package:file_sync/folder_pairs.dart';
import 'package:file_sync/main.dart';
import 'package:file_sync/sync_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('saved sync details can be opened from a fresh workspace', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'folder_pairs_v1':
          '[{"name":"工程配对","first":"/Projects","second":"/SSD/Projects"}]',
    });
    final run = SyncResult()
      ..copied = 1
      ..stopped = true
      ..transfers.add('新增 notes.md\nMacBook → SSD');
    await SyncHistoryStore().append(0, run);
    await (await SharedPreferences.getInstance()).reload();
    await tester.pumpWidget(const FileSyncApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('同步日志'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('已停止'));
    await tester.pumpAndSettle();
    expect(find.text('新增 notes.md\nMacBook → SSD'), findsOneWidget);
  });

  testWidgets('two devices save and the same group can grow to five', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final paths = [
      '/Mac/Projects',
      r'D:\Projects',
      '/SSD/Projects',
      '/NAS/Projects',
      '/Linux/Projects',
    ];
    final devices = ['MacBook', 'Windows PC', 'Travel SSD', 'NAS', 'Linux'];
    final selections = [...paths, '/Mac/Photos', '/SSD/Photos'].iterator;
    final app = FileSyncApp(
      folderPicker: (_) async {
        expect(selections.moveNext(), isTrue);
        return selections.current;
      },
    );

    Future<void> tap(String label, {int index = 0}) async {
      final target = find.text(label).at(index);
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    Future<void> enter(int index, String value) async {
      final field = find.byType(TextFormField).at(index);
      await tester.ensureVisible(field);
      await tester.enterText(field, value);
      await tester.pumpAndSettle();
    }

    Future<void> fillDevice(int index, String name) async {
      await enter(1 + index * 2, name);
      await tap('浏览…', index: index);
    }

    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    await tap('新建配对');
    await tap('保存配对');
    expect(find.text('请选择或输入文件夹'), findsNWidgets(2));
    expect(find.byTooltip('移除设备 1'), findsNothing);
    await enter(0, '工程配对');
    await fillDevice(0, devices[0]);
    await fillDevice(1, devices[1]);
    await tap('保存配对');
    expect(find.text('对应文件夹（2 台设备）'), findsOneWidget);

    await tap('编辑配对');
    for (var i = 2; i < devices.length; i++) {
      await tap('添加设备');
      await fillDevice(i, devices[i]);
    }
    await tap('保存配对');
    expect(find.text('对应文件夹（5 台设备）'), findsOneWidget);

    await tap('新建配对');
    await enter(0, '照片配对');
    await fillDevice(0, devices[0]);
    await fillDevice(1, devices[2]);
    await tap('保存配对');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await (await SharedPreferences.getInstance()).reload();
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    expect(find.text('对应文件夹（5 台设备）'), findsOneWidget);
    for (final device in devices) {
      expect(find.text(device), findsOneWidget);
    }
    for (final path in paths) {
      expect(find.text(path), findsOneWidget);
    }
    await tap('照片配对');
    expect(find.text('/Mac/Photos'), findsOneWidget);
    expect(find.text('/SSD/Photos'), findsOneWidget);
  });

  testWidgets('saved two-folder data still opens', (tester) async {
    SharedPreferences.setMockInitialValues({
      'folder_pairs_v1':
          '[{"name":"旧配对","first":"/Projects","second":"/SSD/Projects"}]',
    });
    await tester.pumpWidget(const FileSyncApp());
    await tester.pumpAndSettle();
    expect(find.text('对应文件夹（2 台设备）'), findsOneWidget);
    expect(find.text('/Projects'), findsOneWidget);
    expect(find.text('/SSD/Projects'), findsOneWidget);
  });

  testWidgets('sync keeps the offline member and file conflict pending', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const FileSyncApp());

    await tester.pumpAndSettle();
    await tester.tap(find.text('项目资料'));
    await tester.pumpAndSettle();
    expect(find.text('12 个文件待同步'), findsOneWidget);
    await tester.tap(find.text('同步全部'));
    await tester.pump();
    expect(find.text('正在同步在线成员'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(milliseconds: 1500));
    expect(find.text('0 个文件待同步'), findsOneWidget);
    expect(find.text('1 个成员未连接'), findsOneWidget);
    expect(find.text('1 个文件冲突'), findsOneWidget);

    await tester.tap(find.text('1 个文件冲突'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保留两个版本'));
    await tester.pumpAndSettle();
    expect(find.text('1 个文件冲突'), findsNothing);
    expect(find.text('冲突已处理'), findsOneWidget);
  });

  testWidgets('narrow navigation opens backups and restores to a preview', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const FileSyncApp());
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('打开导航'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('版本备份'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复…').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '~/Documents/Restored');
    await tester.tap(find.text('预览恢复'));
    await tester.pumpAndSettle();
    expect(find.text('恢复预览'), findsOneWidget);
    expect(find.textContaining('~/Documents/Restored'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
