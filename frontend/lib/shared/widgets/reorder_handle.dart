import 'package:flutter/material.dart';

/// 拖拽排序把手，用于 `ReorderableListView`（需关闭默认把手）。
class ReorderHandle extends StatelessWidget {
  const ReorderHandle({
    required this.index,
    this.tooltip = '拖动调整顺序',
    this.size = 19,
    super.key,
  });

  final int index;
  final String tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ReorderableDragStartListener(
      index: index,
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Tooltip(
          message: tooltip,
          child: Icon(
            Icons.drag_indicator,
            size: size,
            color: const Color(0xFF8390A6),
          ),
        ),
      ),
    );
  }
}

/// 拖拽中的行浮起效果，保持与列表项一致的圆角。
Widget reorderProxyDecorator(
  Widget child,
  int index,
  Animation<double> animation,
) {
  return AnimatedBuilder(
    animation: animation,
    builder: (context, innerChild) {
      final value = Curves.easeInOut.transform(animation.value);
      return Material(
        color: Colors.transparent,
        elevation: value * 6,
        borderRadius: BorderRadius.circular(12),
        child: innerChild,
      );
    },
    child: child,
  );
}
