import 'package:flutter/material.dart';

class CustomPopupMenuOption<T> {
  final T value;
  final String title;
  final IconData? icon;

  CustomPopupMenuOption({required this.value, required this.title, this.icon});
}

class CustomPopupMenuButton<T> extends StatelessWidget {
  final List<CustomPopupMenuOption<T>> options;
  final ValueChanged<T> onSelected;
  final Widget child;
  final Color backgroundColor;
  final Color textColor;

  const CustomPopupMenuButton({
    super.key,
    required this.options,
    required this.onSelected,
    required this.child,
    this.backgroundColor = Colors.white,
    this.textColor = Colors.black87,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      icon: child,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: backgroundColor,
      elevation: 6,
      offset: const Offset(0, 40),
      onSelected: onSelected,
      itemBuilder: (context) => options
          .map(
            (option) => PopupMenuItem<T>(
              value: option.value,
              child: Row(
                children: [
                  if (option.icon != null) ...[
                    Icon(option.icon, size: 18, color: textColor),
                    const SizedBox(width: 8),
                  ],
                  Text(option.title, style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}
