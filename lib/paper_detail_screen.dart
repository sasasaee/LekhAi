import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'services/gemini_question_service.dart';

import 'services/question_storage_service.dart';
import 'models/question_model.dart';
import 'services/tts_service.dart';
import 'dart:convert';
import 'services/stt_service.dart';

class PaperDetailScreen extends StatefulWidget {
  final ParsedDocument document;
  final TtsService ttsService;
  final String timestamp;

  const PaperDetailScreen({
    super.key,
    required this.document,
    required this.ttsService,
    required this.timestamp,
  });

  @override
  State<PaperDetailScreen> createState() => _PaperDetailScreenState();
}

class _PaperDetailScreenState extends State<PaperDetailScreen> {
  late ParsedDocument _document;
  final GeminiQuestionService _geminiService = GeminiQuestionService();
  final QuestionStorageService _storageService = QuestionStorageService();

  @override
  void initState() {
    super.initState();
    _document = widget.document;
  }

  Future<void> _processWithGemini(BuildContext context, String apiKey) async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    
    if (image == null) return;

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Processing with Gemini AI... please wait.")),
    );

    try {
      final newDoc = await _geminiService.processImage(image.path, apiKey);
      
      setState(() {
         // Merge new sections into existing document
         _document.sections.addAll(newDoc.sections);
      });
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Successfully added questions from Gemini!")),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Build a flat list of display items
    final items = <_ListItem>[];
    
    // 1. Document Header
    if (_document.header.isNotEmpty) {
      items.add(_HeaderItem(_document.header.join("\n")));
    }

    // 2. Sections and Questions
    for (var section in _document.sections) {
      // Add Section Header if it has title or context
      if ((section.title != null && section.title!.isNotEmpty) || 
          (section.context != null && section.context!.isNotEmpty)) {
        items.add(_SectionItem(section.title, section.context));
      }
      
      // Add Questions
      for (var q in section.questions) {
        items.add(_QuestionItem(q, section.context));
      }
    }

    // Format date for title
    String dateStr = "Unknown Date";
    try {
      final dt = DateTime.parse(widget.timestamp);
      dateStr = "${dt.day}/${dt.month} ${dt.hour}:${dt.minute}";
    } catch (_) {}

    return Scaffold(
      appBar: AppBar(
        title: Text('Paper $dateStr'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: "Save Paper",
            onPressed: () => _savePaper(context),
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          
          if (item is _HeaderItem) {
             return Padding(
              padding: const EdgeInsets.all(8.0),
              child: Card(
                color: Colors.grey.shade100,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    item.text,
                    style: const TextStyle(fontStyle: FontStyle.italic),
                  ),
                ),
              ),
            );
          } else if (item is _SectionItem) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.title != null && item.title!.isNotEmpty)
                    Text(
                      item.title!,
                      style: const TextStyle(
                        fontSize: 18, 
                        fontWeight: FontWeight.bold,
                        color: Colors.blueAccent
                      ),
                    ),
                  if (item.context != null && item.context!.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        border: Border.all(color: Colors.amber.shade200),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        item.context!,
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.brown.shade800,
                          height: 1.4
                        ),
                      ),
                    ),
                ],
              ),
            );
          } else if (item is _QuestionItem) {
            final q = item.question;
            final qTitle = q.number != null ? "Q${q.number}" : "Question";
            final marks = q.marks != null ? "(${q.marks})" : "";

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              elevation: 2,
              child: ListTile(
                title: Text("$qTitle $marks", style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    q.prompt + (q.body.isNotEmpty ? "..." : ""),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SingleQuestionScreen(
                        question: q,
                        contextText: item.context, // Pass context if available
                        ttsService: widget.ttsService,
                      ),
                    ),
                  );
                },
              ),
            );
          }
          return const SizedBox.shrink();
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _onAddPage(context),
        icon: const Icon(Icons.add_a_photo),
        label: const Text('Add Page'),
      ),
    );
  }
  Future<void> _onAddPage(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('gemini_api_key');
    
    if (context.mounted) {
       showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Process New Page"),
          content: Text(apiKey != null && apiKey.isNotEmpty 
              ? "Gemini API Key detected. Would you like to use Gemini AI for superior accuracy?" 
              : "No Gemini API Key found. Using standard Local OCR."),
          actions: [
            if (apiKey != null && apiKey.isNotEmpty)
              TextButton(
                onPressed: () {
                   Navigator.pop(ctx);
                   _processWithGemini(context, apiKey!);
                },
                child: const Text("Use Gemini AI"),
              ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Local Processing unimplemented context...")));
              },
              child: Text(apiKey != null && apiKey.isNotEmpty ? "Use Local OCR" : "Proceed"),
            ),
          ],
        ),
      );
    }
  }



  Future<void> _savePaper(BuildContext context) async {
    try {
      await _storageService.saveDocument(_document);
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Paper saved successfully!")),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to save: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }
}

// Helper classes for ListView
abstract class _ListItem {}

class _HeaderItem extends _ListItem {
  final String text;
  _HeaderItem(this.text);
}

class _SectionItem extends _ListItem {
  final String? title;
  final String? context;
  _SectionItem(this.title, this.context);
}

class _QuestionItem extends _ListItem {
  final ParsedQuestion question;
  final String? context; // Context from the parent section
  _QuestionItem(this.question, this.context);
}



class SingleQuestionScreen extends StatefulWidget {
  final ParsedQuestion question;
  final String? contextText; // Clean text for reading
  final TtsService ttsService;

  const SingleQuestionScreen({
    super.key,
    required this.question,
    this.contextText,
    required this.ttsService,
  });

  @override
  State<SingleQuestionScreen> createState() => _SingleQuestionScreenState();
}

class _SingleQuestionScreenState extends State<SingleQuestionScreen> {
  // States:
  // Stopped: _isReading = false, _isPaused = false
  // Reading: _isReading = true, _isPaused = false
  // Paused:  _isReading = true, _isPaused = true (User logic: "Stop" button puts it here)
  
  bool _isReading = false;
  bool _isPaused = false;

  double _currentSpeed = 0.5;
  bool _playContext = false; // State for playing context
  
  final SttService _sttService = SttService();
  bool _isListening = false;
  final TextEditingController _answerController = TextEditingController();


  void _startListening() async {
    // 1. Check availability
    bool available = _sttService.isAvailable;
    if (!available) {
       // Attempt re-init just in case
       available = await _sttService.init();
    }

    if (!available) {
      widget.ttsService.speak("Microphone not available.");
      return;
    }

    // 2. Give auditory feedback
    await widget.ttsService.speak("Listening."); 
    await Future.delayed(const Duration(milliseconds: 800));

    setState(() {
      _isListening = true;
      _textBeforeListening = _answerController.text; // Snapshot current text
    });

    await _sttService.startListening(
      localeId: 'en_US', 
      onResult: (text) {
        if (!mounted) return;
        setState(() {
          // Accumulate text: Base + New Session Text
          // Note: 'text' from STT is the cumulative result of THIS session.
          // So we always add it to the _textBeforeListening.
          String spacer = (_textBeforeListening.isNotEmpty && text.isNotEmpty) ? " " : "";
          String combined = "$_textBeforeListening$spacer$text";
          
          widget.question.answer = combined;
          _answerController.text = combined;
          _answerController.selection = TextSelection.fromPosition(
            TextPosition(offset: _answerController.text.length),
          );
        });
      },
    );
  }

  void _stopListening() async {
    // Manual stop
    if (_isListening) {
      setState(() => _isListening = false);
      await _sttService.stopListening();
      
      // Small delay to allow STT to finalize any pending partial results
      await Future.delayed(const Duration(milliseconds: 600));
      _onDictationFinished();
    }
  }
  
  String _textBeforeListening = ""; 

  void _onDictationFinished() async {
     String answer = _answerController.text.trim();
     if (answer.isEmpty) {
       widget.ttsService.speak("No answer detected.");
       return;
     }

     // Read back and show dialog simultaneously
     widget.ttsService.speak("You wrote: $answer. Is this correct?");
     
     if (mounted) {
       _showConfirmationDialog(answer);
     }
  }

  Future<void> _showConfirmationDialog(String answer) async {
    await showDialog(
      context: context,
      barrierDismissible: false, // Force choice
      builder: (ctx) => AlertDialog(
        title: const Text("Confirm Answer"),
        content: Text("You wrote:\n\n$answer"),
        actions: [
          TextButton(
            onPressed: () {
               Navigator.pop(ctx);
               // Retry logic
               setState(() {
                 _answerController.text = ""; 
                 widget.question.answer = "";
               });
               _startListening();
            },
            child: const Text("Retry (Clear & Record)"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.ttsService.speak("Answer saved.");
            },
            child: const Text("Yes, Confirm"),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    // Stop any ongoing TTS and load settings
    _stopAndInit();
    // Initialize answer controller
    _answerController.text = widget.question.answer;
  }

  Future<void> _stopAndInit() async {
    // Ensure TTS stops before doing anything else
    await widget.ttsService.stop();
    await _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await widget.ttsService.loadPreferences();
    if (mounted) {
      setState(() {
        _currentSpeed = prefs['speed'] ?? 0.5;
      });
    }
  }

  @override
  void dispose() {
    _answerController.dispose();
    widget.ttsService.stop(); // Stop immediately on exit
    super.dispose();
  }

  String get _fullText {
    final sb = StringBuffer();
    // 1. Prepend Context if enabled and available
    if (_playContext && widget.contextText != null && widget.contextText!.isNotEmpty) {
       sb.write("Context: ${widget.contextText}. ");
       sb.write("\n\n");
    }

    if (widget.question.number != null) sb.write("Question ${widget.question.number}. ");
    sb.write(widget.question.prompt);
    sb.write("\n");
    sb.write(widget.question.body.join("\n"));
    return sb.toString();
  }

  int _lastSpeechStartOffset = 0; // Tracks the absolute offset in the text where the LAST chunk started
  
  int get _currentAbsolutePosition {
    // Current absolute = Offset of current chunk + Progress within current chunk
    return _lastSpeechStartOffset + widget.ttsService.currentWordStart;
  }

  Future<void> _speakFromPosition(int start) async {
      String textToSpeak = _fullText;
      if (start > 0 && start < textToSpeak.length) {
         textToSpeak = textToSpeak.substring(start);
      }
      
      // Update offset for this new chunk
      _lastSpeechStartOffset = start;
      
      setState(() {
       _isReading = true; 
       _isPaused = false;
      });
      
      await widget.ttsService.speakAndWait(textToSpeak);
      
      if (mounted) {
        // Only reset if we are NOT paused. 
        // If we were paused by _onStopPressed, _isPaused will be true.
        if (!_isPaused) {
          setState(() {
            _isReading = false;
            // _isPaused = false; // Already false if we are here
          });
        }
      }
  }

  void _onReadPressed() async {
    if (_isPaused) {
       // Resume from tracked position
       await _speakFromPosition(_lastSpeechStartOffset); 
    } else {
       // Start fresh
       _lastSpeechStartOffset = 0;
       await _speakFromPosition(0);
    }
  }

  void _onStopPressed() async {
    if (!_isPaused) {
      // Pause action
      
      // Capture current position before pausing/stopping
      int currentPos = _currentAbsolutePosition;
      
      setState(() {
        _isPaused = true;
        _lastSpeechStartOffset = currentPos; // Save for resume
      });
      
      await widget.ttsService.stop(); // Stop completely
      
    } else {
      // Restart action
      await widget.ttsService.stop(); 
      setState(() {
        _isPaused = false;
        _lastSpeechStartOffset = 0;
      });
      // Start fresh
      _onReadPressed();
    }
  }
  
  void _changeSpeed() async {
    // Cycle: 0.5 -> 0.75 -> 1.0 -> 1.25 -> 1.5 -> 0.5
    double newSpeed = _currentSpeed + 0.25;
    if (newSpeed > 1.5) newSpeed = 0.5;
    
    // Capture absolute position BEFORE stopping
    int currentPos = _currentAbsolutePosition;
    
    // Check state
    bool wasReading = _isReading && !_isPaused;
    bool wasPaused = _isPaused;

    // Stop to apply settings safely
    await widget.ttsService.stop(); 
    
    // Update setting
    setState(() => _currentSpeed = newSpeed);
    await widget.ttsService.setSpeed(newSpeed);
    await widget.ttsService.savePreferences(speed: newSpeed, volume: 0.7);

    if (wasReading) {
       // Auto-resume if we were actively reading
       await _speakFromPosition(currentPos);
    } else if (wasPaused) {
       // Just update offset so Resume works correctly
       _lastSpeechStartOffset = currentPos;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Labels logic:
    // If Reading (and not paused): Read="Scanning..."(disabled?), Stop="Stop"
    // Wait, user said "Read button should say Resume".
    // State: Reading (Active) -> Read="Reading", Stop="Stop"
    // State: Paused -> Read="Resume", Stop="Restart"
    // State: Idle -> Read="Read", Stop="Stop"(Disabled?) or Hidden?
    
    String readLabel = "Read";
    IconData readIcon = Icons.volume_up;
    VoidCallback? onRead = _onReadPressed;

    String stopLabel = "Stop";
    IconData stopIcon = Icons.stop;
    VoidCallback? onStop = _onStopPressed;

    if (_isReading && !_isPaused) {
      readLabel = "Reading...";
      readIcon = Icons.volume_up;
      onRead = null; // Disable read button while reading? Or allow it to Restart?
      // User didn't specify, but typically disabled.
      
      stopLabel = "Stop"; // Acts as Pause based on user request
      onStop = _onStopPressed;
    } else if (_isPaused) {
      readLabel = "Resume";
      readIcon = Icons.play_arrow;
      
      stopLabel = "Restart";
      stopIcon = Icons.replay;
    } else {
      // Idle
      readLabel = "Read";
      onStop = null; // Can't stop if not playing
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Question Detail")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.contextText != null && widget.contextText!.isNotEmpty) ...[
                       Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          border: Border.all(color: Colors.amber.shade200),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Shared Context:",
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.amber.shade900
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.contextText!,
                              style: const TextStyle(fontSize: 15, height: 1.4),
                            ),
                            SwitchListTile(
                              title: const Text("Read this context too?", style: TextStyle(fontSize: 14)),
                              value: _playContext, 
                              onChanged: (val) {
                                setState(() => _playContext = val);
                              },
                              contentPadding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                            )
                          ],
                        ),
                       ),
                       const SizedBox(height: 16),
                    ],

                    if (widget.question.number != null)
                      Text(
                        "Question ${widget.question.number}",
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                    if (widget.question.marks != null)
                      Text(
                        "Marks: ${widget.question.marks}",
                        style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade700,
                            fontStyle: FontStyle.italic),
                      ),
                    const SizedBox(height: 16),
                    Text(
                      widget.question.prompt,
                      style: const TextStyle(fontSize: 18),
                    ),
                    const SizedBox(height: 8),
                    ..._buildBodyWidgets(widget.question.body),
                  ],
                ),
              ),
            ),
            // Controls
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Read / Resume
                ElevatedButton.icon(
                  onPressed: onRead,
                  icon: Icon(readIcon),
                  label: Text(readLabel),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
                
                // Stop / Restart
                ElevatedButton.icon(
                  onPressed: onStop,
                  icon: Icon(stopIcon),
                  label: Text(stopLabel),
                   style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    backgroundColor: _isPaused ? Colors.orangeAccent : Colors.redAccent,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Speed Control
            ElevatedButton.icon(
              onPressed: _changeSpeed,
              icon: const Icon(Icons.speed),
              label: Text("Speed: ${_currentSpeed.toStringAsFixed(2)}x"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueGrey.shade100,
                foregroundColor: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }


  List<Widget> _buildBodyWidgets(List<String> body) {
    List<Widget> widgets = [];
    List<String> currentBoxItems = [];
    String? currentBoxTitle;
    bool inBox = false;

    for (var i = 0; i < body.length; i++) {
        final line = body[i];
        final trimmed = line.trim();

        if (trimmed.startsWith("[[BOX:") && trimmed.endsWith("]]")) {
            if (inBox) {
               widgets.add(_buildBoxWidget(currentBoxTitle, currentBoxItems));
               currentBoxItems = [];
            }
            inBox = true;
            currentBoxTitle = trimmed.substring(6, trimmed.length - 2).trim(); 
        } else if (trimmed == "[[BOX END]]") {
            if (inBox) {
                widgets.add(_buildBoxWidget(currentBoxTitle, currentBoxItems));
                inBox = false;
                currentBoxItems = [];
                currentBoxTitle = null;
            }
        } else {
            if (inBox) {
                currentBoxItems.add(line);
            } else {
                if (line.startsWith("Word Box:")) {
                   widgets.add(_buildBoxWidget("Word Box", [line.replaceFirst("Word Box:", "")]));
                } else {
                   widgets.add(Padding(
                     padding: const EdgeInsets.only(bottom: 4),
                     child: Text(line, style: const TextStyle(fontSize: 16)),
                   ));
                }
            }
        }
    }
    
    if (inBox && currentBoxItems.isNotEmpty) {
        widgets.add(_buildBoxWidget(currentBoxTitle, currentBoxItems));
    }
    
    return widgets;
  }

  Widget _buildBoxWidget(String? title, List<String> items) {
    return Container(
       width: double.infinity,
       margin: const EdgeInsets.symmetric(vertical: 8),
       decoration: BoxDecoration(
         color: Colors.white,
         border: Border.all(color: Colors.blueGrey.shade300),
         borderRadius: BorderRadius.circular(8),
         boxShadow: [
            BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))
         ]
       ),
       child: Column(
         crossAxisAlignment: CrossAxisAlignment.stretch,
         children: [
            Container(
               padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
               decoration: BoxDecoration(
                  color: Colors.blueGrey.shade50,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                  border: Border(bottom: BorderSide(color: Colors.blueGrey.shade200))
               ),
               child: Text(
                  title ?? "Box",
                  style: TextStyle(
                     fontSize: 14, 
                     fontWeight: FontWeight.bold,
                     color: Colors.blueGrey.shade800
                  ),
               ),
            ),
            Padding(
               padding: const EdgeInsets.all(12.0),
               child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: items.map((item) => Padding(
                     padding: const EdgeInsets.only(bottom: 4),
                     child: Text(item, style: const TextStyle(fontSize: 15, height: 1.3)),
                  )).toList(),
               ),
            ),
         ],
       ),
    );
  }
}
