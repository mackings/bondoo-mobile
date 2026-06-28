import 'package:flutter/material.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';

enum ApiFeedbackType { success, error, info }

Future<void> showApiFeedback(
  BuildContext context, {
  required String title,
  required String message,
  ApiFeedbackType type = ApiFeedbackType.info,
  String actionLabel = 'Done',
}) {
  final color = switch (type) {
    ApiFeedbackType.success => AppTheme.success,
    ApiFeedbackType.error => AppTheme.danger,
    ApiFeedbackType.info => AppTheme.primaryBright,
  };
  final icon = switch (type) {
    ApiFeedbackType.success => Icons.check_rounded,
    ApiFeedbackType.error => Icons.close_rounded,
    ApiFeedbackType.info => Icons.info_outline_rounded,
  };

  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(24, 26, 24, 14),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.13),
              border: Border.all(color: color.withValues(alpha: 0.28)),
            ),
            child: Icon(icon, color: color, size: 30),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(dialogContext).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.muted, height: 1.45),
          ),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            style: FilledButton.styleFrom(backgroundColor: color),
            child: Text(actionLabel),
          ),
        ],
      ),
    ),
  );
}

Future<void> showApiError(
  BuildContext context,
  Object error, {
  String title = 'Request failed',
}) {
  return showApiFeedback(
    context,
    title: title,
    message: apiErrorMessage(error),
    type: ApiFeedbackType.error,
    actionLabel: 'Try again',
  );
}

Future<void> showApiSuccess(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return showApiFeedback(
    context,
    title: title,
    message: message,
    type: ApiFeedbackType.success,
  );
}
