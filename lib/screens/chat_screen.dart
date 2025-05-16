import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:video_player/video_player.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_file/open_file.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../color.dart';
import 'new_chat_screen.dart';
import 'login_signup_screen.dart';

class ChatScreen extends StatefulWidget {
  final LanContact contact;

  const ChatScreen({required this.contact});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final List<Map<String, dynamic>> messages = [];
  String? localIp;
  String? myName;
  File? _selectedImage;
  File? _selectedVideo;
  File? _selectedFile;
  FlutterSoundRecorder? _recorder;
  bool _isRecording = false;
  bool _isPaused = false;
  String? _recordingPath;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isMicPressed = false;
  final Map<String, VideoPlayerController> _videoControllers = {};
  final ImagePicker _picker = ImagePicker();
  bool _isInCall = false; // Local call state
  String _callStatus = 'Connecting...'; // Call status for UI
  final ChatManager _chatManager = ChatManager(); // Single instance of ChatManager
  RTCVideoRenderer _localRenderer = RTCVideoRenderer(); // Local video renderer
  RTCVideoRenderer _remoteRenderer = RTCVideoRenderer(); // Remote video renderer
  bool _isMuted = false; // Track microphone mute state
  bool _isVideoOn = true; // Track video on/off state

  @override
  void initState() {
    super.initState();
    _getLocalIp();
    _loadMessages();
    _initRecorder();
    _messageController.addListener(() => setState(() {}));
    _initializeRenderers();

    // Initialize ChatManager and set callbacks
    _chatManager.initialize().then((_) {
      _chatManager.setOnNewMessageCallback((message, senderIp) {
        if (senderIp != widget.contact.ip) return;
        if (message['type'] == 'image' || message['type'] == 'video' || message['type'] == 'voice' || message['type'] == 'file') {
          _saveAndDisplayMedia(message['sender'], File(message['path']), message['type'], message['timestamp']);
        } else {
          setState(() {
            messages.add(message);
          });
          _saveMessages();
        }
      });
      _chatManager.setOnCallEventCallback((event, senderIp, {String? sdpJson, bool? isVideo, Map<String, dynamic>? candidateMap}) async {
        if (senderIp != widget.contact.ip) return;
        switch (event) {
          case 'call_offer':
            if (sdpJson != null && isVideo != null) {
              setState(() => _callStatus = 'Ringing');
              _handleCallOffer(sdpJson, isVideo, senderIp);
            }
            break;
          case 'call_answer':
            setState(() {
              _isInCall = true;
              _callStatus = 'Connected';
            });
            break;
          case 'call_end':
            _terminateCall();
            break;
        }
      });

      // Load queued messages when screen initializes
      _chatManager.loadQueuedMessages(widget.contact.ip).then((queuedMessages) {
        setState(() {
          messages.addAll(queuedMessages);
        });
        _saveMessages();
      });
    });
  }

  Future<void> _initializeRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    _chatManager.localRenderer = _localRenderer;
    _chatManager.remoteRenderer = _remoteRenderer;
  }

  Future<void> _initRecorder() async {
    _recorder = FlutterSoundRecorder();
    await _requestPermissions();
    await _recorder!.openRecorder();
  }

  Future<void> _requestPermissions() async {
    final statuses = await [
      Permission.microphone,
      Permission.storage,
      Permission.camera,
      Permission.notification,
      if (Platform.isAndroid && (await _getAndroidVersion()) >= 13) Permission.audio,
    ].request();
    if (!statuses[Permission.microphone]!.isGranted) print('Microphone permission denied');
    if (!statuses[Permission.camera]!.isGranted) print('Camera permission denied');
    if (!statuses[Permission.notification]!.isGranted) print('Notification permission denied');
    if (statuses.containsKey(Permission.storage) && !statuses[Permission.storage]!.isGranted) print('Storage permission denied');
    if (statuses.containsKey(Permission.audio) && !statuses[Permission.audio]!.isGranted) print('Audio permission denied');
  }

  Future<int> _getAndroidVersion() async => Platform.isAndroid ? 13 : 0;

  Future<void> _getLocalIp() async {
    final interfaces = await NetworkInterface.list();
    for (var interface in interfaces) {
      for (var addr in interface.addresses) {
        if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
          setState(() {
            localIp = addr.address;
            myName = localIp;
          });
          return;
        }
      }
    }
  }

  void _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty && _selectedImage == null && _selectedVideo == null && _selectedFile == null) return;

    if (message.isNotEmpty) {
      _chatManager.sendMessage(widget.contact.ip, message);
    }
    if (_selectedImage != null) await _chatManager.sendImage(widget.contact.ip, _selectedImage!);
    if (_selectedVideo != null) await _chatManager.sendVideo(widget.contact.ip, _selectedVideo!);
    if (_selectedFile != null) await _chatManager.sendFile(widget.contact.ip, _selectedFile!);

    setState(() {
      _messageController.clear();
      _selectedImage = null;
      _selectedVideo = null;
      _selectedFile = null;
    });
    await _saveMessages();
  }

  Future<void> _handleFileSelection() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.isNotEmpty && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      if (await file.exists()) setState(() => _selectedFile = file);
    }
  }

  Future<void> _handleCameraCapture(bool isVideo) async {
    XFile? file;
    if (isVideo) {
      file = await _picker.pickVideo(source: ImageSource.camera);
    } else {
      file = await _picker.pickImage(source: ImageSource.camera);
    }
    if (file != null) {
      final mediaFile = File(file.path);
      if (await mediaFile.exists()) {
        setState(() {
          if (isVideo) {
            _selectedVideo = mediaFile;
            final controller = VideoPlayerController.file(mediaFile);
            _videoControllers[mediaFile.path] = controller;
            controller.initialize().then((_) => setState(() {}));
          } else {
            _selectedImage = mediaFile;
          }
        });
      }
    }
  }

  Future<void> _startRecordingVoiceNote() async {
    final directory = await getApplicationDocumentsDirectory();
    _recordingPath = '${directory.path}/voice${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder!.startRecorder(toFile: _recordingPath!, codec: Codec.aacMP4);
    setState(() {
      _isRecording = true;
      _isPaused = false;
    });
  }

  Future<void> _pauseRecordingVoiceNote() async {
    await _recorder!.pauseRecorder();
    setState(() => _isPaused = true);
  }

  Future<void> _resumeRecordingVoiceNote() async {
    await _recorder!.resumeRecorder();
    setState(() => _isPaused = false);
  }

  Future<void> _stopRecordingVoiceNote({bool send = true}) async {
    final path = await _recorder!.stopRecorder();
    setState(() {
      _isRecording = false;
      _isPaused = false;
      _isMicPressed = false;
    });
    if (path != null && send) {
      final voiceNote = File(path);
      if (await voiceNote.exists()) await _chatManager.sendVoiceNote(widget.contact.ip, voiceNote);
    } else if (!send && _recordingPath != null) {
      final file = File(_recordingPath!);
      if (await file.exists()) await file.delete();
    }
    _recordingPath = null;
  }

  Future<void> _saveMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'chat_${widget.contact.ip.replaceAll('.', '_')}';
    final encoded = messages.map((m) {
      if (m['type'] == 'image' || m['type'] == 'video' || m['type'] == 'file' || m['type'] == 'voice') {
        return "${m['sender']}|${m['type']}|${m['path']}|${m['timestamp']}";
      }
      return "${m['sender']}|text|${m['message']}|${m['timestamp']}";
    }).toList();
    await prefs.setStringList(key, encoded);
  }

  Future<void> _loadMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'chat_${widget.contact.ip.replaceAll('.', '_')}';
    final encoded = prefs.getStringList(key) ?? [];
    final loaded = encoded.map((e) {
      final parts = e.split('|');
      if (parts.length >= 4 && (parts[1] == 'image' || parts[1] == 'video' || parts[1] == 'file' || parts[1] == 'voice')) {
        return {"sender": parts[0], "type": parts[1], "path": parts[2], "timestamp": parts[3]};
      }
      return {"sender": parts[0], "type": "text", "message": parts[2], "timestamp": parts[3]};
    }).toList();
    setState(() {
      messages.addAll(loaded);
    });
    for (var msg in loaded.where((m) => m['type'] == 'video' && m['path'] != null)) {
      final file = File(msg['path'] ?? '');
      if (await file.exists()) {
        final controller = VideoPlayerController.file(file);
        _videoControllers[msg['path']!] = controller;
        await controller.initialize();
        controller.setLooping(false);
      }
    }
  }

  Future<void> _saveAndDisplayMedia(String sender, File file, String type, String timestamp) async {
    setState(() {
      messages.add({"sender": sender, "type": type, "path": file.path, "timestamp": timestamp});
      if (type == 'video') {
        final controller = VideoPlayerController.file(file);
        _videoControllers[file.path] = controller;
        controller.initialize().then((_) => setState(() {}));
      }
    });
    await _saveMessages();
  }

  Future<void> _startCall(bool isVideo) async {
    setState(() {
      _callStatus = 'Connecting...';
      _isInCall = true;
      _isMuted = false; // Reset mute state
      _isVideoOn = isVideo; // Set video state based on call type
    });
    await _chatManager.startCall(widget.contact.ip, isVideo);
    if (_chatManager.callStatus == 'Connected') {
      setState(() => _callStatus = 'Connected');
    }
  }

  Future<void> _handleCallOffer(String sdpJson, bool isVideo, String senderIp) async {
    _chatManager.showNotification(
      contactName: widget.contact.name,
      message: 'Incoming ${isVideo ? "video" : "voice"} call',
      senderIp: senderIp,
      isCall: true,
      isVideoCall: isVideo,
      sdpJson: sdpJson,
    );
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Incoming Call', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.phone, size: 50, color: Colors.blue),
            const SizedBox(height: 10),
            Text('From ${widget.contact.name}', style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildCallButton(Icons.call_end, Colors.red, 'Reject', () {
                  Navigator.pop(context);
                  _endCall();
                }),
                const SizedBox(width: 20),
                _buildCallButton(Icons.phone_callback, Colors.green, 'Accept', () async {
                  Navigator.pop(context);
                  setState(() {
                    _isInCall = true;
                    _callStatus = 'Connected';
                    _isMuted = false; // Reset mute state
                    _isVideoOn = isVideo; // Set video state
                  });
                  await _chatManager.answerCall(widget.contact.ip, sdpJson, isVideo);
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCallButton(IconData icon, Color color, String label, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        shape: const CircleBorder(),
        padding: const EdgeInsets.all(15),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 30, color: Colors.white),
          const SizedBox(height: 5),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }

  Future<void> _endCall() async {
    await _chatManager.endCall();
    _terminateCall();
  }

  void _terminateCall() {
    setState(() {
      _isInCall = false;
      _callStatus = 'Call Ended';
      _isMuted = false; // Reset mute state
      _isVideoOn = true; // Reset video state
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _callStatus = 'Connecting...'; // Reset for next call
          });
        }
      });
    });
  }

  String _truncateFileName(String filePath, {int maxLength = 20}) {
    final fileName = filePath.split('/').last;
    return fileName.length <= maxLength ? fileName : '${fileName.substring(0, maxLength)}...';
  }

  String _formatTimestamp(String timestamp) {
    final dateTime = DateTime.parse(timestamp);
    return '${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _clearChat() async {
    final prefs = await SharedPreferences.getInstance();
    final chatKey = 'chat_${widget.contact.ip.replaceAll('.', '_')}';
    final backgroundMessagesKey = 'background_messages_${widget.contact.ip.replaceAll('.', '_')}';
    final backgroundCallsKey = 'background_calls_${widget.contact.ip.replaceAll('.', '_')}';
    await prefs.remove(chatKey);
    await prefs.remove(backgroundMessagesKey);
    await prefs.remove(backgroundCallsKey);
    setState(() {
      messages.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Chat with ${widget.contact.name} cleared")),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _recorder?.closeRecorder();
    _audioPlayer.dispose();
    _videoControllers.values.forEach((controller) => controller.dispose());
    _videoControllers.clear();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColor.background,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColor.appbar, AppColor.headertext, AppColor.button],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: AppBar(
            title: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundImage: widget.contact.profilePic != null
                      ? FileImage(File(widget.contact.profilePic!))
                      : null,
                  child: widget.contact.profilePic == null
                      ? const Icon(Icons.person, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 10),
                Text(
                  widget.contact.name,
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                ),
              ],
            ),
            backgroundColor: Colors.transparent,
            elevation: 0,
            actions: [
              IconButton(
                icon: const Icon(Icons.wifi, color: Colors.green),
                onPressed: () {},
              ),
              IconButton(
                icon: const Icon(Icons.videocam, color: AppColor.selectedicon),
                onPressed: _isInCall ? null : () => _startCall(true),
              ),
              IconButton(
                icon: const Icon(Icons.call, color: AppColor.selectedicon),
                onPressed: _isInCall ? null : () => _startCall(false),
              ),
              PopupMenuButton<String>(
                color: Colors.black.withOpacity(0.6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.white.withOpacity(0.2)),
                ),
                onSelected: (value) async {
                  if (value == 'clear_chat') {
                    await _clearChat();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'clear_chat',
                    child: Text("Clear Chat", style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
          if (_isInCall)
            Container(
              color: Colors.black87,
              child: Column(
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        if (_chatManager.isVideoCall)
                          // Remote video (larger view)
                          Center(
                            child: SizedBox(
                              width: MediaQuery.of(context).size.width,
                              height: MediaQuery.of(context).size.height * 0.7,
                              child: RTCVideoView(_remoteRenderer, mirror: true),
                            ),
                          )
                        else
                          Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.mic, size: 100, color: Colors.white70),
                                const SizedBox(height: 10),
                                Text(_callStatus, style: const TextStyle(color: Colors.white, fontSize: 20)),
                              ],
                            ),
                          ),
                        // Local video (picture-in-picture)
                        if (_chatManager.isVideoCall)
                          Positioned(
                            top: 20,
                            right: 20,
                            child: Container(
                              width: 120,
                              height: 160,
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.white24),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: RTCVideoView(_localRenderer, mirror: true),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Call controls
                  Container(
                    padding: const EdgeInsets.all(10),
                    color: Colors.black54,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildCallControl(Icons.mic, _isMuted ? Colors.grey : Colors.white, 'Mute', () {
                          setState(() {
                            _isMuted = !_isMuted;
                            _chatManager.localStream?.getAudioTracks().forEach((track) {
                              track.enabled = !_isMuted;
                            });
                          });
                        }),
                        const SizedBox(width: 20),
                        _buildCallControl(_chatManager.isVideoCall ? (_isVideoOn ? Icons.videocam : Icons.videocam_off) : Icons.videocam_off,
                            _isVideoOn ? Colors.white : Colors.grey, 'Video', () {
                          if (_chatManager.isVideoCall) {
                            setState(() {
                              _isVideoOn = !_isVideoOn;
                              _chatManager.localStream?.getVideoTracks().forEach((track) {
                                track.enabled = _isVideoOn;
                              });
                            });
                          }
                        }),
                        const SizedBox(width: 20),
                        _buildCallControl(Icons.call_end, Colors.red, 'End', _endCall),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final isMe = msg['sender'] == myName;
                      return Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isMe ? AppColor.messageBubbleSent : AppColor.messageBubbleReceived,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(12),
                              topRight: const Radius.circular(12),
                              bottomLeft: isMe ? const Radius.circular(12) : const Radius.circular(0),
                              bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(12),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                            children: [
                              if (msg['type'] == 'image')
                                Image.file(
                                  File(msg['path']),
                                  width: 200,
                                  height: 200,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, color: AppColor.text),
                                )
                              else if (msg['type'] == 'voice')
                                TextButton(
                                  onPressed: () async {
                                    final file = File(msg['path']);
                                    if (await file.exists()) {
                                      await _audioPlayer.play(DeviceFileSource(msg['path']));
                                    }
                                  },
                                  child: Text("Play Voice Note", style: TextStyle(color: AppColor.text)),
                                )
                              else if (msg['type'] == 'video')
                                _videoControllers[msg['path']]?.value.isInitialized ?? false
                                    ? AspectRatio(
                                        aspectRatio: _videoControllers[msg['path']]!.value.aspectRatio,
                                        child: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            VideoPlayer(_videoControllers[msg['path']]!),
                                            IconButton(
                                              icon: Icon(
                                                _videoControllers[msg['path']]!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                                                color: AppColor.selectedicon,
                                                size: 50,
                                              ),
                                              onPressed: () {
                                                setState(() {
                                                  if (_videoControllers[msg['path']]!.value.isPlaying) {
                                                    _videoControllers[msg['path']]!.pause();
                                                  } else {
                                                    _videoControllers[msg['path']]!.play();
                                                  }
                                                });
                                              },
                                            ),
                                          ],
                                        ),
                                      )
                                    : const CircularProgressIndicator(color: AppColor.button)
                              else if (msg['type'] == 'file')
                                TextButton(
                                  onPressed: () async {
                                    final file = File(msg['path']);
                                    if (await file.exists()) {
                                      await OpenFile.open(msg['path']);
                                    }
                                  },
                                  child: Text("Open File: ${_truncateFileName(msg['path'])}", style: TextStyle(color: AppColor.text)),
                                )
                              else
                                Text(msg['message'], style: TextStyle(color: AppColor.text)),
                              const SizedBox(height: 4),
                              Text(_formatTimestamp(msg['timestamp']), style: TextStyle(color: AppColor.timestamp, fontSize: 10)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (_selectedImage != null)
                  _buildSelectedMedia(_selectedImage!, isImage: true)
                else if (_selectedVideo != null)
                  _buildSelectedMedia(_selectedVideo!, isVideo: true)
                else if (_selectedFile != null)
                  _buildSelectedMedia(_selectedFile!),
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColor.appbar, AppColor.headertext, AppColor.button],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: _isRecording
                      ? Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.cancel, color: Colors.red),
                              onPressed: () => _stopRecordingVoiceNote(send: false),
                            ),
                            IconButton(
                              icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause, color: AppColor.selectedicon),
                              onPressed: _isPaused ? _resumeRecordingVoiceNote : _pauseRecordingVoiceNote,
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.send, color: Colors.white),
                              onPressed: _stopRecordingVoiceNote,
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.attach_file, color: AppColor.selectedicon),
                              onPressed: _handleFileSelection,
                            ),
                            PopupMenuButton<String>(
                              color: Colors.black.withOpacity(0.6),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: Colors.white.withOpacity(0.2)),
                              ),
                              icon: const Icon(Icons.camera_alt, color: AppColor.selectedicon),
                              onSelected: (value) => _handleCameraCapture(value == 'video'),
                              itemBuilder: (context) => [
                                const PopupMenuItem(value: 'photo', child: Text('Take Photo', style: TextStyle(color: Colors.white))),
                                const PopupMenuItem(value: 'video', child: Text('Record Video', style: TextStyle(color: Colors.white))),
                              ],
                            ),
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColor.messageBubbleReceived,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: TextField(
                                  controller: _messageController,
                                  style: TextStyle(color: AppColor.text),
                                  decoration: InputDecoration(
                                    hintText: "Message...",
                                    hintStyle: TextStyle(color: AppColor.timestamp),
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                  ),
                                ),
                              ),
                            ),
                            _messageController.text.trim().isNotEmpty || _selectedImage != null || _selectedVideo != null || _selectedFile != null
                                ? IconButton(
                                    icon: const Icon(Icons.send, color: Colors.white),
                                    onPressed: _sendMessage,
                                  )
                                : GestureDetector(
                                    onLongPress: () {
                                      setState(() => _isMicPressed = true);
                                      _startRecordingVoiceNote();
                                    },
                                    onLongPressEnd: (_) {
                                      if (_isMicPressed && _isRecording) _stopRecordingVoiceNote();
                                      setState(() => _isMicPressed = false);
                                    },
                                    child: Icon(
                                      Icons.mic,
                                      color: _isMicPressed ? AppColor.button : AppColor.selectedicon,
                                      size: _isMicPressed ? 32 : 24,
                                    ),
                                  ),
                          ],
                        ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSelectedMedia(File file, {bool isImage = false, bool isVideo = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          if (isImage || isVideo)
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: isImage
                    ? Image.file(
                        file,
                        fit: BoxFit.cover,
                      )
                    : isVideo
                        ? (_videoControllers[file.path]?.value.isInitialized == true
                            ? FittedBox(
                                fit: BoxFit.cover,
                                child: SizedBox(
                                  width: _videoControllers[file.path]!.value.size.width,
                                  height: _videoControllers[file.path]!.value.size.height,
                                  child: VideoPlayer(_videoControllers[file.path]!),
                                ),
                              )
                            : const Center(child: CircularProgressIndicator()))
                        : null,
              ),
            )
          else
            Text("Selected: ${_truncateFileName(file.path)}", style: TextStyle(color: AppColor.text)),
          IconButton(
            icon: const Icon(Icons.close, color: AppColor.selectedicon),
            onPressed: () {
              setState(() {
                if (isVideo) _videoControllers.remove(file.path)?.dispose();
                _selectedImage = null;
                _selectedVideo = null;
                _selectedFile = null;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCallControl(IconData icon, Color color, String label, VoidCallback onPressed) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.8), // Slightly transparent for better visibility
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: Colors.black), // Ensure icon is visible
            const SizedBox(height: 5),
            Text(label, style: const TextStyle(color: Colors.black, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}