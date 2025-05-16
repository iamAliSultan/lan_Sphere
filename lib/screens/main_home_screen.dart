import 'package:flutter/material.dart';
import '../color.dart';
import 'calls_screen.dart';
import 'new_chat_screen.dart';
import 'chat_screen.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';
import 'login_signup_screen.dart';
// Assuming ChatManager is in a separate file

class MainHomeScreen extends StatefulWidget {
  @override
  _MainHomeScreenState createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  int _selectedIndex = 0;
  bool _isButtonClicked = false;
  bool _isSearching = false;
  TextEditingController _searchController = TextEditingController();
  List<LanContact> contacts = [];
  List<LanContact> filteredContacts = [];
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    filteredContacts = contacts;
    _searchController.addListener(() {
      filterContacts();
    });
    _loadContacts();
    // Initialize ChatManager
    ChatManager().initialize().then((_) {
      ChatManager().setOnNewMessageCallback((message, senderIp) {
        setState(() {
          final contactIndex = contacts.indexWhere((c) => c.ip == senderIp);
          if (contactIndex != -1) {
            contacts[contactIndex].lastMessage = message['message'] ?? 'New message';
            filteredContacts = List.from(contacts);
            _saveContacts();
            _updateLatestMessage(contactIndex); // Update the latest message
          }
        });
      });
    });
    // Start a timer to update contacts every second
    _updateTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      _loadContacts();
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel(); // Cancel the timer when the widget is disposed
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final contactListJson = prefs.getStringList('contacts') ?? [];
    setState(() {
      contacts = contactListJson
          .map((contactJson) => LanContact.fromMap(json.decode(contactJson)))
          .toList();
      filteredContacts = List.from(contacts);
      // Update lastMessage for each contact with the latest message
      for (int i = 0; i < contacts.length; i++) {
        _updateLatestMessage(i);
      }
      if (_isSearching) {
        filterContacts(); // Reapply search filter after loading
      }
    });
  }

  // Update the latest message for a contact based on chat history
  Future<void> _updateLatestMessage(int contactIndex) async {
    if (contactIndex >= 0 && contactIndex < contacts.length) {
      final prefs = await SharedPreferences.getInstance();
      final key = 'chat_${contacts[contactIndex].ip.replaceAll('.', '_')}';
      final encoded = prefs.getStringList(key) ?? [];
      if (encoded.isNotEmpty) {
        final latestMessageData = encoded.last.split('|');
        if (latestMessageData.length >= 4) {
          final messageType = latestMessageData[1];
          final messageContent = messageType == 'text' ? latestMessageData[2] : 'New $messageType';
          setState(() {
            contacts[contactIndex].lastMessage = messageContent;
            filteredContacts = List.from(contacts);
          });
        }
      } else {
        setState(() {
          contacts[contactIndex].lastMessage = 'No messages yet';
          filteredContacts = List.from(contacts);
        });
      }
    }
  }

  void filterContacts() {
    String query = _searchController.text.toLowerCase();
    setState(() {
      filteredContacts = contacts.where((contact) {
        return contact.name.toLowerCase().contains(query);
      }).toList();
    });
  }

  void toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        filteredContacts = List.from(contacts); // Reset filter when search is closed
      }
    });
  }

  void addContact(LanContact newContact) {
    setState(() {
      contacts.add(newContact);
      filteredContacts = List.from(contacts);
      if (_isSearching) {
        filterContacts(); // Reapply search filter after adding
      }
    });
    _saveContacts();
    // Establish TCP connection for the new contact
    ChatManager().getTcpClient(newContact.ip).then((client) {
      if (client == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to connect to ${newContact.ip}')),
        );
      }
    });
  }

  Future<void> _saveContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final contactListJson = contacts.map((contact) => json.encode(contact.toMap())).toList();
    await prefs.setStringList('contacts', contactListJson);
  }

  Future<String?> _copyImageToAppDir(String? imagePath) async {
    if (imagePath == null) return null;
    final directory = await getApplicationDocumentsDirectory();
    final profilePicsDir = Directory('${directory.path}/profile_pics');
    if (!await profilePicsDir.exists()) {
      await profilePicsDir.create();
    }
    final fileName = 'profile_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final newPath = '${profilePicsDir.path}/$fileName';
    await File(imagePath).copy(newPath);
    return newPath;
  }

  final List<Widget> _screens = [
    Container(),
    CallsScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColor.background,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Container(
          decoration: BoxDecoration(
            color: AppColor.background,
            border: Border(
              bottom: BorderSide(color: Colors.grey.withOpacity(0.4), width: 1),
            ),
          ),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: _isSearching
                ? TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: "Search contacts...",
                      border: InputBorder.none,
                      hintStyle: TextStyle(color: Colors.white54),
                    ),
                    style: TextStyle(color: Colors.white),
                    cursorColor: Colors.white,
                  )
                : const Text(
                    'LANSPHERE',
                    style: TextStyle(
                      color: AppColor.headertext,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
            centerTitle: false,
            actions: [
              IconButton(
                icon: Icon(
                  _isSearching ? Icons.close : Icons.search,
                  color: AppColor.text,
                ),
                onPressed: toggleSearch,
              ),
            ],
          ),
        ),
      ),
      body: _selectedIndex == 0
          ? ListView.builder(
              itemCount: filteredContacts.length,
              itemBuilder: (context, index) {
                final contact = filteredContacts[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.grey[800],
                    backgroundImage: contact.profilePic != null && File(contact.profilePic!).existsSync()
                        ? FileImage(File(contact.profilePic!))
                        : null,
                    child: contact.profilePic == null || !File(contact.profilePic!).existsSync()
                        ? const Icon(Icons.person, color: Colors.white)
                        : null,
                  ),
                  title: Text(
                    contact.name,
                    style: TextStyle(color: AppColor.text),
                  ),
                  subtitle: Text(
                    contact.lastMessage ?? 'No messages yet',
                    style: TextStyle(color: Colors.grey),
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ChatScreen(contact: contact),
                      ),
                    ).then((value) {
                      if (value != null && value is LanContact) {
                        setState(() {
                          final updatedIndex = contacts.indexWhere((c) => c.id == value.id);
                          if (updatedIndex != -1) {
                            contacts[updatedIndex] = value;
                            filteredContacts = List.from(contacts);
                            if (_isSearching) {
                              filterContacts(); // Reapply search filter after update
                            }
                          }
                        });
                        _saveContacts();
                      }
                    });
                  },
                  trailing: PopupMenuButton<String>(
                    color: Colors.black.withOpacity(0.6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.white.withOpacity(0.2)),
                    ),
                    onSelected: (value) async {
                      if (value == 'edit') {
                        final contactData = await showDialog<ContactData>(
                          context: context,
                          builder: (context) => ContactEditorDialog(
                            initialName: contact.name,
                            initialProfilePic: contact.profilePic,
                          ),
                        );
                        if (contactData != null && contactData.name.isNotEmpty) {
                          final profilePicPath = await _copyImageToAppDir(contactData.profilePicPath);
                          setState(() {
                            final updatedIndex = contacts.indexWhere((c) => c.id == contact.id);
                            if (updatedIndex != -1) {
                              contacts[updatedIndex] = LanContact(
                                name: contactData.name,
                                ip: contact.ip,
                                id: contact.id,
                                profilePic: profilePicPath,
                                lastMessage: contact.lastMessage,
                              );
                              filteredContacts = List.from(contacts);
                              if (_isSearching) {
                                filterContacts(); // Reapply search filter after edit
                              }
                            }
                          });
                          await _saveContacts();
                        }
                      } else if (value == 'delete') {
                        setState(() {
                          final updatedIndex = contacts.indexWhere((c) => c.id == contact.id);
                          if (updatedIndex != -1) {
                            contacts.removeAt(updatedIndex);
                            filteredContacts = List.from(contacts);
                            if (_isSearching) {
                              filterContacts(); // Reapply search filter after delete
                            }
                          }
                        });
                        await _saveContacts();
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'edit', child: Text("Edit", style: TextStyle(color: Colors.white))),
                      const PopupMenuItem(value: 'delete', child: Text("Delete", style: TextStyle(color: Colors.white))),
                    ],
                  ),
                );
              },
            )
          : _screens[_selectedIndex],
      floatingActionButton: _selectedIndex == 0
          ? Padding(
              padding: const EdgeInsets.only(bottom: 20, right: 22),
              child: FloatingActionButton(
                backgroundColor: _isButtonClicked
                    ? Colors.white
                    : const Color(0xFF629584),
                onPressed: () async {
                  setState(() {
                    _isButtonClicked = true;
                  });
                  final newContact = await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => NewChatScreen()),
                  );
                  if (newContact != null && newContact is LanContact) {
                    addContact(newContact); // Instantly add the new contact
                  }
                  setState(() {
                    _isButtonClicked = false;
                  });
                },
                child: Icon(
                  Icons.message,
                  color: _isButtonClicked ? Colors.black : AppColor.text,
                ),
              ),
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: AppColor.appbar,
        selectedItemColor: Color(0xFF629584),
        unselectedItemColor: AppColor.text,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.chat),
            label: 'Chat',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.call),
            label: 'Calls',
          ),
        ],
      ),
    );
  }
}

class ContactData {
  final String name;
  final String? profilePicPath;

  ContactData({required this.name, this.profilePicPath});
}

class ContactEditorDialog extends StatefulWidget {
  final String initialName;
  final String? initialProfilePic;

  const ContactEditorDialog({
    required this.initialName,
    this.initialProfilePic,
  });

  @override
  _ContactEditorDialogState createState() => _ContactEditorDialogState();
}

class _ContactEditorDialogState extends State<ContactEditorDialog> {
  final TextEditingController _nameController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  File? _selectedImage;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.initialName;
    if (widget.initialProfilePic != null) {
      _selectedImage = File(widget.initialProfilePic!);
    }
  }

  Future<void> _pickImage() async {
    try {
      print('Attempting to pick image...');
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 50,
      );
      print('Image picked: ${image?.path}');

      if (image != null) {
        final file = File(image.path);
        if (await file.exists()) {
          print('File exists at path: ${image.path}');
          setState(() {
            _selectedImage = file;
          });
        } else {
          print('File does not exist at path: ${image.path}');
        }
      } else {
        print('No image selected');
      }
    } catch (e, stackTrace) {
      print('Error picking image: $e');
      print('Stack trace: $stackTrace');
    }
  }

  void _removeImage() {
    setState(() {
      _selectedImage = null;
    });
    print('Image removed');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColor.appbar, AppColor.headertext, AppColor.button],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8.0),
              child: const Text(
                'Edit Contact',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: CircleAvatar(
                              radius: 30,
                              backgroundImage: _selectedImage != null
                                  ? FileImage(_selectedImage!)
                                  : null,
                              child: _selectedImage == null
                                  ? const Icon(Icons.person, size: 30, color: Colors.white)
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.camera_alt, color: AppColor.button, size: 24),
                            onPressed: _pickImage,
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red, size: 24),
                            onPressed: _removeImage,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: 200,
                        child: TextField(
                          controller: _nameController,
                          decoration: InputDecoration(
                            labelText: 'Name',
                            labelStyle: const TextStyle(color: Colors.white),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Colors.white),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Colors.white),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Colors.white),
                            ),
                          ),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel', style: TextStyle(color: Colors.white)),
                  ),
                  TextButton(
                    onPressed: () {
                      final name = _nameController.text.trim();
                      if (name.isNotEmpty) {
                        Navigator.pop(
                          context,
                          ContactData(
                            name: name,
                            profilePicPath: _selectedImage?.path,
                          ),
                        );
                      }
                    },
                    child: const Text('Save', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
