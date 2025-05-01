import 'package:flutter/material.dart';
import '../color.dart';
import 'calls_screen.dart';
import 'settings_screen.dart';
import 'new_chat_screen.dart'; // Import New Chat Screen

class MainHomeScreen extends StatefulWidget {
  @override
  _MainHomeScreenState createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  int _selectedIndex = 0; // Default selected index (Chat/Home)
  bool _isButtonClicked = false; // Track button click state
  bool _isSearching = false; // Track search state
  TextEditingController _searchController = TextEditingController();

  // Static Chat Data
  List<Map<String, String>> chats = [
    {"name": "Ahmad Saeed", "lastMessage": "Hey! How are you?"},
    {"name": "Umair Bandesha", "lastMessage": "Let's meet tomorrow."},
    {"name": "Hassan Mota", "lastMessage": "Did you check the files?"},
    {"name": "Abdullah", "lastMessage": "See you soon!"},
    {"name": "Ali Malik", "lastMessage": "Good morning! 😊"},
    {"name": "hooo", "lastMessage": "See you"},
    {"name": "HEHE", "lastMessage": "I am at home."},
    {"name": "YAhoo", "lastMessage": "Let's go shopping!"},
    {"name": "Ahmer", "lastMessage": "Hey! How are you?"},
    {"name": "Bandesha", "lastMessage": "Let's meet tomorrow."},
    {"name": "Mota", "lastMessage": "Did you check the files?"},
    {"name": "saif", "lastMessage": "See you soon!"},
    {"name": "Malik", "lastMessage": "Good morning! 😊"},
   
  ];

  List<Map<String, String>> filteredChats = [];

  @override
  void initState() {
    super.initState();
    filteredChats = chats; // Initially, show all chats

    // Add a listener to filter chats dynamically
    _searchController.addListener(() {
      filterChats();
    });
  }

  // Function to filter chat list
  void filterChats() {
    String query = _searchController.text.toLowerCase();
    setState(() {
      filteredChats = chats.where((chat) {
        return chat["name"]!.toLowerCase().contains(query);
      }).toList();
    });
  }

  // Function to toggle search mode
  void toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear(); // Clear search when exiting search mode
      }
    });
  }

  final List<Widget> _screens = [
    Center(
      child: Text(
        'Chat Screen',
        style: TextStyle(color: AppColor.text, fontSize: 24),
      ),
    ),
    CallsScreen(), // Calls Screen
    SettingsScreen() // Settings Screen
  ];

  // Function to handle navigation between screens
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
                      hintText: "Search chats...",
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
                onPressed: toggleSearch, // Toggle search mode
              ),
            ],
          ),
        ),
      ),

      body: _selectedIndex == 0
          ? ListView.builder(
              itemCount: filteredChats.length,
              itemBuilder: (context, index) {
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.grey[800],
                    child: Icon(Icons.person, color: Colors.white),
                  ),
                  title: Text(
                    filteredChats[index]["name"]!,
                    style: TextStyle(color: AppColor.text),
                  ),
                  subtitle: Text(
                    filteredChats[index]["lastMessage"]!,
                    style: TextStyle(color: Colors.grey),
                  ),
                  onTap: () {
                    // Open chat with selected person
                  },
                );
              },
            )
          : _screens[_selectedIndex], // Display calls or settings screen

      floatingActionButton: _selectedIndex == 0
          ? Padding(
              padding: const EdgeInsets.only(bottom: 20, right: 22),
              child: FloatingActionButton(
                backgroundColor: _isButtonClicked
                    ? Colors.white
                    : const Color(0xFF629584),
                onPressed: () {
                  setState(() {
                    _isButtonClicked = true;
                  });

                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => NewChatScreen()),
                  ).then((_) {
                    setState(() {
                      _isButtonClicked = false;
                    });
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
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
