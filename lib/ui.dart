import 'package:flutter/material.dart';

const ink = Color(0xff18241e);
const muted = Color(0xff56635b);
const soft = Color(0xff626e65);
const border = Color(0xffdfe5dd);
const paper = Color(0xfff8f9f6);
const sidebar = Color(0xffeef1eb);
const green = Color(0xff24563e);
const paleGreen = Color(0xffe9f1e9);
const amber = Color(0xff875425);

TextStyle type(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color color = ink,
  double? spacing,
  bool mono = false,
}) => TextStyle(
  fontSize: size,
  fontWeight: weight,
  color: color,
  letterSpacing: spacing,
  fontFamily: mono ? 'Menlo' : null,
  fontFamilyFallback: mono ? const ['Consolas', 'monospace'] : null,
  height: 1.35,
);

ThemeData appTheme() => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(seedColor: green)
      .copyWith(primary: green, surface: Colors.white, onSurface: ink),
  scaffoldBackgroundColor: paper,
  fontFamilyFallback: const [
    'PingFang SC',
    'Microsoft YaHei',
    'Noto Sans CJK SC',
  ],
  dividerColor: border,
  tooltipTheme: const TooltipThemeData(
    waitDuration: Duration(milliseconds: 400),
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: paper,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  ),
  inputDecorationTheme: InputDecorationTheme(
    isDense: true,
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: border),
    ),
  ),
);

class ActionButton extends StatelessWidget {
  const ActionButton(
    this.label, {
    super.key,
    this.icon,
    this.onPressed,
    this.primary = false,
  });
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    );
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 39)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 13),
      ),
      shape: WidgetStatePropertyAll(shape),
      textStyle: WidgetStatePropertyAll(type(13, weight: FontWeight.w600)),
      iconSize: const WidgetStatePropertyAll(17),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon), const SizedBox(width: 7)],
        Text(label),
      ],
    );
    if (primary) {
      return FilledButton(onPressed: onPressed, style: style, child: child);
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: style.copyWith(
        side: const WidgetStatePropertyAll(BorderSide(color: border)),
        foregroundColor: const WidgetStatePropertyAll(ink),
        backgroundColor: const WidgetStatePropertyAll(Colors.white),
      ),
      child: child,
    );
  }
}

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.color = Colors.white,
    this.padding,
  });
  final Widget child;
  final Color color;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      border: Border.all(color: border),
      borderRadius: BorderRadius.circular(12),
    ),
    child: child,
  );
}

class IconTile extends StatelessWidget {
  const IconTile(
    this.icon, {
    super.key,
    this.color = muted,
    this.background = sidebar,
    this.size = 37,
  });
  final IconData icon;
  final Color color;
  final Color background;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(9),
    ),
    child: Icon(icon, color: color, size: size * .52),
  );
}

class StatusText extends StatelessWidget {
  const StatusText(this.label, this.color, {super.key});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 7),
      Text(
        label,
        style: type(12, color: color, weight: FontWeight.w500),
      ),
    ],
  );
}

class Wordmark extends StatelessWidget {
  const Wordmark({super.key});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: green,
          borderRadius: BorderRadius.circular(9),
        ),
        child: const Icon(
          Icons.swap_horiz_rounded,
          color: Colors.white,
          size: 24,
        ),
      ),
      const SizedBox(width: 10),
      Flexible(
        child: Text(
          'FileSync',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: type(20, weight: FontWeight.w700, spacing: -.65),
        ),
      ),
    ],
  );
}
