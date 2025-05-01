import 'package:flutter/material.dart';

class IncomingCallScreen extends StatelessWidget {
  final String callerIp; // IP or identifier for the caller
  final Function acceptCall;
  final Function rejectCall;

  IncomingCallScreen({
    required this.callerIp,
    required this.acceptCall,
    required this.rejectCall,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Incoming Call')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Incoming call from: $callerIp',
              style: TextStyle(fontSize: 20),
            ),
            SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: Icon(Icons.call),
                  onPressed: () => acceptCall(),
                  iconSize: 50,
                  color: Colors.green,
                ),
                SizedBox(width: 20),
                IconButton(
                  icon: Icon(Icons.call_end),
                  onPressed: () => rejectCall(),
                  iconSize: 50,
                  color: Colors.red,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}