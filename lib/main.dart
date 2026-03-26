import 'package:flutter/material.dart';
import 'services/medace_api.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MedAce Chat App',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: OllamaChatPage(),
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
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isUploading = false;

  // Session management
  String? _sessionId;
  List<String> _uploadedFiles = [];

  final List<String> _availableModels = [
    'llama3.2:latest',
    'medllama2:7b-q4_K_M',
    'AntAngelMed/MedGemma1.5:4b',
  ];
  // ignore: prefer_final_fields
  String _selectedModel = 'llama3.2:latest'; // Default model

// --- Clear chat history ---
  void _clearChat() {
    setState(() {
      _messages.clear();
      _messages.add(
        ChatMessage(
          text: '🧹 Chat history cleared. Starting fresh!',
          isUser: false,
          isSystem: true,
        ),
      );
    });
  }
  // --- Upload a PDF ---
  Future<void> _uploadDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true, // needed for web support
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    setState(() => _isUploading = true);

    try {
      Map<String, dynamic>? response;

      if (file.bytes != null) {
        // Web or mobile with bytes
        response = await MedAceApiService.uploadDocumentBytes(
          file.bytes!,
          file.name,
          sessionId: _sessionId,
        );
      } else if (file.path != null) {
        // Mobile/desktop with file path
        response = await MedAceApiService.uploadDocument(
          file.path!,
          file.name,
          sessionId: _sessionId,
        );
      }

      if (response != null) {
        setState(() {
          _sessionId = response!['session_id'];
          _uploadedFiles = List<String>.from(response['files_in_session']);
        });

        // Show confirmation in chat
        setState(() {
          _messages.add(
            ChatMessage(
              text:
                  '📄 "${file.name}" uploaded successfully. You can now ask questions about it.',
              isUser: false,
              isSystem: true,
            ),
          );
        });
      } else {
        setState(() {
          _messages.add(
            ChatMessage(
              text: 'Failed to upload "${file.name}". Please try again.',
              isUser: false,
              isSystem: true,
            ),
          );
        });
      }
    } finally {
      setState(() => _isUploading = false);
    }
  }

  //Clear documents for a session
  Future<void> _clearDocuments() async {
    if (_sessionId == null) return;

    final success = await MedAceApiService.clearSession(_sessionId!);

    setState(() {
      // Always clear the local state regardless of server response
      // If server already cleared it or session expired, we still want UI to reset
      _sessionId = null;
      _uploadedFiles = [];
      _messages.add(
        ChatMessage(
          text: 'All uploaded documents have been removed.',
          isUser: false,
          isSystem: true,
        ),
      );
    });

    if (!success) {
      // ignore: avoid_print
      print("Server clear failed but local state was reset.");
    }
  }

  // --- Send a message ---
  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    List<Map<String, String>> history = [];
    int historyLimit = 10;
    int start = _messages.length > historyLimit ? _messages.length - historyLimit : 0;

    for (int i = start; i < _messages.length; i++) {
      // Ignore system messages and search results to save tokens
      if (!_messages[i].isSystem && _messages[i].searchResults == null) {
        history.add({
          'role': _messages[i].isUser ? 'user' : 'assistant',
          'content': _messages[i].text,
        });
      }
    }

    _controller.clear();
    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _isLoading = true;
    });

    final responseData = await MedAceApiService.askQuestion(
      text,
      _selectedModel,
      sessionId: _sessionId,
      chatHistory: history,
    );

    setState(() {
      _isLoading = false;
      if (responseData != null) {
        _messages.add(
          ChatMessage(
            text: responseData['answer'],
            isUser: false,
            sources: responseData['sources'],
          ),
        );
      } else {
        _messages.add(
          ChatMessage(
            text:
                'Error: Failed to connect to the MedAce Python API. Check your server IP.',
            isUser: false,
          ),
        );
      }
    });
  }

  // --- Search the web ---
  Future<void> _searchWeb(String text) async {
    if (text.trim().isEmpty) return;

    _controller.clear();
    setState(() {
      _messages.add(
        ChatMessage(
          text: '🔍 Searching for: "$text"',
          isUser: false,
          isSystem: true,
        ),
      );
      _isLoading = true;
    });

    final responseData = await MedAceApiService.searchWeb(text, _selectedModel);

    setState(() {
      _isLoading = false;
      if (responseData != null) {
        // Add a message with search results
        _messages.add(
          ChatMessage(
            text: responseData['answer'] ?? 'Here are your results:',
            isUser: false,
            isSystem: false, // must be false — ChatBubble hides results when isSystem=true
            searchResults: (responseData['web_results'] as List)
                .map(
                  (result) => {
                    'title': result['title'] ?? '',
                    'snippet': result['snippet'] ?? '',
                    'displayLink': result['displayLink'] ?? '',
                    'link': result['link'] ?? '', // NEW: Grab the actual URL,
                  },
                )
                .toList(),
            imageResults: (responseData['image_results'] as List)
                .where((result) => result['image'] != null)
                .map(
                  (result) => {
                    'title': result['title'] ?? '',
                    'image': {
                      'thumbnailLink': result['image']['thumbnailLink'] ?? '',
                      'contextLink': result['image']['contextLink'] ?? '',
                      'height': result['image']['height'] ?? 0,
                      'width': result['image']['width'] ?? 0,
                      'byteSize': result['image']['byteSize'] ?? 0,
                    },
                  },
                )
                .toList(),
          ),
        );
      } else {
        _messages.add(
          ChatMessage(
            text:
                'Error: Failed to perform web search. Check your API configuration.',
            isUser: false,
            isSystem: true,
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(
      title: Text('MedAce Chat App'),
      
      actions: [
        IconButton(
          icon: const Icon(Icons.delete_sweep),
          tooltip: 'Clear Chat',
          onPressed: _clearChat,
        ),
        // Model selector
        Container(
          decoration: BoxDecoration(
            color: Colors.blue,
            borderRadius: BorderRadius.horizontal(
              left: Radius.zero,
              right: Radius.zero,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: DropdownButton<String>(
              value: _selectedModel,
              icon: const Icon(Icons.arrow_drop_down, color: Colors.blue),
              dropdownColor: Colors.blue[700],
              style: const TextStyle(color: Colors.white, fontSize: 14),
              underline: Container(height: 0),
              onChanged: (String? newValue) {
                setState(() => _selectedModel = newValue!);
              },
              items: _availableModels.map<DropdownMenuItem<String>>((
                String model,
              ) {
                return DropdownMenuItem<String>(
                  value: model,
                  child: Text(model.split(':')[0]),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    ),
    body: Column(
      children: [
        // --- Uploaded files banner ---
        if (_uploadedFiles.isNotEmpty)
          Container(
            width: double.infinity,
            color: Colors.blue[50],
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.description, size: 16, color: Colors.blue[700]),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Docs: ${_uploadedFiles.join(', ')}',
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

        // --- Chat messages ---
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.all(8.0),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              return ChatBubble(message: _messages[index]);
            },
          ),
        ),

        if (_isLoading) LinearProgressIndicator(),
        if (_isUploading)
          Padding(
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
                Text(
                  'Uploading and processing document...',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),

        // --- Input row ---
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 8.0),
          child: Row(
            children: [
              // Upload button
              IconButton(
                icon: Icon(Icons.attach_file),
                tooltip: 'Upload PDF',
                onPressed: _isUploading ? null : _uploadDocument,
              ),
              // Search button
              IconButton(
                icon: Icon(Icons.search),
                tooltip: 'Search Web',
                onPressed: _isUploading
                    ? null
                    : () => _searchWeb(_controller.text),
              ),
              // Text input
              Expanded(
                child: TextField(
                  controller: _controller,
                  onSubmitted: _sendMessage,
                  decoration: InputDecoration(hintText: 'Enter your message'),
                ),
              ),
              // Send button
              IconButton(
                icon: Icon(Icons.send),
                onPressed: () => _sendMessage(_controller.text),
              ),
            ],
          ),
        ),
        SizedBox(height: 10),
      ],
    ),
  );
}
} // end _OllamaChatPageState

// --- Chat Message Model ---
class ChatMessage {
  final String text;
  final bool isUser;
  final List<dynamic>? sources;
  final bool isSystem;
  final List<dynamic>? searchResults; // New field for search results
  final List<dynamic>? imageResults; // New field for image results

  ChatMessage({
    required this.text,
    required this.isUser,
    this.sources,
    this.isSystem = false,
    this.searchResults,
    this.imageResults,
  });
}

// --- Chat Bubble Widget ---
class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final alignment = message.isUser
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;
    Color bgColor;
    if (message.isSystem) {
      bgColor = Colors.green[50]!;
    } else if (message.isUser) {
      bgColor = Colors.blue[100]!;
    } else {
      bgColor = Colors.grey[200]!;
    }

    return Column(
      crossAxisAlignment: alignment,
      children: [
        Container(
          margin: EdgeInsets.symmetric(vertical: 4.0),
          padding: EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message.text.trim(),
                style: TextStyle(
                  color: Colors.black,
                  fontStyle: message.isSystem
                      ? FontStyle.italic
                      : FontStyle.normal,
                ),
              ),
              // Display search results if available
              if (!message.isUser &&
                  !message.isSystem &&
                  message.searchResults != null &&
                  message.searchResults!.isNotEmpty) ...[
                Divider(color: Colors.grey[400], thickness: 1, height: 20),
                Text(
                  "Web Search Results:",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.grey[800],
                  ),
                ),
                ...message.searchResults!
                    .map(
                      (result) => InkWell(
                        // NEW: Make the source clickable!
                        onTap: () async {
                          final urlString = result['link'];
                          if (urlString != null && urlString.isNotEmpty) {
                            final url = Uri.parse(urlString);
                            if (await canLaunchUrl(url)) {
                              await launchUrl(url, mode: LaunchMode.externalApplication);
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
                                  color: Colors.blue[800], // Make it look like a link
                                  fontWeight: FontWeight.bold,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                "${result['snippet']}",
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[800],
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
              // Display image results if available
              if (!message.isUser &&
                  !message.isSystem &&
                  message.imageResults != null &&
                  message.imageResults!.isNotEmpty) ...[
                Divider(color: Colors.grey[400], thickness: 1, height: 20),
                Text(
                  "Image Search Results:",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.grey[800],
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
                            border: Border.all(color: Colors.grey[300]!),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child:
                              result['image'] != null &&
                                  result['image']['thumbnailLink'] != null
                              ? Image.network(
                                  result['image']['thumbnailLink'],
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Container(
                                        color: Colors.grey[200],
                                        child: Icon(
                                          Icons.broken_image,
                                          size: 20,
                                          color: Colors.grey[400],
                                        ),
                                      ),
                                )
                              : Container(
                                  color: Colors.grey[200],
                                  child: Icon(
                                    Icons.image,
                                    size: 30,
                                    color: Colors.grey[400],
                                  ),
                                ),
                        ),
                      )
                      .toList(),
                ),
              ],
              // Display sources if available (existing functionality)
              if (!message.isUser &&
                  !message.isSystem &&
                  message.sources != null &&
                  message.sources!.isNotEmpty) ...[
                Divider(color: Colors.grey[400], thickness: 1, height: 20),
                Text(
                  "Sources:",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.grey[800],
                  ),
                ),
                ...message.sources!
                    .map(
                      (source) => Text(
                        "- ${source['file']} (Page ${source['page']})",
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[700],
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
