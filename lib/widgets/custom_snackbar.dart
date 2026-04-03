import 'package:flutter/material.dart';

class CustomSnackbar {
  static OverlayEntry? _currentEntry;

  static void show(
    BuildContext context,
    String message, {
    Color backgroundColor = Colors.black87,
    Duration duration = const Duration(milliseconds: 2200),
    IconData? icon,
  }) {
    _currentEntry?.remove();

    final overlay = Overlay.of(context);
    if (overlay == null) return;

    _currentEntry = OverlayEntry(
      builder: (context) {
        return _AnimatedSnackbar(
          text: message,
          backgroundColor: backgroundColor,
          icon: icon,
        );
      },
    );

    overlay.insert(_currentEntry!);

    Future.delayed(duration + const Duration(milliseconds: 300), () {
      _currentEntry?.remove();
      _currentEntry = null;
    });
  }
}

class _AnimatedSnackbar extends StatefulWidget {
  final String text;
  final Color backgroundColor;
  final IconData? icon;

  const _AnimatedSnackbar({
    Key? key,
    required this.text,
    required this.backgroundColor,
    this.icon,
  }) : super(key: key);

  @override
  State<_AnimatedSnackbar> createState() => _AnimatedSnackbarState();
}

class _AnimatedSnackbarState extends State<_AnimatedSnackbar> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
    _slide = Tween<Offset>(begin: const Offset(0, 1), end: const Offset(0, 0)).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fade = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return Positioned(
      bottom: mediaQuery.viewInsets.bottom + 20,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: Material(
            color: widget.backgroundColor,
            borderRadius: BorderRadius.circular(12),
            elevation: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      widget.text,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
