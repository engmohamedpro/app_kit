import 'package:get/get.dart';

class AppSnack {
  AppSnack._();

  static void success(String message) {
    Get.snackbar(
      '',
      message,
      snackPosition: SnackPosition.TOP,
      backgroundColor: const Color(0xFF27AE60),
      colorText: const Color(0xFFFFFFFF),
      margin: const EdgeInsets.all(12),
      borderRadius: 8,
      duration: const Duration(seconds: 3),
      isDismissible: true,
      forwardAnimationCurve: Curves.easeOutBack,
    );
  }

  static void error(String message) {
    Get.snackbar(
      '',
      message,
      snackPosition: SnackPosition.TOP,
      backgroundColor: const Color(0xFFC0392B),
      colorText: const Color(0xFFFFFFFF),
      margin: const EdgeInsets.all(12),
      borderRadius: 8,
      duration: const Duration(seconds: 3),
      isDismissible: true,
      forwardAnimationCurve: Curves.easeOutBack,
    );
  }
}