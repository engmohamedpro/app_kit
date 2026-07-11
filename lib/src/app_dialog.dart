import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AppDialog {
  AppDialog._();

  static Future<bool?> confirm({
    required String message,
    String? cancelText,
    String? confirmText,
    Color? confirmColor,
  }) {
    return Get.defaultDialog<bool>(
      title: '',
      content: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 16),
      ),
      textCancel: cancelText ?? 'Cancel',
      textConfirm: confirmText ?? 'Confirm',
      confirmTextColor: Colors.white,
      onConfirm: () => Get.back(result: true),
      onCancel: () => Get.back(result: false),
      buttonColor: confirmColor ?? const Color(0xFF2C3E50),
      radius: 12,
    );
  }

  static Future<void> alert({
    required String message,
    String? buttonText,
  }) {
    return Get.defaultDialog<void>(
      title: '',
      content: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 16),
      ),
      textConfirm: buttonText ?? 'OK',
      confirmTextColor: Colors.white,
      onConfirm: () => Get.back(),
      buttonColor: const Color(0xFF2C3E50),
      radius: 12,
      barrierDismissible: false,
    );
  }

  static Future<T?> custom<T>({
    required Widget content,
    bool barrierDismissible = true,
  }) {
    return Get.dialog<T>(
      content,
      barrierDismissible: barrierDismissible,
    );
  }

  static void dismiss() => Get.back();
}

class AppBottomSheet {
  AppBottomSheet._();

  static Future<T?> show<T>({
    required Widget child,
    bool isDismissible = true,
    bool enableDrag = true,
    Color? backgroundColor,
    ShapeBorder? shape,
  }) {
    return Get.bottomSheet<T>(
      child,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      backgroundColor: backgroundColor ?? Colors.white,
      shape: shape ??
          const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
    );
  }

  static void dismiss() => Get.back();
}