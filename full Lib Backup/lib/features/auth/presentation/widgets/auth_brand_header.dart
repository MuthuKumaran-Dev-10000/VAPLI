import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lubrication_indicator/core/constants/app_constants.dart';

class AuthBrandHeader extends StatelessWidget {
  const AuthBrandHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.secondary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.4),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(
            Icons.oil_barrel_rounded,
            color: Colors.white,
            size: 44,
          ),
        ),
        const SizedBox(height: 28),
        Text(
          'VAPLI',
          style: GoogleFonts.inter(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 26,
            letterSpacing: 3,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Industrial Lubrication Management',
          style: GoogleFonts.inter(
            color: AppColors.textSecondary,
            fontSize: 13,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

