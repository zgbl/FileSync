import 'package:flutter/material.dart';

import 'ui.dart';
import 'workspace.dart';

class SyncPage extends StatelessWidget {
  const SyncPage({
    super.key,
    required this.group,
    required this.sync,
    required this.resolve,
    required this.openActivity,
  });

  final SyncGroup group;
  final VoidCallback sync;
  final VoidCallback resolve;
  final VoidCallback openActivity;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 850;
        final members = _Members(group: group);
        final plan = _SyncPlan(group: group, resolve: resolve);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _GroupHeading(group: group, sync: sync),
            const SizedBox(height: 25),
            _SyncStatus(group: group),
            const SizedBox(height: 28),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: members),
                  const SizedBox(width: 23),
                  SizedBox(width: 258, child: plan),
                ],
              )
            else ...[
              members,
              const SizedBox(height: 23),
              plan,
            ],
            const SizedBox(height: 28),
            SectionHeading(
              '最近活动',
              trailing: TextButton(
                onPressed: openActivity,
                child: const Text('查看全部'),
              ),
            ),
            const SizedBox(height: 9),
            ActivityList(entries: group.activity.take(2).toList()),
          ],
        );
      },
    );
  }
}

class _GroupHeading extends StatelessWidget {
  const _GroupHeading({required this.group, required this.sync});
  final SyncGroup group;
  final VoidCallback sync;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 14,
      runSpacing: 15,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              group.name,
              style: type(34, weight: FontWeight.w700, spacing: -1.4),
            ),
            const SizedBox(height: 6),
            Text(
              '双向同步  /  ${group.members.length} 个成员',
              style: type(13, color: muted),
            ),
          ],
        ),
        ActionButton(
          group.syncing ? '同步中…' : '同步全部',
          primary: true,
          icon: Icons.sync_rounded,
          onPressed: group.canSync ? sync : null,
        ),
      ],
    );
  }
}

class _SyncStatus extends StatelessWidget {
  const _SyncStatus({required this.group});
  final SyncGroup group;

  @override
  Widget build(BuildContext context) {
    final String title;
    final String detail;
    if (group.syncing) {
      title = '正在同步在线成员';
      detail = '正在扫描目录并校验文件';
    } else if (group.members.length < 2) {
      title = '添加成员以开始同步';
      detail = '为每台设备指定一个文件夹';
    } else if (group.offlineCount > 0) {
      title = '等待 ${group.offlineCount} 个成员';
      detail = group.canSync ? '在线成员可继续同步，离线成员连接后补齐' : '至少需要两个在线成员才能开始同步';
    } else if (group.hasSynced && group.conflict) {
      title = '有文件冲突待处理';
      detail = '其他文件已完成同步';
    } else {
      title = group.hasSynced ? '本轮同步已完成' : '所有成员已就绪';
      detail = group.hasSynced ? '在线成员的文件已校验' : '可随时开始一轮同步';
    }
    return Panel(
      color: paleGreen,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          IconTile(
            group.syncing ? Icons.sync_rounded : Icons.hub_outlined,
            size: 43,
            background: const Color(0xffdce9dd),
            color: green,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: type(15, weight: FontWeight.w700, color: green),
                ),
                const SizedBox(height: 3),
                Text(detail, style: type(12, color: muted)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${group.availableCount} / ${group.members.length} 在线',
            style: type(12, color: green, weight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(this.label, {super.key, this.trailing});
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(label, style: type(17, weight: FontWeight.w700)),
      ),
      ?trailing,
    ],
  );
}

class _Members extends StatelessWidget {
  const _Members({required this.group});
  final SyncGroup group;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeading('成员文件夹（示例）'),
        const SizedBox(height: 11),
        Panel(
          child: group.members.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    '还没有成员。添加设备或移动硬盘上的文件夹。',
                    style: type(13, color: muted),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, box) {
                    final table = box.maxWidth >= 515;
                    return Column(
                      children: [
                        if (table) const _MemberHeaders(),
                        for (final (index, member)
                            in group.members.indexed) ...[
                          if (table || index > 0)
                            const Divider(height: 1, thickness: 1),
                          _MemberRow(member: member, table: table),
                        ],
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _MemberHeaders extends StatelessWidget {
  const _MemberHeaders();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(15, 10, 16, 10),
    child: Row(
      children: [
        Expanded(
          flex: 3,
          child: Text(
            '设备',
            style: type(11, color: muted, weight: FontWeight.w600),
          ),
        ),
        Expanded(
          flex: 4,
          child: Text(
            '文件夹路径',
            style: type(11, color: muted, weight: FontWeight.w600),
          ),
        ),
        SizedBox(
          width: 76,
          child: Text(
            '状态',
            style: type(11, color: muted, weight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member, required this.table});
  final Member member;
  final bool table;

  @override
  Widget build(BuildContext context) {
    final path = Tooltip(
      message: member.path,
      child: Text(
        member.path,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
        style: type(11.5, color: muted, mono: true),
      ),
    );
    final info = Row(
      children: [
        IconTile(member.kind.icon),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                member.name,
                overflow: TextOverflow.ellipsis,
                style: type(13, weight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              if (table)
                Text(member.kind.label, style: type(11, color: soft))
              else
                path,
            ],
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 12, 9, 12),
      child: Row(
        children: [
          Expanded(flex: 3, child: info),
          if (table)
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: path,
              ),
            ),
          if (!table) const SizedBox(width: 8),
          SizedBox(
            width: table ? 76 : null,
            child: StatusText(
              member.available ? '在线' : '未连接',
              member.available ? green : soft,
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncPlan extends StatelessWidget {
  const _SyncPlan({required this.group, required this.resolve});
  final SyncGroup group;
  final VoidCallback resolve;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 39, child: SectionHeading('本轮预览')),
      const SizedBox(height: 11),
      Panel(
        padding: const EdgeInsets.fromLTRB(15, 7, 15, 8),
        child: Column(
          children: [
            _PlanItem(
              Icons.arrow_upward_rounded,
              '${group.filesToSync} 个文件待同步',
              group.filesToSync == 0 ? '当前没有待传输的文件' : '新增与更新 · ${group.size}',
              color: green,
              background: paleGreen,
            ),
            if (group.conflict) ...[
              const Divider(height: 1),
              _PlanItem(
                Icons.alt_route_rounded,
                '1 个文件冲突',
                '两台设备都修改了同一文件',
                color: amber,
                background: const Color(0xfff4eee2),
                onPressed: resolve,
              ),
            ],
            if (group.offlineCount > 0) ...[
              const Divider(height: 1),
              _PlanItem(
                Icons.link_off_rounded,
                '${group.offlineCount} 个成员未连接',
                group.members
                    .where((member) => !member.available)
                    .map((member) => member.name)
                    .join('、'),
              ),
            ],
          ],
        ),
      ),
    ],
  );
}

class _PlanItem extends StatelessWidget {
  const _PlanItem(
    this.icon,
    this.label,
    this.detail, {
    this.color = muted,
    this.background = sidebar,
    this.onPressed,
  });
  final IconData icon;
  final String label;
  final String detail;
  final Color color;
  final Color background;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          IconTile(icon, size: 32, color: color, background: background),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: type(12, weight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(detail, style: type(11, color: muted)),
              ],
            ),
          ),
          if (onPressed != null)
            const Icon(Icons.chevron_right_rounded, size: 17, color: muted),
        ],
      ),
    );
    return onPressed == null
        ? content
        : InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onPressed,
            child: content,
          );
  }
}

class ActivityList extends StatelessWidget {
  const ActivityList({super.key, required this.entries});
  final List<Activity> entries;

  @override
  Widget build(BuildContext context) => Panel(
    child: entries.isEmpty
        ? Padding(
            padding: const EdgeInsets.all(18),
            child: Text('此处会显示同步、冲突处理和备份记录。', style: type(13, color: muted)),
          )
        : Column(
            children: [
              for (final (index, entry) in entries.indexed) ...[
                if (index > 0) const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      IconTile(
                        entry.icon,
                        size: 30,
                        color: green,
                        background: paleGreen,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.title,
                              style: type(12.5, weight: FontWeight.w700),
                            ),
                            Text(entry.detail, style: type(11.5, color: muted)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(entry.time, style: type(11, color: muted)),
                    ],
                  ),
                ),
              ],
            ],
          ),
  );
}
