import 'package:flutter/material.dart';
import 'login_signup_screen.dart'; // Import LoginSignupScreen
import '../color.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeIn,
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
      ),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:  AppColor.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background image (moved slightly downward)
          Positioned(
            top: 120, // Adjusted to move image slightly down
            left: 0,
            right: 0,
            child: Image.asset(
              'assets/started.png', // Replace with your image path
              fit: BoxFit.contain,
            ),
          ),
          // Main content
          Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // "Connect with your friends" (moved slightly upward)
              FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: const Padding(
                    padding: EdgeInsets.only(bottom: 10), // Adjusted to move text up
                    child: Text(
                      'Connect with your friends!!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        color: AppColor.headertext,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              // Subtitle text (newly added)
              FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 30),
                    child: Text(
                      'Chat mobile app with video and audio calling option, stay connected with friends.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: AppColor.text,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20), // Space before button
              
              // Move the arrow button to the right
              FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Align(
                    alignment: Alignment.centerRight, // Move button to the right
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 50, right: 40), // Adjust position
                      child: CircleAvatar(
                        radius: 30,
                        backgroundColor: AppColor.button,
                        child: IconButton(
                          icon: const Icon(Icons.arrow_forward, color: AppColor.text, size: 30),
                          onPressed: () {
                            // Navigate to Login Screen
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(builder: (context) => const LoginSignupScreen()),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
