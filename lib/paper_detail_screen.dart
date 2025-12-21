import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'services/gemini_question_service.dart';
import 'services/question_storage_service.dart';
import 'models/question_model.dart';
import 'services/tts_service.dart';
import 'dart:convert';
import 'services/stt_service.dart';
import 'services/audio_recorder_service.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';

// --- PAPER DETAIL SCREEN ---

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
    final items = <_ListItem>[];
    
    if (_document.header.isNotEmpty) {
      items.add(_HeaderItem(_document.header.join("\n")));
    }

    for (var section in _document.sections) {
      if ((section.title != null && section.title!.isNotEmpty) || 
          (section.context != null && section.context!.isNotEmpty)) {
        items.add(_SectionItem(section.title, section.context));
      }
      
      for (var q in section.questions) {
        items.add(_QuestionItem(q, section.context));
      }
    }

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
                        contextText: item.context,
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

// --- HELPER CLASSES ---

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
  final String? context;
  _QuestionItem(this.question, this.context);
}

// --- SINGLE QUESTION SCREEN ---

class SingleQuestionScreen extends StatefulWidget {
  final ParsedQuestion question;
  final String? contextText; 
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
  bool _isReading = false;
  bool _isPaused = false;
  
  // Mapped Speed: 1.0 (Display) = 0.5 (Engine)
  double _displaySpeed = 1.0; 
  double _currentVolume = 1.0;
  bool _playContext = false;

  final SttService _sttService = SttService(); 
  bool _isListening = false;
  final TextEditingController _answerController = TextEditingController();

  final AudioRecorderService _audioRecorderService = AudioRecorderService();
  bool _isProcessingAudio = false;
  String? _tempAudioPath;
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _stopAndInit();
    _answerController.text = widget.question.answer;
    _answerController.addListener(() {
      widget.question.answer = _answerController.text;
    });
  }

  Future<void> _stopAndInit() async {
    await widget.ttsService.stop();
    await _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await widget.ttsService.loadPreferences();
    if (mounted) {
      setState(() {
        _displaySpeed = prefs['speed'] ?? 1.0;
        _currentVolume = prefs['volume'] ?? 1.0;
      });
      // Apply mapped speed to engine
      await widget.ttsService.setSpeed(_displaySpeed * 0.5);
      await widget.ttsService.setVolume(_currentVolume);
    }
  }

  @override
  void dispose() {
    _answerController.dispose();
    widget.ttsService.stop();
    _audioPlayer.dispose();
    super.dispose();
  }

  // --- VOLUME LOGIC ---
  void _changeVolume() async {
    double newVolume = _currentVolume + 0.2;
    if (newVolume > 1.01) newVolume = 0.2;

    int currentPos = _currentAbsolutePosition;
    bool wasReading = _isReading && !_isPaused;
    bool wasPaused = _isPaused;

    await widget.ttsService.stop(); 
    
    setState(() => _currentVolume = newVolume);
    await widget.ttsService.setVolume(newVolume);
    await widget.ttsService.savePreferences(speed: _displaySpeed, volume: newVolume);

    if (wasReading) {
        await _speakFromPosition(currentPos);
    } else if (wasPaused) {
        _lastSpeechStartOffset = currentPos;
    }
  }

  // --- SPEED LOGIC ---
  void _changeSpeed() async {
    double nextDisplaySpeed = _displaySpeed + 0.25;
    if (nextDisplaySpeed > 1.75) {
      nextDisplaySpeed = 0.5;
    }
    
    int currentPos = _currentAbsolutePosition;
    bool wasReading = _isReading && !_isPaused;
    bool wasPaused = _isPaused;

    await widget.ttsService.stop(); 
    
    setState(() => _displaySpeed = nextDisplaySpeed);
    
    // Engine gets Display * 0.5
    await widget.ttsService.setSpeed(nextDisplaySpeed * 0.5);
    await widget.ttsService.savePreferences(speed: nextDisplaySpeed, volume: _currentVolume);

    if (wasReading) {
        await _speakFromPosition(currentPos);
    } else if (wasPaused) {
        _lastSpeechStartOffset = currentPos;
    }
  }

  String get _fullText {
    final sb = StringBuffer();
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

  int _lastSpeechStartOffset = 0;
  int get _currentAbsolutePosition => _lastSpeechStartOffset + widget.ttsService.currentWordStart;

  Future<void> _speakFromPosition(int start) async {
      String textToSpeak = _fullText;
      if (start > 0 && start < textToSpeak.length) {
          textToSpeak = textToSpeak.substring(start);
      }
      _lastSpeechStartOffset = start;
      setState(() {
       _isReading = true; 
       _isPaused = false;
      });
      await widget.ttsService.speakAndWait(textToSpeak);
      if (mounted && !_isPaused) {
          setState(() => _isReading = false);
      }
  }

  void _onReadPressed() async {
    if (_isPaused) {
       await _speakFromPosition(_lastSpeechStartOffset); 
    } else {
       _lastSpeechStartOffset = 0;
       await _speakFromPosition(0);
    }
  }

  void _onStopPressed() async {
    if (!_isPaused) {
      int currentPos = _currentAbsolutePosition;
      setState(() {
        _isPaused = true;
        _lastSpeechStartOffset = currentPos;
      });
      await widget.ttsService.stop();
    } else {
      await widget.ttsService.stop(); 
      setState(() {
        _isPaused = false;
        _lastSpeechStartOffset = 0;
      });
      _onReadPressed();
    }
  }

  void _startListening() async {
    if (!await _audioRecorderService.hasPermission()) {
      widget.ttsService.speak("Microphone permission needed.");
      return;
    }
    await widget.ttsService.speak("Listening.");
    await Future.delayed(const Duration(milliseconds: 600));
    final tempDir = await getTemporaryDirectory();
    _tempAudioPath = '${tempDir.path}/temp_answer_${DateTime.now().millisecondsSinceEpoch}.m4a';
    try {
      await _audioRecorderService.startRecording(_tempAudioPath!);
      setState(() {
        _isListening = true;
        _isProcessingAudio = false;
      });
    } catch (e) { widget.ttsService.speak("Failed to start recording."); }
  }

  void _stopListening() async {
    if (_isListening) {
      final path = await _audioRecorderService.stopRecording();
      setState(() { _isListening = false; _isProcessingAudio = true; });
      if (path == null) {
        widget.ttsService.speak("Recording failed.");
        setState(() => _isProcessingAudio = false);
        return;
      }
      await _processAudioAnswer(path);
    }
  }

  Future<void> _processAudioAnswer(String audioPath) async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('gemini_api_key');
    String transcribedText = "";
    if (apiKey != null && apiKey.isNotEmpty) {
        try {
          final geminiService = GeminiQuestionService();
          transcribedText = await geminiService.transcribeAudio(audioPath, apiKey);
        } catch (e) { transcribedText = "[Transcription Failed: $e]"; }
    } else {
        transcribedText = "[No API Key - Audio Saved. Type answer manually.]";
        widget.ttsService.speak("No API Key found. Audio saved, please type answer.");
    }
    if (!mounted) return;
    setState(() {
      _isProcessingAudio = false;
      _answerController.text = transcribedText;
    });
    await Future.delayed(const Duration(milliseconds: 100));
    _onDictationFinished();
  }

  void _onDictationFinished() async {
     String answer = _answerController.text.trim();
     widget.ttsService.speak("You wrote: $answer. Is this correct?");
     if (mounted) { _showConfirmationDialog(answer); }
  }

  Future<void> _showConfirmationDialog(String answer) async {
    await showDialog(
      context: context,
      barrierDismissible: false, 
      builder: (ctx) => AlertDialog(
        title: const Text("Confirm Answer"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("You wrote:\n\n$answer"),
            if (_tempAudioPath != null)
              TextButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text("Play Preview"),
                onPressed: () async {
                  await _audioPlayer.play(DeviceFileSource(_tempAudioPath!));
                },
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
               Navigator.pop(ctx);
               _discardAudio();
               setState(() { _answerController.text = ""; });
               _startListening();
            },
            child: const Text("Retry"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _handleConfirmedAnswer();
              widget.ttsService.speak("Answer saved.");
            },
            child: const Text("Confirm"),
          ),
        ],
      ),
    );
  }

  void _discardAudio() {
    if (_tempAudioPath != null) {
      final file = File(_tempAudioPath!);
      if (file.existsSync()) file.deleteSync();
      _tempAudioPath = null;
    }
  }

  Future<void> _handleConfirmedAnswer() async {
    widget.question.answer = _answerController.text;
    if (_tempAudioPath != null) {
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final fileName = 'answer_q${widget.question.number ?? "x"}_${DateTime.now().millisecondsSinceEpoch}.m4a';
        final permPath = '${appDir.path}/$fileName';
        await File(_tempAudioPath!).copy(permPath);
        setState(() { widget.question.audioPath = permPath; });
        _discardAudio(); 
      } catch (e) { print("Error saving audio: $e"); }
    }
  }

  @override
  Widget build(BuildContext context) {
    String readLabel = _isPaused ? "Resume" : (_isReading ? "Reading..." : "Read");
    IconData readIcon = _isPaused ? Icons.play_arrow : Icons.volume_up;
    VoidCallback? onRead = (_isReading && !_isPaused) ? null : _onReadPressed;

    String stopLabel = _isPaused ? "Restart" : "Stop";
    IconData stopIcon = _isPaused ? Icons.replay : Icons.stop;
    VoidCallback? onStop = (!_isReading && !_isPaused) ? null : _onStopPressed;

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
                            Text("Shared Context:", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
                            const SizedBox(height: 4),
                            Text(widget.contextText!, style: const TextStyle(fontSize: 15, height: 1.4)),
                            SwitchListTile(
                              title: const Text("Read this context too?", style: TextStyle(fontSize: 14)),
                              value: _playContext, 
                              onChanged: (val) => setState(() => _playContext = val),
                              contentPadding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                            )
                          ],
                        ),
                       ),
                       const SizedBox(height: 16),
                    ],
                    if (widget.question.number != null)
                      Text("Question ${widget.question.number}", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    if (widget.question.marks != null)
                      Text("Marks: ${widget.question.marks}", style: TextStyle(fontSize: 14, color: Colors.grey.shade700, fontStyle: FontStyle.italic)),
                    const SizedBox(height: 16),
                    Text(widget.question.prompt, style: const TextStyle(fontSize: 18)),
                    const SizedBox(height: 8),
                    ..._buildBodyWidgets(widget.question.body),
                    const SizedBox(height: 24),
                    const Divider(),
                    const Text("Your Answer:", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _answerController,
                      maxLines: 5,
                      decoration: InputDecoration(
                        hintText: "Type or detect answer...",
                        border: const OutlineInputBorder(),
                        suffixIcon: _isProcessingAudio 
                          ? const Padding(padding: EdgeInsets.all(12.0), child: CircularProgressIndicator(strokeWidth: 2))
                          : IconButton(
                              icon: Icon(_isListening ? Icons.stop : Icons.mic),
                              color: _isListening ? Colors.red : Colors.grey,
                              onPressed: _isListening ? _stopListening : _startListening,
                            ),
                      ),
                    ),
                    if (widget.question.audioPath != null && widget.question.audioPath!.isNotEmpty)
                       Padding(
                         padding: const EdgeInsets.symmetric(vertical: 8.0),
                         child: OutlinedButton.icon(
                           icon: const Icon(Icons.play_circle_fill),
                           label: const Text("Play Saved Answer"),
                           onPressed: () async => await _audioPlayer.play(DeviceFileSource(widget.question.audioPath!)),
                         ),
                       ),
                  ],
                ),
              ),
            ),
            
            // Audio Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: onRead,
                  icon: Icon(readIcon),
                  label: Text(readLabel),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                ),
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

            // Speed and Volume Controls
            Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4.0),
                    child: ElevatedButton.icon(
                      onPressed: _changeSpeed,
                      icon: const Icon(Icons.speed, size: 18),
                      label: Text("${_displaySpeed.toStringAsFixed(2)}x"),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey.shade100, foregroundColor: Colors.black87),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4.0),
                    child: ElevatedButton.icon(
                      onPressed: _changeVolume,
                      icon: Icon(_currentVolume < 0.5 ? Icons.volume_down : Icons.volume_up, size: 18),
                      label: Text("Vol: ${(_currentVolume * 100).toInt()}%"),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey.shade100, foregroundColor: Colors.black87),
                    ),
                  ),
                ),
              ],
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
    for (var line in body) {
        final trimmed = line.trim();
        if (trimmed.startsWith("[[BOX:") && trimmed.endsWith("]]")) {
            if (inBox) widgets.add(_buildBoxWidget(currentBoxTitle, currentBoxItems));
            inBox = true;
            currentBoxTitle = trimmed.substring(6, trimmed.length - 2).trim(); 
            currentBoxItems = [];
        } else if (trimmed == "[[BOX END]]") {
            if (inBox) { widgets.add(_buildBoxWidget(currentBoxTitle, currentBoxItems)); inBox = false; }
        } else {
            if (inBox) { currentBoxItems.add(line); } 
            else { widgets.add(Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(line, style: const TextStyle(fontSize: 16)))); }
        }
    }
    if (inBox) widgets.add(_buildBoxWidget(currentBoxTitle, currentBoxItems));
    return widgets;
  }

  Widget _buildBoxWidget(String? title, List<String> items) {
    return Container(
        width: double.infinity, margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.blueGrey.shade300), borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.blueGrey.shade50, borderRadius: const BorderRadius.vertical(top: Radius.circular(8))), child: Text(title ?? "Box", style: const TextStyle(fontWeight: FontWeight.bold))),
            Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: items.map((i) => Text(i)).toList())),
        ]),
    );
  }
}