import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaamos_mail/src/core/html_sanitizer.dart';
import 'package:kaamos_mail/src/core/models.dart';

void main() {
  const sanitizer = HtmlSanitizer();

  String clean(String html, {bool allowRemote = false}) =>
      sanitizer.sanitize(html, allowRemote: allowRemote).document;

  test('toglie script, iframe, form con tutto il contenuto', () {
    final doc = clean(
      '<p>ok</p><script>alert(1)</script><iframe src="x"></iframe>'
      '<form><input name="pwd"></form>',
    );
    expect(doc, contains('<p>ok</p>'));
    expect(doc, isNot(contains('alert')));
    expect(doc, isNot(contains('iframe')));
    expect(doc, isNot(contains('pwd')));
  });

  test('toglie gli attributi on* e i link javascript:', () {
    final doc = clean(
      '<a href="javascript:alert(1)" onclick="x()">a</a>'
      '<a href="https://kaamos.dev">b</a><img src="x" onerror="y()">',
    );
    expect(doc, isNot(contains('javascript:')));
    expect(doc, isNot(contains('onclick')));
    expect(doc, isNot(contains('onerror')));
    expect(doc, contains('href="https://kaamos.dev"'));
  });

  test('blocca le immagini remote e le conta', () {
    final r = sanitizer.sanitize(
      '<img src="https://track.er/p.gif">'
      '<div style="background: url(https://track.er/bg.png)">x</div>',
    );
    expect(r.blockedRemote, 2);
    expect(r.document, isNot(contains('track.er')));
  });

  test('con allowRemote le immagini restano', () {
    final r = sanitizer.sanitize(
      '<img src="https://esempio.org/foto.jpg">',
      allowRemote: true,
    );
    expect(r.blockedRemote, 0);
    expect(r.document, contains('https://esempio.org/foto.jpg'));
  });

  test('cid: diventa data: con le immagini interne', () {
    final r = sanitizer.sanitize(
      '<img src="cid:logo@x">',
      inlineImages: {
        'logo@x': InlineImage(
          mimeType: 'image/png',
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
      },
    );
    expect(r.document, contains('src="data:image/png;base64,AQID"'));
  });

  test('la pagina ha la CSP e niente referrer', () {
    final doc = clean('<p>x</p>');
    expect(doc, contains('Content-Security-Policy'));
    expect(doc, contains("default-src 'none'"));
    expect(doc, contains('no-referrer'));
  });

  test('CSS pericoloso viene tolto', () {
    final doc = clean(
      '<style>@import url(https://x.y/a.css); p { width: expression(alert(1)) }</style>'
      '<p style="color: red">x</p>',
    );
    expect(doc, isNot(contains('@import')));
    expect(doc, isNot(contains('expression(')));
    expect(doc, contains('color: red'));
  });
}
