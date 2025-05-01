import 'package:flutter/material.dart';
import '../color.dart';

class CallsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColor.background,
      body: Center(
        child: Text(
          'Calls Screen',
          style: TextStyle(color: AppColor.text, fontSize: 24),
        ),
      ),
    );
  }
}
