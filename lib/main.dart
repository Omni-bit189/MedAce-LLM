import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/medace_api.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, ThemeMode currentMode, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'MedAce Chat App',
          theme: ThemeData(
            primarySwatch: Colors.blue,
            brightness: Brightness.light,
            scaffoldBackgroundColor: Colors.white,
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
          darkTheme: ThemeData(
            primarySwatch: Colors.blue,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF131314),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF131314),
              foregroundColor: Colors.white,
              elevation: 0,
            ),
          ),
          themeMode: currentMode,
          home: const OllamaChatPage(),
        );
      },
    );
  }
}

class OllamaChatPage extends StatefulWidget {
  const OllamaChatPage({super.key});
  @override
  _OllamaChatPageState createState() => _OllamaChatPageState();
}

class _OllamaChatPageState extends State<OllamaChatPage> {
  final _controller = TextEditingController();

  bool _isLoading = false;
  bool _isUploading = false;
  String _selectedModel = 'llama3.2:latest';
  final List<String> _availableModels = [
    'llama3.2:latest',
    'medllama2:7b-q4_K_M',
    'AntAngelMed/MedGemma1.5:4b',
  ];

  List<ChatSession> _allSessions = [];
  late ChatSession _currentSession;
  final String _storageKey = 'medace_chat_history';

  // --- NEW: Pending Attachment States ---
  PlatformFile? _pendingPdf;
  XFile? _pendingImage;
  Uint8List? _pendingImageBytes;

  @override
  void initState() {
    super.initState();
    _createNewSession();
    _loadSavedSessions();
  }

  Future<void> _loadSavedSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final String? savedData = prefs.getString(_storageKey);
    if (savedData != null) {
      setState(
        () => _allSessions = jsonDecode(
          savedData,
        ).map<ChatSession>((e) => ChatSession.fromJson(e)).toList(),
      );
    }
  }

  Future<void> _saveSessionsToDisk() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(_allSessions.map((e) => e.toJson()).toList()),
    );
  }

  void _createNewSession() {
    setState(
      () => _currentSession = ChatSession(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: 'New Chat',
        messages: [],
      ),
    );
  }

  void _loadSession(String id) {
    setState(
      () => _currentSession = _allSessions.firstWhere(
        (session) => session.id == id,
      ),
    );
    Navigator.pop(context);
  }

  void _deleteSession(String id) {
    setState(() {
      _allSessions.removeWhere((session) => session.id == id);
      if (_currentSession.id == id) _createNewSession();
      _saveSessionsToDisk();
    });
  }

  void _updateCurrentSessionData() {
    if (!_allSessions.any((s) => s.id == _currentSession.id) &&
        _currentSession.messages.isNotEmpty) {
      final userMessages = _currentSession.messages.where((m) => m.isUser);
      if (userMessages.isNotEmpty) {
        final firstMsg = userMessages.first.text;
        _currentSession.title = firstMsg.length > 20
            ? '${firstMsg.substring(0, 20)}...'
            : firstMsg;
      } else {
        _currentSession.title = 'Document Scan';
      }
      _allSessions.insert(0, _currentSession);
    }
    _saveSessionsToDisk();
  }

  void _clearCurrentChat() {
    setState(() {
      _currentSession.messages.clear();
      _currentSession.messages.add(
        ChatMessage(
          text: '🧹 Chat history cleared for this session.',
          isUser: false,
          isSystem: true,
        ),
      );
      _updateCurrentSessionData();
    });
  }

  Future<void> _clearDocuments() async {
    if (_currentSession.backendSessionId == null) return;
    await MedAceApiService.clearSession(_currentSession.backendSessionId!);
    setState(() {
      _currentSession.backendSessionId = null;
      _currentSession.uploadedFiles = [];
      _currentSession.messages.add(
        ChatMessage(
          text: 'All uploaded documents have been removed.',
          isUser: false,
          isSystem: true,
        ),
      );
      _updateCurrentSessionData();
    });
  }

  // --- NEW: Staged File Pickers ---
  Future<void> _stageDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _pendingPdf = result.files.first;
        _pendingImage = null; // Only allow one attachment at a time
        _pendingImageBytes = null;
      });
    }
  }

  Future<void> _stageImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 800,
      imageQuality: 70,
    );
    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        _pendingImage = image;
        _pendingImageBytes = bytes;
        _pendingPdf = null;
      });
    }
  }

  void _clearPending() {
    setState(() {
      _pendingPdf = null;
      _pendingImage = null;
      _pendingImageBytes = null;
    });
  }

  // --- NEW: Unified Send & Upload Logic ---
  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty && _pendingPdf == null && _pendingImage == null) {
      return;
    }

    _controller.clear();
    setState(() => _isLoading = true);

    String finalPrompt = text;
    String? attachedName;
    String? base64Str;

    // 1. Process Pending PDF
    if (_pendingPdf != null) {
      final file = _pendingPdf!;
      attachedName = file.name;
      setState(() => _isUploading = true);
      try {
        Map<String, dynamic>? response;
        if (file.bytes != null) {
          response = await MedAceApiService.uploadDocumentBytes(
            file.bytes!,
            file.name,
            sessionId: _currentSession.backendSessionId,
          );
        } else if (file.path != null) {
          response = await MedAceApiService.uploadDocument(
            file.path!,
            file.name,
            sessionId: _currentSession.backendSessionId,
          );
        }
        if (response != null) {
          _currentSession.backendSessionId = response['session_id'];
          _currentSession.uploadedFiles = List<String>.from(
            response['files_in_session'] ?? [file.name],
          );
        }
      } finally {
        setState(() => _isUploading = false);
      }
      if (finalPrompt.trim().isEmpty) {
        finalPrompt = "Please summarize this uploaded document.";
      }
    }

    // 2. Process Pending Image
    if (_pendingImage != null && _pendingImageBytes != null) {
      final image = _pendingImage!;
      attachedName = image.name;
      base64Str = base64Encode(_pendingImageBytes!);
      setState(() => _isUploading = true);

      try {
        String extractedText = "";
        if (kIsWeb) {
          final response = await MedAceApiService.uploadImageBytes(
            _pendingImageBytes!,
            image.name,
          );
          extractedText =
              (response != null && response['extracted_text'] != null)
              ? response['extracted_text']
              : "Error: Failed to extract text.";
        } else {
          final inputImage = InputImage.fromFilePath(image.path);
          final textRecognizer = TextRecognizer(
            script: TextRecognitionScript.latin,
          );
          final RecognizedText recognizedText = await textRecognizer
              .processImage(inputImage);
          extractedText = recognizedText.text.trim().isEmpty
              ? "Error: No readable text found."
              : recognizedText.text;
          textRecognizer.close();
        }

        if (finalPrompt.trim().isEmpty) {
          finalPrompt = "Please summarize this scanned document.";
          finalPrompt = "$finalPrompt\n\n[Scanned Image Text]:\n$extractedText";
        }
      } catch (e) {
        print("OCR Error: $e");
      } finally {
        setState(() => _isUploading = false);
      }
    }

    // 3. Add to UI (The user's message now holds the attachments!)
    setState(() {
      _currentSession.messages.add(
        ChatMessage(
          text: text.trim().isEmpty ? "Sent an attachment." : text,
          isUser: true,
          attachedFileName: _pendingPdf != null ? attachedName : null,
          base64Image: _pendingImage != null ? base64Str : null,
        ),
      );
      _clearPending(); // Clear staged files
      _updateCurrentSessionData();
    });

    // 4. Send to LLM
    List<Map<String, String>> history = [];
    int start = _currentSession.messages.length > 10
        ? _currentSession.messages.length - 10
        : 0;
    for (int i = start; i < _currentSession.messages.length; i++) {
      if (!_currentSession.messages[i].isSystem) {
        history.add({
          'role': _currentSession.messages[i].isUser ? 'user' : 'assistant',
          'content': _currentSession.messages[i].text,
        });
      }
    }

    final responseData = await MedAceApiService.askQuestion(
      finalPrompt,
      _selectedModel,
      sessionId: _currentSession.backendSessionId,
      chatHistory: history,
    );

    setState(() {
      _isLoading = false;
      _currentSession.messages.add(
        responseData != null
            ? ChatMessage(
                text: responseData['answer'],
                isUser: false,
                sources: responseData['sources'],
              )
            : ChatMessage(
                text: 'Error: Failed to connect to the MedAce API.',
                isUser: false,
              ),
      );
      _updateCurrentSessionData();
    });
  }

  Future<void> _searchWeb(String text) async {
    if (text.trim().isEmpty) return;
    _controller.clear();

    setState(() {
      _currentSession.messages.add(ChatMessage(text: text, isUser: true));
      _currentSession.messages.add(
        ChatMessage(
          text: '🔍 Searching the web...',
          isUser: false,
          isSystem: true,
        ),
      );
      _isLoading = true;
      _updateCurrentSessionData();
    });

    final responseData = await MedAceApiService.searchWeb(text, _selectedModel);

    setState(() {
      _isLoading = false;
      if (responseData != null) {
        _currentSession.messages.add(
          ChatMessage(
            text: responseData['answer'] ?? 'Here are your results:',
            isUser: false,
            searchResults: (responseData['web_results'] as List?)
                ?.map(
                  (result) => {
                    'title': result['title'] ?? '',
                    'snippet': result['snippet'] ?? '',
                    'displayLink': result['displayLink'] ?? '',
                    'link': result['link'] ?? '',
                  },
                )
                .toList(),
            imageResults: (responseData['image_results'] as List?)
                ?.where((result) => result['image'] != null)
                .map(
                  (result) => {
                    'title': result['title'] ?? '',
                    'image': {
                      'thumbnailLink': result['image']?['thumbnailLink'] ?? '',
                      'contextLink': result['image']?['contextLink'] ?? '',
                    },
                  },
                )
                .toList(),
          ),
        );
      } else {
        _currentSession.messages.add(
          ChatMessage(
            text: 'Error: Failed to perform web search.',
            isUser: false,
            isSystem: true,
          ),
        );
      }
      _updateCurrentSessionData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      drawer: Drawer(
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              accountName: const Text(
                "MedAce History",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              accountEmail: Text("${_allSessions.length} saved chats"),
              currentAccountPicture: const CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(
                  Icons.medical_services,
                  color: Colors.blue,
                  size: 30,
                ),
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).appBarTheme.backgroundColor,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('New Chat'),
              onTap: () {
                Navigator.pop(context);
                _createNewSession();
              },
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: _allSessions.length,
                itemBuilder: (context, index) {
                  final session = _allSessions[index];
                  return ListTile(
                    selected: session.id == _currentSession.id,
                    selectedTileColor: Theme.of(
                      context,
                    ).primaryColor.withValues(alpha: 0.1),
                    leading: const Icon(Icons.chat_bubble_outline),
                    title: Text(
                      session.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      color: Colors.redAccent,
                      onPressed: () => _deleteSession(session.id),
                    ),
                    onTap: () => _loadSession(session.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      appBar: AppBar(
        title: const Text(
          'MedAce',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
        ),
        actions: [
          IconButton(
            icon: Icon(
              themeNotifier.value == ThemeMode.light
                  ? Icons.dark_mode
                  : Icons.light_mode,
            ),
            onPressed: () =>
                themeNotifier.value = themeNotifier.value == ThemeMode.light
                ? ThemeMode.dark
                : ThemeMode.light,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear Chat',
            onPressed: _clearCurrentChat,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (_currentSession.uploadedFiles.isNotEmpty)
            Container(
              width: double.infinity,
              color: isDark
                  ? Colors.blue[900]?.withValues(alpha: 0.3)
                  : Colors.blue[50],
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.description, size: 16, color: Colors.blue[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Active Docs: ${_currentSession.uploadedFiles.join(', ')}',
                      style: TextStyle(fontSize: 12, color: Colors.blue[700]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: _clearDocuments,
                    child: Icon(Icons.close, size: 16, color: Colors.blue[700]),
                  ),
                ],
              ),
            ),

          Expanded(
            child: _currentSession.messages.isEmpty
                ? _buildEmptyState(isDark)
                : ListView.builder(
                    padding: const EdgeInsets.all(8.0),
                    itemCount: _currentSession.messages.length,
                    itemBuilder: (context, index) =>
                        ChatBubble(message: _currentSession.messages[index]),
                  ),
          ),

          if (_isLoading) const LinearProgressIndicator(),
          if (_isUploading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('Processing...', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),

          _buildInputArea(isDark),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '✨ Hi Omair',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Where should we start?',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 50),

              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.description, size: 18),
                    label: const Text('Upload Medical PDF'),
                    backgroundColor: isDark
                        ? const Color(0xFF1E1F20)
                        : Colors.grey[100],
                    side: BorderSide.none,
                    padding: const EdgeInsets.all(12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    onPressed: _stageDocument,
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.document_scanner, size: 18),
                    label: const Text('Scan Document'),
                    backgroundColor: isDark
                        ? const Color(0xFF1E1F20)
                        : Colors.grey[100],
                    side: BorderSide.none,
                    padding: const EdgeInsets.all(12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    onPressed: _stageImage,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputArea(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 800),
        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1F20) : Colors.grey[200],
          borderRadius: BorderRadius.circular(30),
        ),
        child: Column(
          children: [
            // --- NEW: Pending Attachment Preview Area ---
            if (_pendingPdf != null || _pendingImage != null)
              Container(
                margin: const EdgeInsets.only(left: 16, top: 12, bottom: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2E2F30) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_pendingImageBytes != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.memory(
                          _pendingImageBytes!,
                          height: 40,
                          width: 40,
                          fit: BoxFit.cover,
                        ),
                      ),
                    if (_pendingPdf != null)
                      Icon(
                        Icons.picture_as_pdf,
                        color: Colors.red[400],
                        size: 30,
                      ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        _pendingPdf?.name ??
                            _pendingImage?.name ??
                            "Attached File",
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      color: Colors.grey[500],
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: _clearPending,
                    ),
                  ],
                ),
              ),

            // Standard Input Row
            Row(
              children: [
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.add_circle_outline,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                  tooltip: 'Attach File or Photo',
                  offset: const Offset(0, -120),
                  color: isDark ? const Color(0xFF2E2F30) : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  onSelected: (value) {
                    if (value == 'pdf') _stageDocument();
                    if (value == 'camera') _stageImage();
                  },
                  itemBuilder: (BuildContext context) =>
                      <PopupMenuEntry<String>>[
                        PopupMenuItem<String>(
                          value: 'pdf',
                          child: Row(
                            children: [
                              Icon(
                                Icons.picture_as_pdf,
                                color: isDark ? Colors.red[300] : Colors.red,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Upload PDF',
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuItem<String>(
                          value: 'camera',
                          child: Row(
                            children: [
                              Icon(
                                Icons.camera_alt,
                                color: isDark ? Colors.blue[300] : Colors.blue,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Take Photo',
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                ),

                IconButton(
                  icon: const Icon(Icons.travel_explore),
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                  onPressed: _isUploading
                      ? null
                      : () => _searchWeb(_controller.text),
                ),

                Expanded(
                  child: TextField(
                    controller: _controller,
                    onSubmitted: _sendMessage,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Ask MedAce...',
                      hintStyle: TextStyle(
                        color: isDark ? Colors.grey[500] : Colors.grey[600],
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ),

                Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2E2F30) : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedModel,
                      icon: Icon(
                        Icons.keyboard_arrow_down,
                        size: 16,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                      dropdownColor: isDark
                          ? const Color(0xFF2E2F30)
                          : Colors.white,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      onChanged: (String? newValue) =>
                          setState(() => _selectedModel = newValue!),
                      items: _availableModels
                          .map<DropdownMenuItem<String>>(
                            (String model) => DropdownMenuItem<String>(
                              value: model,
                              child: Text(
                                model
                                    .split(':')[0]
                                    .replaceAll('AntAngelMed/', ''),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  color: isDark ? Colors.grey[300] : Colors.black87,
                  onPressed: () => _sendMessage(_controller.text),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ChatSession {
  final String id;
  String title;
  List<ChatMessage> messages;
  String? backendSessionId;
  List<String> uploadedFiles;

  ChatSession({
    required this.id,
    required this.title,
    required this.messages,
    this.backendSessionId,
    this.uploadedFiles = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'backendSessionId': backendSessionId,
    'uploadedFiles': uploadedFiles,
    'messages': messages.map((m) => m.toJson()).toList(),
  };
  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
    id: json['id'],
    title: json['title'],
    backendSessionId: json['backendSessionId'],
    uploadedFiles: List<String>.from(json['uploadedFiles'] ?? []),
    messages: (json['messages'] as List)
        .map((m) => ChatMessage.fromJson(m))
        .toList(),
  );
}

class ChatMessage {
  final String text;
  final bool isUser;
  final bool isSystem;
  final List<dynamic>? sources;
  final List<dynamic>? searchResults;
  final List<dynamic>? imageResults;
  final String? attachedFileName;
  final String? base64Image;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.isSystem = false,
    this.sources,
    this.searchResults,
    this.imageResults,
    this.attachedFileName,
    this.base64Image,
  });

  Map<String, dynamic> toJson() => {
    'text': text,
    'isUser': isUser,
    'isSystem': isSystem,
    'sources': sources,
    'searchResults': searchResults,
    'imageResults': imageResults,
    'attachedFileName': attachedFileName,
    'base64Image': base64Image,
  };
  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    text: json['text'] ?? '',
    isUser: json['isUser'] ?? false,
    isSystem: json['isSystem'] ?? false,
    sources: json['sources'] as List<dynamic>?,
    searchResults: json['searchResults'] as List<dynamic>?,
    imageResults: json['imageResults'] as List<dynamic>?,
    attachedFileName: json['attachedFileName'],
    base64Image: json['base64Image'],
  );
}

class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final alignment = message.isUser
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;

    Color bgColor;
    Color textColor = isDark ? Colors.white : Colors.black;
    if (message.isSystem) {
      bgColor = isDark
          ? Colors.green[900]!.withValues(alpha: 0.5)
          : Colors.green[50]!;
    } else if (message.isUser) {
      bgColor = isDark ? Colors.blue[800]! : Colors.blue[100]!;
    } else {
      bgColor = isDark ? const Color(0xFF1E1F20) : Colors.grey[100]!;
    }

    return Column(
      crossAxisAlignment: alignment,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 4.0),
          padding: const EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- FIX 1: Smaller Image Thumbnails! ---
              if (message.base64Image != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      base64Decode(message.base64Image!),
                      height: 150,
                      width: 150,
                      fit: BoxFit.cover, // No more double.infinity!
                    ),
                  ),
                ),

              if (message.attachedFileName != null &&
                  message.base64Image == null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12.0),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.blue[900]?.withValues(alpha: 0.3)
                        : Colors
                              .blue[50], // Changed from Red to Blue for user bubbles
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark ? Colors.blue[800]! : Colors.blue[200]!,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.picture_as_pdf,
                        color: isDark ? Colors.blue[300] : Colors.blue,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          message.attachedFileName!,
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

              Text(
                message.text.trim(),
                style: TextStyle(
                  color: textColor,
                  fontStyle: message.isSystem
                      ? FontStyle.italic
                      : FontStyle.normal,
                ),
              ),

              if (!message.isUser &&
                  !message.isSystem &&
                  message.searchResults != null &&
                  message.searchResults!.isNotEmpty) ...[
                Divider(color: Colors.grey[600], thickness: 1, height: 20),
                Text(
                  "Web Search Results:",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: textColor,
                  ),
                ),
                ...message.searchResults!.map(
                  (result) => InkWell(
                    onTap: () async {
                      final urlString = result['link'];
                      if (urlString != null && urlString.isNotEmpty) {
                        final url = Uri.parse(urlString);
                        if (await canLaunchUrl(url)) {
                          await launchUrl(
                            url,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "[Source] ${result['title']}",
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.blue[300]
                                  : Colors.blue[800],
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "${result['snippet']}",
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[800],
                            ),
                          ),
                          Text(
                            "${result['displayLink']}",
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              if (!message.isUser &&
                  !message.isSystem &&
                  message.imageResults != null &&
                  message.imageResults!.isNotEmpty) ...[
                Divider(color: Colors.grey[600], thickness: 1, height: 20),
                Text(
                  "Image Search Results:",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: textColor,
                  ),
                ),
                Wrap(
                  spacing: 8.0,
                  runSpacing: 8.0,
                  children: message.imageResults!
                      .map(
                        (result) => Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey[700]!),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child:
                              result['image'] != null &&
                                  result['image']['thumbnailLink'] != null
                              ? Image.network(
                                  result['image']['thumbnailLink'],
                                  fit: BoxFit.cover,
                                  errorBuilder: (c, e, s) => Container(
                                    color: Colors.grey[800],
                                    child: const Icon(Icons.broken_image),
                                  ),
                                )
                              : Container(
                                  color: Colors.grey[800],
                                  child: const Icon(Icons.image),
                                ),
                        ),
                      )
                      .toList(),
                ),
              ],
              if (!message.isUser &&
                  !message.isSystem &&
                  message.sources != null &&
                  message.sources!.isNotEmpty) ...[
                Divider(color: Colors.grey[600], thickness: 1, height: 20),
                Text(
                  "Sources:",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: textColor,
                  ),
                ),
                ...message.sources!.map(
                  (source) => Text(
                    "- ${source['file']} (Page ${source['page']})",
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.grey[400] : Colors.grey[700],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
