import 'dart:math';

import 'package:flutter/material.dart';

import '../design/app_theme.dart';

String createOperationId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

String formatMoney(String raw) {
  final match = RegExp(r'^(-?\d+)(?:\.(\d{1,2}))?$').firstMatch(raw.trim());
  if (match == null) return '$raw MT';
  return '${match.group(1)}.${(match.group(2) ?? '').padRight(2, '0')} MT';
}

String formatQuantity(num value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2);

/// Devolve só os dígitos do número, sem o indicativo de Moçambique (258).
String? normalizePhone(String? raw) {
  if (raw == null) return null;
  var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;
  if (digits.startsWith('00258') && digits.length >= 13) {
    digits = digits.substring(5);
  } else if (digits.startsWith('258') && digits.length >= 11) {
    digits = digits.substring(3);
  }
  return digits;
}

/// Must match the backend's V12 comparison policy, without inferring identity.
String? customerPhoneKey(String? raw) {
  if (raw == null || raw.length > 40) return null;
  final value = raw.trim();
  if (!RegExp(r'^\+?[0-9 ()-]+$').hasMatch(value)) return null;
  final compact = value.replaceAll(RegExp(r'[ ()-]'), '');
  String digits;
  if (compact.startsWith('+')) {
    digits = compact.substring(1);
  } else if (compact.startsWith('00')) {
    digits = compact.substring(2);
  } else if (compact.startsWith('258') &&
      (compact.length == 11 || compact.length == 12)) {
    digits = compact;
  } else if (compact.length == 8 || compact.length == 9) {
    digits = '258$compact';
  } else {
    return null;
  }
  if (!RegExp(r'^[1-9][0-9]{7,14}$').hasMatch(digits) ||
      (digits.startsWith('258') &&
          digits.length != 11 &&
          digits.length != 12)) {
    return null;
  }
  return '+$digits';
}

class StateMessage extends StatelessWidget {
  const StateMessage({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.large),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: theme.colorScheme.outline),
          const SizedBox(height: AppSpacing.medium),
          Text(message, textAlign: TextAlign.center),
          if (actionLabel != null) ...[
            const SizedBox(height: AppSpacing.small),
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
  });
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.medium,
      AppSpacing.medium,
      AppSpacing.medium,
      AppSpacing.small,
    ),
    child: TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    ),
  );
}
