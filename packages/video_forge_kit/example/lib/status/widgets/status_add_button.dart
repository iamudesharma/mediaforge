import 'package:flutter/material.dart';

/// WhatsApp-style add-status control.
class StatusAddButton extends StatelessWidget {
  const StatusAddButton({
    super.key,
    required this.onTap,
    this.enabled = true,
    this.size = 64,
  });

  final VoidCallback? onTap;
  final bool enabled;
  final double size;

  static const Color whatsAppGreen = Color(0xFF25D366);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            customBorder: const CircleBorder(),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: enabled
                      ? whatsAppGreen
                      : Theme.of(context).disabledColor,
                  width: 2,
                ),
              ),
              child: Icon(
                Icons.add,
                color: enabled ? whatsAppGreen : Theme.of(context).disabledColor,
                size: size * 0.45,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Add status',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }
}
