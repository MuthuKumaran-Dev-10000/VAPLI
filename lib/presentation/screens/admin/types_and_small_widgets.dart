import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'create_tank_screen_helpers.dart';
// ─────────────────────────────────────────────────────────────────────────────
// TypeMeta
// ─────────────────────────────────────────────────────────────────────────────

class TypeMeta {
  final String value, label;
  final IconData icon;
  const TypeMeta(this.value, this.label, this.icon);
}

// ─────────────────────────────────────────────────────────────────────────────
// Btn  — compact icon + label button used in TankCardActions
// ─────────────────────────────────────────────────────────────────────────────

class Btn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const Btn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        ),
      );
}
