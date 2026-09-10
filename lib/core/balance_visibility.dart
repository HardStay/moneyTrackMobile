import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BalanceVisibility {
  static final hidden = ValueNotifier<bool>(false);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    hidden.value = prefs.getBool('hide_balance') ?? false;
  }

  static Future<void> toggle() async {
    hidden.value = !hidden.value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hide_balance', hidden.value);
  }
}
