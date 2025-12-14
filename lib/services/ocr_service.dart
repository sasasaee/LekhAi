import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrLine {
  final int index;
  final String text;
  final double l, t, r, b;

  OcrLine({
    required this.index,
    required this.text,
    required this.l,
    required this.t,
    required this.r,
    required this.b,
  });

  Map<String, dynamic> toJson() => {
        "i": index,
        "t": text,
        "l": l,
        "y": t,
        "r": r,
        "b": b,
      };
}

class OcrService {
  final TextRecognizer _textRecognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

  Future<List<OcrLine>> processImageLines(String path) async {
    final inputImage = InputImage.fromFilePath(path);
    final recognizedText = await _textRecognizer.processImage(inputImage);

    final out = <OcrLine>[];
    var idx = 0;

    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        final text = line.text.trim();
        if (text.isEmpty) continue;
        final bb = line.boundingBox;

        out.add(OcrLine(
          index: idx++,
          text: text,
          l: bb.left.toDouble(),
          t: bb.top.toDouble(),
          r: bb.right.toDouble(),
          b: bb.bottom.toDouble(),
        ));
      }
    }
    return out;
  }

  void dispose() => _textRecognizer.close();
}
