import 'package:flutter/material.dart';
import 'services/medace_api.dart';
import 'package:file_picker/file_picker.dart';

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
  String _selectedModel = 'llama3.2:latest';// Default model

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
          _messages.add(ChatMessage(
            text: '📄 "${file.name}" uploaded successfully. You can now ask questions about it.',
            isUser: false,
            isSystem: true,
          ));
        });
      } else {
        setState(() {
          _messages.add(ChatMessage(
            text: 'Failed to upload "${file.name}". Please try again.',
            isUser: false,
            isSystem: true,
          ));
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
        _messages.add(ChatMessage(
            text: 'All uploaded documents have been removed.',
            isUser: false,
            isSystem: true,
        ));
    });

    if (!success) {
        print("Server clear failed but local state was reset.");
    }
}
  // --- Send a message ---
  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    _controller.clear();
    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _isLoading = true;
    });

    final responseData = await MedAceApiService.askQuestion(
      text,
      _selectedModel,
      sessionId: _sessionId,
    );

    setState(() {
      _isLoading = false;
      if (responseData != null) {
        _messages.add(ChatMessage(
          text: responseData['answer'],
          isUser: false,
          sources: responseData['sources'],
        ));
      } else {
        _messages.add(ChatMessage(
          text: 'Error: Failed to connect to the MedAce Python API. Check your server IP.',
          isUser: false,
        ));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('MedAce Chat App'),
        actions: [
          // Model selector
          Container(
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.horizontal(left: Radius.zero, right: Radius.zero),
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
                items: _availableModels.map<DropdownMenuItem<String>>((String model) {
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
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('Uploading and processing document...', style: TextStyle(fontSize: 12)),
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
}

// --- Chat Message Model ---
class ChatMessage {
  final String text;
  final bool isUser;
  final List<dynamic>? sources;
  final bool isSystem;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.sources,
    this.isSystem = false,
  });
}

// --- Chat Bubble Widget ---
class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final alignment = message.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
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
                  fontStyle: message.isSystem ? FontStyle.italic : FontStyle.normal,
                ),
              ),
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
                      color: Colors.grey[800]),
                ),
                ...message.sources!
                    .map((source) => Text(
                          "- ${source['file']} (Page ${source['page']})",
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[700],
                              fontStyle: FontStyle.italic),
                        ))
                    .toList(),
              ]
            ],
          ),
        ),
      ],
    );
  }
}