import 'package:flutter/material.dart';
import 'package:lenali/screens/splash_screen.dart';
import 'package:lenali/screens/login_signup_screen.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final chatManager = ChatManager(); // Initialize ChatManager
  await chatManager.initialize();

  // Start the background service and set up lifecycle management
  runApp(LANsphereApp(chatManager: chatManager));
}

class LANsphereApp extends StatefulWidget {
  final ChatManager chatManager;

  const LANsphereApp({super.key, required this.chatManager});

  @override
  _LANsphereAppState createState() => _LANsphereAppState();
}

class _LANsphereAppState extends State<LANsphereApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // Observe app lifecycle
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      // Restart or reinitialize background service when app is paused or closed
      widget.chatManager.backgroundService.invoke('restart');
    } else if (state == AppLifecycleState.resumed) {
      // Re-sync state or reload data when app resumes (optional)
      widget.chatManager.initialize(); // Reinitialize if needed
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // Clean up observer
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
      ),
      initialRoute: '/splash',
      routes: {
        '/splash': (context) => const SplashScreen(),
      
        // Add other routes as needed (e.g., home screen after login)
      },
    );
  }
}