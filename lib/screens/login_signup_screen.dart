import 'package:flutter/material.dart';
import 'main_home_screen.dart';
import '../color.dart'; // Import App Colors

class LoginSignupScreen extends StatefulWidget {
  const LoginSignupScreen({super.key});

  @override
  _LoginSignupScreenState createState() => _LoginSignupScreenState();
}

class _LoginSignupScreenState extends State<LoginSignupScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColor.background,
      body: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly, // Even spacing
        crossAxisAlignment: CrossAxisAlignment.center, // Center align
        children: [
          const SizedBox(height: 100), // Moves "LanSphere" and "Login" further down
          
          // Centered App Title and Login Text
          const Column(
            children: [
              Text(
                'LanSphere',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: AppColor.headertext,
                ),
              ),
              SizedBox(height: 10), // Space between texts
              Text(
                "Login",
                style: TextStyle(
                  fontSize: 32,
                  color: AppColor.text,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          // Login/Signup Form
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, // Align labels to the left
              children: [
                // Username Label
                const Text(
                  "Username (Using your provided Email):",
                  style: TextStyle(
                    fontSize: 18,
                    color: AppColor.text,
                  ),
                ),
                const SizedBox(height: 5), // Small space
                TextField(
                  style: const TextStyle(color: AppColor.text), // White text input
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // Password Label
                const Text(
                  "Password:",
                  style: TextStyle(
                    fontSize: 18,
                    color: AppColor.text,
                  ),
                ),
                const SizedBox(height: 5), // Small space
                TextField(
                  style: const TextStyle(color: AppColor.text), // White text input
                  obscureText: true,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20), // Space before button

          // Centered Login Button
          Center(
            child: ElevatedButton(
              onPressed: () {
                // Navigate to MainHomeScreen after login
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => MainHomeScreen()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColor.button,
                padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
              ),
              child: const Text(
                'Login',
                style: TextStyle(fontSize: 18, color: AppColor.text),
              ),
            ),
          ),

        //  const SizedBox(height: 50), // Extra spacing at the bottom
        ],
      ),
    );
  }
}
