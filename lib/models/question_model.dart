class ParsedDocument {
  final List<String> header;
  final List<ParsedSection> sections;
  // Optional: Add timestamp or title if we want to deserialize it here directly
  
  ParsedDocument({required this.header, required this.sections});

  Map<String, dynamic> toJson() => {
    "header": header,
    "sections": sections.map((e) => e.toJson()).toList(),
  };

  factory ParsedDocument.fromJson(Map<String, dynamic> json) {
    return ParsedDocument(
      header: (json['header'] as List?)?.map((e) => e.toString()).toList() ?? [],
      sections: (json['sections'] as List?)
              ?.map((e) => ParsedSection.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class ParsedSection {
  final String? title;
  final String? context; // For shared passages or word boxes
  final List<ParsedQuestion> questions;

  ParsedSection({
    required this.title,
    this.context,
    required this.questions,
  });

  Map<String, dynamic> toJson() => {
    "title": title,
    "context": context,
    "questions": questions.map((e) => e.toJson()).toList(),
  };

  factory ParsedSection.fromJson(Map<String, dynamic> json) {
    return ParsedSection(
      title: json['title'] as String?,
      context: json['context'] as String?,
      questions: (json['questions'] as List?)
              ?.map((e) => ParsedQuestion.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class ParsedQuestion {
  final String? number;
  String prompt; // first line (after number)
  final List<String> body;
  String? marks;
  final List<int> sourceLineIndices;

  ParsedQuestion({
    required this.number,
    required this.prompt,
    required this.body,
    required this.marks,
    required this.sourceLineIndices,
  });

  Map<String, dynamic> toJson() => {
    "number": number,
    "prompt": prompt,
    "body": body,
    "marks": marks,
    "sourceLineIndices": sourceLineIndices,
  };

  factory ParsedQuestion.fromJson(Map<String, dynamic> json) {
    return ParsedQuestion(
      number: json['number'] as String?,
      prompt: json['prompt'] as String? ?? "",
      body: (json['body'] as List?)?.map((e) => e.toString()).toList() ?? [],
      marks: json['marks'] as String?,
      sourceLineIndices:
          (json['sourceLineIndices'] as List?)?.cast<int>() ?? [],
    );
  }
}
