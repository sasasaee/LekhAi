
import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import '../models/question_model.dart';
import 'package:flutter/services.dart' show rootBundle;

class PdfService {
  Future<File> generateExamPdf({
    required String studentName,
    required String studentId,
    required String examName,
    required ParsedDocument document,
  }) async {
    final pdf = pw.Document();

    // Load custom font if needed, otherwise use standard
    // For simplicity, using standard sans serif. 
    // If you have a specific font asset, load it here.
    // final font = await rootBundle.load("assets/fonts/OpenSans-Regular.ttf");
    // final ttf = pw.Font.ttf(font);

    // Front Page
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Center(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text("LekhAi Exam Result", style: pw.TextStyle(fontSize: 32, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 50),
                pw.Text("Exam: $examName", style: pw.TextStyle(fontSize: 24)),
                pw.SizedBox(height: 20),
                pw.Divider(),
                pw.SizedBox(height: 20),
                pw.Text("Student Name: $studentName", style: pw.TextStyle(fontSize: 20)),
                pw.SizedBox(height: 10),
                pw.Text("Student ID: $studentId", style: pw.TextStyle(fontSize: 20)),
                pw.SizedBox(height: 50),
                pw.Text("Date: ${DateTime.now().toString().split('.')[0]}", style: pw.TextStyle(fontSize: 16, color: PdfColors.grey)),
              ],
            ),
          );
        },
      ),
    );

    // Content Pages
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Text("Answers", style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(height: 20),
            ...document.sections.expand((section) {
              return [
                if (section.title != null && section.title!.isNotEmpty)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 10, bottom: 5),
                    child: pw.Text(
                      section.title!,
                      style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                if (section.context != null && section.context!.isNotEmpty)
                  pw.Container(
                    margin: const pw.EdgeInsets.only(bottom: 15),
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey100,
                      border: pw.Border.all(color: PdfColors.grey300),
                    ),
                    child: pw.Text(
                       "Context: ${section.context!}",
                       style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700, fontStyle: pw.FontStyle.italic),
                    ),
                  ),
                ...section.questions.map((q) {
                  return pw.Container(
                    margin: const pw.EdgeInsets.only(bottom: 20),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              "${q.number ?? '-'}. ",
                              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
                            ),
                            pw.Expanded(
                              child: pw.Text(
                                q.prompt,
                                style: const pw.TextStyle(fontSize: 14),
                              ),
                            ),
                            if (q.marks != null)
                               pw.Text(" (${q.marks})", style: const pw.TextStyle(fontSize: 12)),
                          ],
                        ),
                        if (q.body.isNotEmpty)
                           pw.Padding(
                             padding: const pw.EdgeInsets.only(left: 15, top: 4),
                             child: pw.Text(q.body.join("\n"), style: const pw.TextStyle(fontSize: 12)),
                           ),
                        pw.SizedBox(height: 8),
                        pw.Container(
                          width: double.infinity,
                          padding: const pw.EdgeInsets.all(8),
                          decoration: pw.BoxDecoration(
                            color: PdfColors.grey50,
                            border: pw.Border.all(color: PdfColors.grey400),
                            borderRadius: pw.BorderRadius.circular(4),
                          ),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                                pw.Text("Answer:", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.grey600)),
                                pw.SizedBox(height: 4),
                                pw.Text(
                                    q.answer.isNotEmpty ? q.answer : "[No Answer Provided]",
                                    style: pw.TextStyle(fontSize: 12, color: q.answer.isNotEmpty ? PdfColors.black : PdfColors.red),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ];
            }).toList(),
          ];
        },
      ),
    );

    // Save File
    final output = await getApplicationDocumentsDirectory();
    final file = File("${output.path}/Exam_${examName.replaceAll(RegExp(r'\s+'), '_')}_${DateTime.now().millisecondsSinceEpoch}.pdf");
    await file.writeAsBytes(await pdf.save());
    return file;
  }
}
