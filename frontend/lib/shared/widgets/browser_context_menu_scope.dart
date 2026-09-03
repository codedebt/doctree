import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 仅当指针处于 [child] 区域内时关闭浏览器自带右键菜单，指针离开后恢复，
/// 使自定义右键菜单不与浏览器菜单冲突，同时不影响页面其他区域。
///
/// 浏览器右键菜单的开关是整个页面级别的，因此这里用指针进入/离开区域来近似
/// 实现局部禁用。非 Web 平台不做任何处理。
class BrowserContextMenuScope extends StatefulWidget {
  const BrowserContextMenuScope({required this.child, super.key});

  final Widget child;

  /// 在 [action] 执行期间保持浏览器右键菜单处于关闭状态。
  ///
  /// 自定义菜单以浮层形式弹出时指针会移出 [child] 区域，用它包裹弹出逻辑可以
  /// 避免菜单显示期间浏览器菜单被提前恢复。
  static Future<T> keepDisabled<T>(Future<T> Function() action) async {
    _BrowserMenuSuppressor.acquire();
    try {
      return await action();
    } finally {
      _BrowserMenuSuppressor.release();
    }
  }

  @override
  State<BrowserContextMenuScope> createState() =>
      _BrowserContextMenuScopeState();
}

class _BrowserContextMenuScopeState extends State<BrowserContextMenuScope> {
  bool _hovering = false;
  bool _pressing = false;

  void _setHovering(bool value) {
    if (_hovering == value) return;
    _hovering = value;
    value ? _BrowserMenuSuppressor.acquire() : _BrowserMenuSuppressor.release();
  }

  /// 触摸设备没有 hover 事件，长按弹出菜单前需要在按下时就关闭浏览器菜单。
  void _setPressing(bool value) {
    if (_pressing == value) return;
    _pressing = value;
    value ? _BrowserMenuSuppressor.acquire() : _BrowserMenuSuppressor.release();
  }

  @override
  void dispose() {
    _setHovering(false);
    _setPressing(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return widget.child;
    return MouseRegion(
      onEnter: (_) => _setHovering(true),
      onExit: (_) => _setHovering(false),
      child: Listener(
        onPointerDown: (event) {
          if (event.kind != PointerDeviceKind.mouse) _setPressing(true);
        },
        onPointerUp: (event) {
          if (event.kind != PointerDeviceKind.mouse) _setPressing(false);
        },
        onPointerCancel: (event) {
          if (event.kind != PointerDeviceKind.mouse) _setPressing(false);
        },
        child: widget.child,
      ),
    );
  }
}

/// 以引用计数的方式开关浏览器右键菜单，避免多处同时使用时相互覆盖。
abstract final class _BrowserMenuSuppressor {
  static int _count = 0;

  static void acquire() {
    if (!kIsWeb) return;
    if (_count++ == 0) unawaited(BrowserContextMenu.disableContextMenu());
  }

  static void release() {
    if (!kIsWeb) return;
    if (--_count == 0) unawaited(BrowserContextMenu.enableContextMenu());
  }
}
