import 'package:flutter/material.dart';
import '../models/session.dart';
import '../theme/app_theme.dart';

class LanguageSelector extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final String? label;
  final bool enabled;

  const LanguageSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!.toUpperCase(),
            style: const TextStyle(
              color: AppColors.surface400,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Container(
          decoration: BoxDecoration(
            color: AppColors.bg800,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.bg600),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: AppColors.bg800,
              borderRadius: BorderRadius.circular(12),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.bg500, size: 20),
              style: const TextStyle(color: AppColors.white, fontSize: 14),
              onChanged: enabled ? (v) => onChanged(v!) : null,
              items: kLanguageNames.entries.map((e) {
                final flag = kLanguageFlags[e.key] ?? '🌐';
                return DropdownMenuItem(
                  value: e.key,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Text(flag, style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 10),
                        Text(e.value, style: const TextStyle(color: AppColors.white, fontSize: 14)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${kLanguageFlags[value] ?? '🌐'} ${languageName(value)} selected',
          style: const TextStyle(color: AppColors.surface400, fontSize: 11),
        ),
      ],
    );
  }
}
