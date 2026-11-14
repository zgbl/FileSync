import 'package:flutter/material.dart';

enum DeviceKind {
  mac('macOS', Icons.laptop_mac_rounded),
  windows('Windows', Icons.desktop_windows_outlined),
  drive('移动硬盘', Icons.sd_storage_outlined),
  android('Android', Icons.phone_android_rounded),
  ios('iOS', Icons.phone_iphone_rounded);

  const DeviceKind(this.label, this.icon);

  final String label;
  final IconData icon;
}

class Member {
  Member(this.name, this.kind, this.path, {this.available = true});

  final String name;
  final DeviceKind kind;
  final bool available;
  String path;
}

class SyncGroup {
  SyncGroup(
    this.name, {
    List<Member>? members,
    this.filesToSync = 0,
    this.size = '',
    this.conflict = false,
    List<Activity>? activity,
  }) : members = members ?? [],
       activity = [...?activity];

  final String name;
  final List<Member> members;
  final List<Activity> activity;
  final String size;
  int filesToSync;
  bool conflict;
  bool syncing = false;
  bool hasSynced = false;

  int get availableCount => members.where((member) => member.available).length;
  int get offlineCount => members.length - availableCount;
  bool get canSync => availableCount >= 2 && !syncing;
}

class Activity {
  const Activity(this.title, this.detail, this.time, this.icon);

  final String title;
  final String detail;
  final String time;
  final IconData icon;
}

List<SyncGroup> exampleGroups() => [
  SyncGroup(
    '项目资料',
    members: [
      Member('MacBook Pro', DeviceKind.mac, '~/Documents/Projects'),
      Member('Windows PC', DeviceKind.windows, r'D:\Work\Projects'),
      Member(
        'Travel SSD',
        DeviceKind.drive,
        '/Volumes/TravelSSD/Projects',
        available: false,
      ),
    ],
    filesToSync: 12,
    size: '86.4 MB',
    conflict: true,
    activity: const [
      Activity(
        '同步完成',
        'MacBook Pro 和 Windows PC · 24 个文件',
        '今天 09:41',
        Icons.check_rounded,
      ),
      Activity('移动硬盘已断开', 'Travel SSD', '今天 09:38', Icons.usb_off_rounded),
    ],
  ),
  SyncGroup(
    '照片归档',
    members: [
      Member('MacBook Pro', DeviceKind.mac, '~/Pictures/Archive'),
      Member(
        'Travel SSD',
        DeviceKind.drive,
        '/Volumes/TravelSSD/Photos',
        available: false,
      ),
    ],
  ),
  SyncGroup(
    '个人文档',
    members: [
      Member('MacBook Pro', DeviceKind.mac, '~/Documents/Personal'),
      Member('Windows PC', DeviceKind.windows, r'D:\Personal'),
    ],
  ),
];
