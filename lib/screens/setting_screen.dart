import 'package:flutter/material.dart';
import '../color.dart';

class SettingScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColor.background,
      body: Center(
        child: Text(
          'Setting Secreen',
          style: TextStyle(color: AppColor.text, fontSize: 24),
        ),
      ),
    );
  }
}
