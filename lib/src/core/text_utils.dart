import 'package:html/parser.dart' as html_parser;

import 'models.dart';

/// Funzioni pure sul testo: niente rete, niente UI. Per questo sono le più
/// facili da testare (vedi `test/text_utils_test.dart`).

/// Riduce un testo all'anteprima di una riga: niente citazioni, spazi
/// compressi, al massimo [maxLength] caratteri.
String makePreview(String text, {int maxLength = 160}) {
  final lines = text
      .split(RegExp(r'\r?\n'))
      .map((l) => l.trim())
      // Le righe citate ("> ...") e le firme non dicono niente di nuovo.
      .takeWhile((l) => l != '--' && l != '-- ')
      .where((l) => l.isNotEmpty && !l.startsWith('>'));
  final joined = lines.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (joined.length <= maxLength) return joined;
  return '${joined.substring(0, maxLength).trimRight()}…';
}

/// Il testo visibile di un HTML, per le anteprime. Non serve a mostrare il
/// messaggio (per quello c'è la WebView).
String htmlToText(String html) {
  final document = html_parser.parse(html);
  document
      .querySelectorAll('style, script, head, title')
      .forEach((e) => e.remove());
  for (final br in document.querySelectorAll('br')) {
    br.replaceWith(document.createElement('span')..text = '\n');
  }
  for (final block in document.querySelectorAll('p, div, tr, li, h1, h2, h3')) {
    block.append(document.createElement('span')..text = '\n');
  }
  return (document.body?.text ?? '').replaceAll(' ', ' ');
}

/// Mette tra virgolette una stringa per un comando IMAP SEARCH.
String imapQuote(String value) {
  final escaped = value
      .replaceAll(RegExp(r'[\r\n]'), ' ')
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"');
  return '"$escaped"';
}

/// Toglie `<` e `>` da un Content-ID o Message-ID.
String stripAngles(String value) {
  var v = value.trim();
  if (v.startsWith('<')) v = v.substring(1);
  if (v.endsWith('>')) v = v.substring(0, v.length - 1);
  return v;
}

/// Gli id in un header `References` o `In-Reply-To`.
List<String> parseMessageIds(String? header) {
  if (header == null) return const [];
  return [
    for (final m in RegExp(r'<[^<>\s]+>').allMatches(header)) m.group(0)!,
  ];
}

/// Ordine delle cartelle: prima quelle speciali in un ordine fisso, poi le
/// altre in ordine alfabetico.
int compareFolders(Folder a, Folder b) {
  final byRole = a.role.index.compareTo(b.role.index);
  if (byRole != 0) return byRole;
  return a.path.toLowerCase().compareTo(b.path.toLowerCase());
}

/// Nome italiano delle cartelle speciali.
String folderLabel(Folder folder) => switch (folder.role) {
  FolderRole.inbox => 'Posta in arrivo',
  FolderRole.sent => 'Inviati',
  FolderRole.drafts => 'Bozze',
  FolderRole.archive => 'Archivio',
  FolderRole.trash => 'Cestino',
  FolderRole.junk => 'Spam',
  FolderRole.other => folder.name,
};

/// Interpreta una lista di indirizzi scritta a mano:
/// `marta@esempio.org, Luca <luca@esempio.org>`.
///
/// Restituisce gli indirizzi validi e le parti che non lo sono, così la UI
/// può segnalare l'errore invece di inviare a un indirizzo sbagliato.
({List<Address> valid, List<String> invalid}) parseAddressList(String input) {
  final valid = <Address>[];
  final invalid = <String>[];
  for (final raw in input.split(RegExp(r'[,;]'))) {
    final item = raw.trim();
    if (item.isEmpty) continue;
    final match = RegExp(r'^(.*?)\s*<([^<>]+)>$').firstMatch(item);
    final email = (match?.group(2) ?? item).trim();
    final name = match?.group(1)?.trim().replaceAll('"', '');
    if (isValidEmail(email)) {
      valid.add(Address(email, (name == null || name.isEmpty) ? null : name));
    } else {
      invalid.add(item);
    }
  }
  return (valid: valid, invalid: invalid);
}

/// Controllo volutamente semplice: qualcosa@dominio.tld senza spazi.
/// La validazione vera la fa il server SMTP.
bool isValidEmail(String value) =>
    RegExp(r'^[^@\s<>]+@[^@\s<>]+\.[^@\s<>]+$').hasMatch(value);

/// "Re: " davanti all'oggetto, senza raddoppiarlo.
String replySubject(String subject) =>
    RegExp(r'^\s*re\s*:', caseSensitive: false).hasMatch(subject)
    ? subject
    : 'Re: $subject';

/// "Fwd: " davanti all'oggetto, senza raddoppiarlo.
String forwardSubject(String subject) =>
    RegExp(r'^\s*(fwd?|i)\s*:', caseSensitive: false).hasMatch(subject)
    ? subject
    : 'Fwd: $subject';

/// Il testo da citare di un messaggio: la parte testo se c'è, altrimenti
/// il testo ricavato dall'HTML.
String quotableText(MessageContent message) {
  final plain = message.plainText;
  if (plain != null && plain.trim().isNotEmpty) return plain.trimRight();
  final html = message.html;
  if (html == null) return '';
  return htmlToText(html)
      .split('\n')
      .map((l) => l.trimRight())
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

/// Il corpo di una risposta: due righe vuote per scrivere, poi la citazione
/// con `>` davanti a ogni riga.
String replyBody(MessageContent original) {
  final from = original.summary.from?.label ?? 'Qualcuno';
  final date = original.summary.date;
  final when = date == null ? '' : 'Il ${formatFullDate(date)} ';
  final quoted = quotableText(
    original,
  ).split('\n').map((l) => l.isEmpty ? '>' : '> $l').join('\n');
  return '\n\n$when$from ha scritto:\n$quoted\n';
}

/// Il corpo di un inoltro: intestazione del messaggio originale e testo.
String forwardBody(MessageContent original) {
  final s = original.summary;
  final buffer = StringBuffer('\n\n---------- Messaggio inoltrato ----------\n')
    ..writeln('Da: ${s.from ?? ''}');
  if (s.date != null) buffer.writeln('Data: ${formatFullDate(s.date!)}');
  buffer
    ..writeln('Oggetto: ${s.subject}')
    ..writeln('A: ${s.to.join(', ')}');
  if (original.cc.isNotEmpty) buffer.writeln('Cc: ${original.cc.join(', ')}');
  buffer
    ..writeln()
    ..writeln(quotableText(original));
  return buffer.toString();
}

const _months = [
  'gen',
  'feb',
  'mar',
  'apr',
  'mag',
  'giu',
  'lug',
  'ago',
  'set',
  'ott',
  'nov',
  'dic',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// Data breve per la lista: ora se è oggi, "Ieri", altrimenti giorno e
/// mese (più l'anno se non è quello corrente).
String formatListDate(DateTime date, {DateTime? now}) {
  final local = date.toLocal();
  final today = now ?? DateTime.now();
  final startOfToday = DateTime(today.year, today.month, today.day);
  final startOfDate = DateTime(local.year, local.month, local.day);
  final days = startOfToday.difference(startOfDate).inDays;
  if (days == 0) return '${_two(local.hour)}:${_two(local.minute)}';
  if (days == 1) return 'Ieri';
  final dayMonth = '${local.day} ${_months[local.month - 1]}';
  return local.year == today.year ? dayMonth : '$dayMonth ${local.year}';
}

/// Data completa, es. "26 nov 2026, 10:42".
String formatFullDate(DateTime date) {
  final l = date.toLocal();
  return '${l.day} ${_months[l.month - 1]} ${l.year}, '
      '${_two(l.hour)}:${_two(l.minute)}';
}

/// Dimensione leggibile: "84 KB", "1,2 MB".
String formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  final mb = bytes / (1024 * 1024);
  return '${mb.toStringAsFixed(1).replaceAll('.', ',')} MB';
}

/// Iniziali per l'avatar: "Marta Bianchi" → "MB".
String initials(String label) {
  final words = label
      .replaceAll(RegExp(r'[<>"@].*'), '')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return label.isEmpty ? '?' : label[0].toUpperCase();
  if (words.length == 1) {
    return words.first
        .substring(0, words.first.length.clamp(0, 2))
        .toUpperCase();
  }
  return (words.first[0] + words.last[0]).toUpperCase();
}
