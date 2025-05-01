import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../utils/signaling.dart';

class CallScreen extends StatefulWidget {
  final String targetIp;
  final bool isCaller;
  final String callType; // audio or video

  const CallScreen({
    required this.targetIp,
    required this.isCaller,
    required this.callType,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer(); // For remote stream
  Signaling? signaling;

  @override
  void initState() {
    super.initState();
    initRenderers();
    startCall();
  }

  Future<void> initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  void startCall() async {
    signaling = Signaling(
      targetIp: widget.targetIp,
      isCaller: widget.isCaller,
      callType: widget.callType,
      onAddRemoteStream: (stream) {
        // Assign the remote stream to the remote renderer
        _remoteRenderer.srcObject = stream;
      },
    );

    await signaling!.initLocalMedia(
      localRenderer: _localRenderer,
      callType: widget.callType, // Pass call type (audio/video)
    );

    if (widget.isCaller) {
      signaling!.makeCall();
    }
  }

  @override
  void dispose() {
    signaling?.dispose();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(widget.callType == 'audio' ? "Audio Call" : "Video Call")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Local stream (local video or audio)
            widget.callType == 'video'
                ? Container(
                    width: 100,
                    height: 150,
                    child: RTCVideoView(_localRenderer),
                  )
                : Text("Audio Call in Progress...", style: TextStyle(color: Colors.white)),
            SizedBox(height: 20),
            // Remote stream (remote video)
            widget.callType == 'video'
                ? Container(
                    width: 200,
                    height: 300,
                    child: RTCVideoView(_remoteRenderer),
                  )
                : Container(),
            SizedBox(height: 20),
            IconButton(
              icon: Icon(Icons.call_end, color: Colors.red, size: 50),
              onPressed: () {
                signaling?.hangUp();
                Navigator.pop(context);
              },
            )
          ],
        ),
      ),
    );
  }
}
