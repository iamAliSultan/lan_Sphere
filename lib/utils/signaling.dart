import 'dart:convert';
import 'dart:io';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class Signaling {
  final String targetIp;
  final bool isCaller;
  final String callType; // audio/video call type
  final Function(MediaStream remoteStream)? onAddRemoteStream;
  final Function? onIncomingCall; // Callback for incoming calls

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  RawDatagramSocket? _udpSocket;

  final int signalingPort = 5000;

  Signaling({
    required this.targetIp,
    required this.isCaller,
    required this.callType,
    this.onAddRemoteStream,
    this.onIncomingCall,
  });

  Future<void> initLocalMedia({
    required RTCVideoRenderer localRenderer,
    required String callType,
  }) async {
    // Initialize local media stream (audio and/or video based on call type)
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': callType == 'video', // Only enable video for video calls
    });

    localRenderer.srcObject = _localStream;

    // Initialize UDP socket and peer connection
    await _initUdpSocket();
    await _createPeerConnection();

    // Start call if this device is the caller
    if (isCaller) {
      makeCall();
    }
  }

  Future<void> _initUdpSocket() async {
    // Bind UDP socket for signaling communication
    _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, signalingPort);
    _udpSocket!.listen((event) async {
      if (event == RawSocketEvent.read) {
        final datagram = _udpSocket!.receive();
        if (datagram == null) return;

        final data = utf8.decode(datagram.data);
        final message = jsonDecode(data);

        // Handle incoming messages based on their type
        if (message['type'] == 'offer' && !isCaller) {
          // Receiver of the call (this device)
          onIncomingCall?.call(message['fromIp']); // Show incoming call screen
          await _peerConnection!.setRemoteDescription(
            RTCSessionDescription(message['sdp'], message['type']),
          );
        } else if (message['type'] == 'answer' && isCaller) {
          // Caller receives an answer from receiver
          await _peerConnection!.setRemoteDescription(
            RTCSessionDescription(message['sdp'], message['type']),
          );
        } else if (message['type'] == 'candidate') {
          // Handle ICE candidate messages
          await _peerConnection!.addCandidate(
            RTCIceCandidate(
              message['candidate'],
              message['sdpMid'],
              message['sdpMLineIndex'],
            ),
          );
        }
      }
    });
  }

  Future<void> _createPeerConnection() async {
    // Configure ICE servers for peer connection
    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'}, // Google STUN server
      ],
    };

    // Create peer connection for WebRTC communication
    _peerConnection = await createPeerConnection(config);

    // ICE candidate handling
    _peerConnection!.onIceCandidate = (candidate) {
      _sendMessage({
        'type': 'candidate',
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    // Handle remote media stream when added
    _peerConnection!.onAddStream = (stream) {
      onAddRemoteStream?.call(stream);
    };

    // Add local stream (audio/video) to peer connection
    await _peerConnection!.addStream(_localStream!);
  }

  // Initiates the call by creating an offer and sending it
  void makeCall() async {
    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    _sendMessage(offer);
  }

  // Send signaling message over UDP
  void _sendMessage(dynamic data) {
    final message = <String, dynamic>{
      'type': data['type'],
      'sdp': data['sdp'],
      'candidate': data['candidate'],
      'sdpMid': data['sdpMid'],
      'sdpMLineIndex': data['sdpMLineIndex'],
    }..removeWhere((key, value) => value == null); // Remove null values

    // Send the message over UDP socket to the target IP
    _udpSocket!.send(
      utf8.encode(jsonEncode(message)),
      InternetAddress(targetIp),
      signalingPort,
    );
  }

  // Ends the call and cleans up resources
  void hangUp() {
    _localStream?.dispose();
    _peerConnection?.close();
    _udpSocket?.close();
  }

  // Dispose of resources when signaling object is no longer needed
  void dispose() {
    hangUp();
  }
}
