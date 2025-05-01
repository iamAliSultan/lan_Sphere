

import 'package:flutter/material.dart';
import 'screens/splash_screen.dart'; // Import the splash screen

void main() {
  runApp(LANsphereApp());
}

class LANsphereApp extends StatelessWidget {
  const LANsphereApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false, // Remove debug banner
      title: 'LANsphere',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: SplashScreen(), // Set the splash screen as the home screen
    );
  }
}