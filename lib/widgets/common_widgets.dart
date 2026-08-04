import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../data/models/billing_item_model.dart';

/// Shared Yes/No confirmation dialog. Returns true only if the user
/// tapped the confirm action; back-press/tap-outside/"No" all resolve
/// to false.
Future<bool> confirmDialog({
  required String title,
  required String message,
  String confirmText = 'Yes',
  String cancelText = 'No',
  bool danger = false,
}) async {
  final result = await Get.dialog<bool>(
    AlertDialog(
      backgroundColor: AppColors.surfaceElevated,
      title: Text(title, style: AppTextStyles.h3),
      content: Text(message, style: AppTextStyles.body),
      actions: [
        TextButton(
          onPressed: () => Get.back(result: false),
          child: Text(cancelText),
        ),
        TextButton(
          onPressed: () => Get.back(result: true),
          child: Text(
            confirmText,
            style: danger ? TextStyle(color: AppColors.danger) : null,
          ),
        ),
      ],
    ),
  );
  return result == true;
}

class StatusBadge extends StatelessWidget {
  final DocStatus status;
  const StatusBadge({super.key, required this.status});

  Color get _color {
    switch (status) {
      case DocStatus.draft:
        return AppColors.textMuted;
      case DocStatus.sent:
        return AppColors.skyBlue;
      case DocStatus.approved:
        return AppColors.success;
      case DocStatus.rejected:
        return AppColors.danger;
      case DocStatus.expired:
        return AppColors.ember;
      case DocStatus.converted:
        return AppColors.gold;
      case DocStatus.active:
        return AppColors.success;
      case DocStatus.cancelled:
        return AppColors.danger;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _color.withOpacity(0.4)),
      ),
      child: Text(
        status.label,
        style: AppTextStyles.caption.copyWith(
          color: _color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class SearchField extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  const SearchField({super.key, required this.hint, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      style: AppTextStyles.body.copyWith(color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(Icons.search_rounded,
            color: AppColors.textMuted, size: 20),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            Text(title, style: AppTextStyles.h3),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppTextStyles.caption,
            ),
          ],
        ),
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionLabel({super.key, required this.text, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(text, style: AppTextStyles.h3),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Small colored dot + label used for legends and filter chips.
class FilterChipToggle extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const FilterChipToggle({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          gradient: selected ? AppColors.goldGradient : null,
          color: selected ? null : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? Colors.transparent : AppColors.divider,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: selected ? AppColors.textOnGold : AppColors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// Row-action icon for "share this document straight to the party's
/// WhatsApp chat" — used on the Quotation, Estimation, and Receipt list
/// cards next to the existing Print/Download/Share icons. Drawn as an
/// inline SVG (rather than `Icons.share`) so it reads as WhatsApp
/// specifically, in WhatsApp's own brand green, at a glance.
class WhatsAppIconButton extends StatelessWidget {
  final VoidCallback onPressed;
  final double size;

  /// WhatsApp's brand green — intentionally not pulled from
  /// [AppColors], since this needs to read as "WhatsApp" at a glance
  /// regardless of the app's light/dark palette.
  static const brandGreen = Color(0xFF25D366);

  const WhatsAppIconButton({
    super.key,
    required this.onPressed,
    this.size = 18,
  });

  // Simplified WhatsApp glyph (circular chat bubble + handset), good
  // enough at the small sizes used in these action rows.
  static const _glyph = '''
<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
  <path fill="currentColor" d="M12.04 2C6.58 2 2.13 6.45 2.13 11.91c0 1.75.46 3.45 1.32 4.95L2.05 22l5.29-1.39a9.9 9.9 0 0 0 4.7 1.2h.01c5.46 0 9.9-4.45 9.9-9.9C21.95 6.45 17.5 2 12.04 2Zm0 18.02h-.01a8.1 8.1 0 0 1-4.13-1.13l-.3-.18-3.14.82.84-3.06-.19-.31a8.11 8.11 0 0 1-1.24-4.31c0-4.49 3.66-8.14 8.15-8.14 2.18 0 4.22.85 5.76 2.39a8.1 8.1 0 0 1 2.38 5.76c0 4.49-3.65 8.16-8.12 8.16Zm4.47-6.1c-.24-.12-1.44-.71-1.67-.79-.22-.08-.39-.12-.55.12-.16.24-.63.79-.78.95-.14.16-.29.18-.53.06-.24-.12-1.02-.38-1.94-1.2-.72-.64-1.2-1.43-1.35-1.67-.14-.24-.02-.37.11-.49.11-.11.24-.29.36-.43.12-.14.16-.24.24-.4.08-.16.04-.3-.02-.42-.06-.12-.55-1.32-.75-1.8-.2-.48-.4-.42-.55-.42h-.47c-.16 0-.42.06-.64.3-.22.24-.84.82-.84 2s.86 2.32.98 2.48c.12.16 1.7 2.6 4.13 3.64.58.25 1.03.4 1.38.51.58.18 1.11.16 1.53.1.47-.07 1.44-.59 1.64-1.15.2-.57.2-1.05.14-1.15-.06-.1-.22-.16-.46-.28Z"/>
</svg>
''';

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Share on WhatsApp',
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
      icon: SvgPicture.string(
        _glyph,
        width: size,
        height: size,
        colorFilter: const ColorFilter.mode(brandGreen, BlendMode.srcIn),
      ),
    );
  }
}