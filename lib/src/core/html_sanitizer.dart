import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'models.dart';

/// Result of cleaning an HTML mail.
class SanitizedHtml {
  /// Creates the result.
  const SanitizedHtml({required this.document, required this.blockedRemote});

  /// The full page to give the WebView, with the Content-Security-Policy.
  final String document;

  /// How many remote resources (images, backgrounds) were blocked. If more than
  /// zero, the UI shows "Load images".
  final int blockedRemote;
}

/// Cleans a mail's HTML before showing it.
///
/// It is the second of three walls (the others: JavaScript off in the WebView
/// and the CSP inside the page). It works as an *allow list*: it keeps only the
/// tags and attributes we know, everything else goes. A deny list ("remove
/// script and iframe") always forgets something.
class HtmlSanitizer {
  /// Creates the sanitizer.
  const HtmlSanitizer();

  static const _allowedTags = {
    'a',
    'abbr',
    'address',
    'article',
    'b',
    'bdi',
    'bdo',
    'big',
    'blockquote',
    'br',
    'caption',
    'center',
    'cite',
    'code',
    'col',
    'colgroup',
    'dd',
    'del',
    'details',
    'dfn',
    'div',
    'dl',
    'dt',
    'em',
    'figcaption',
    'figure',
    'font',
    'footer',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'header',
    'hr',
    'i',
    'img',
    'ins',
    'kbd',
    'li',
    'main',
    'mark',
    'ol',
    'p',
    'pre',
    'q',
    's',
    'samp',
    'section',
    'small',
    'span',
    'strike',
    'strong',
    'style',
    'sub',
    'summary',
    'sup',
    'table',
    'tbody',
    'td',
    'tfoot',
    'th',
    'thead',
    'time',
    'tr',
    'tt',
    'u',
    'ul',
    'var',
    'wbr',
  };

  /// Tags removed together with everything they contain.
  static const _droppedWithContent = {
    'script',
    'noscript',
    'iframe',
    'frame',
    'frameset',
    'object',
    'embed',
    'applet',
    'form',
    'input',
    'button',
    'select',
    'textarea',
    'option',
    'svg',
    'math',
    'template',
    'video',
    'audio',
    'source',
    'track',
    'canvas',
    'link',
    'meta',
    'base',
    'title',
    'head',
    'xml',
  };

  static const _allowedAttributes = {
    'align',
    'alt',
    'background',
    'bgcolor',
    'border',
    'cellpadding',
    'cellspacing',
    'class',
    'color',
    'cols',
    'colspan',
    'dir',
    'face',
    'height',
    'href',
    'lang',
    'rowspan',
    'size',
    'span',
    'src',
    'start',
    'style',
    'summary',
    'title',
    'type',
    'valign',
    'width',
  };

  static final _remoteUrl = RegExp(r'^\s*(https?:)?//', caseSensitive: false);
  static final _cssUrl = RegExp(r'url\(\s*([^)]*)\)', caseSensitive: false);

  /// Cleans [html]. `cid:` images become `data:` taken from [inlineImages];
  /// remote ones load only with [allowRemote].
  SanitizedHtml sanitize(
    String html, {
    Map<String, InlineImage> inlineImages = const {},
    bool allowRemote = false,
  }) {
    final document = html_parser.parse(html);
    var blocked = 0;

    String? fixImageUrl(String value) {
      final v = value.trim();
      if (v.toLowerCase().startsWith('cid:')) {
        final image =
            inlineImages[v.substring(4).replaceAll(RegExp('[<>]'), '')];
        if (image == null) return null;
        return 'data:${image.mimeType};base64,${base64Encode(image.bytes)}';
      }
      if (v.toLowerCase().startsWith('data:image/')) return v;
      if (_remoteUrl.hasMatch(v)) {
        if (allowRemote) return v.startsWith('//') ? 'https:$v' : v;
        blocked++;
        return null;
      }
      return null;
    }

    String cleanCss(String css) => css
        // Old Internet Explorer tricks to run code from CSS.
        .replaceAll(RegExp(r'expression\s*\(', caseSensitive: false), '(')
        .replaceAll(RegExp(r'@import[^;]*;?', caseSensitive: false), '')
        .replaceAll(RegExp(r'javascript:', caseSensitive: false), '')
        // The mail's "dark mode" rules make the text light and expect the
        // client to darken the background; we keep it white. A media query with
        // an unknown feature is never true, so those blocks stay off on every
        // platform.
        .replaceAll(
          RegExp(r'prefers-color-scheme\s*:\s*dark', caseSensitive: false),
          'kaamos-dark-mode-off',
        )
        .replaceAllMapped(_cssUrl, (m) {
          final inner = m
              .group(1)!
              .trim()
              .replaceAll(RegExp('^["\']|["\']\$'), '');
          final fixed = fixImageUrl(inner);
          return fixed == null ? 'none' : 'url("$fixed")';
        });

    void clean(dom.Node node) {
      for (final child in node.nodes.toList()) {
        if (child is dom.Element) {
          final tag = child.localName?.toLowerCase() ?? '';
          if (_droppedWithContent.contains(tag)) {
            child.remove();
            continue;
          }
          if (tag == 'style') {
            child.text = cleanCss(child.text);
            child.attributes.clear();
            continue;
          }
          if (!_allowedTags.contains(tag)) {
            // Unknown tag: keep the content, not the tag (e.g. Outlook's <o:p>,
            // <html>, <body>).
            clean(child);
            child.reparentChildren(child.parentNode!);
            child.remove();
            continue;
          }
          _cleanAttributes(child, fixImageUrl, cleanCss);
          clean(child);
        } else if (child is dom.Comment) {
          // Outlook conditional comments can contain HTML.
          child.remove();
        }
      }
    }

    final body = document.body ?? document.documentElement!;
    // <style> in <head> matters to newsletters: move it into the body before
    // throwing away the head.
    for (final style in document.querySelectorAll('head style').toList()) {
      body.nodes.insert(0, style..remove());
    }
    // The original <body> attributes (background, text colour): many
    // newsletters put the dark background there and the white text in the
    // content. If we lose them, the text ends up white on white.
    final bodyAttributes = _bodyAttributes(
      document.body,
      fixImageUrl,
      cleanCss,
    );
    clean(body);

    final csp = [
      "default-src 'none'",
      allowRemote ? 'img-src data: https: http:' : 'img-src data:',
      "style-src 'unsafe-inline'",
      allowRemote ? 'font-src data: https:' : 'font-src data:',
    ].join('; ');

    final page =
        '''
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="$csp">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="referrer" content="no-referrer">
<style>
html { background: #ffffff; color: #111111; color-scheme: light only; }
body { margin: 0; padding: 16px; min-height: 100vh; box-sizing: border-box; font-family: -apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; font-size: 15px; line-height: 1.5; overflow-wrap: anywhere; }
img { max-width: 100%; height: auto; }
table { max-width: 100%; }
pre { white-space: pre-wrap; }
</style>
</head>
<body$bodyAttributes>${body.innerHtml}</body>
</html>''';
    return SanitizedHtml(document: page, blockedRemote: blocked);
  }

  /// Attributes that only make sense on `<body>` (old HTML, but still common in
  /// mail).
  static const _bodyOnlyAttributes = {'text', 'link', 'vlink', 'alink'};

  /// The cleaned attributes of the original `<body>`, ready to write into the
  /// tag (e.g. ` bgcolor="#1a1a1a" style="color: #fff"`).
  static String _bodyAttributes(
    dom.Element? original,
    String? Function(String) fixImageUrl,
    String Function(String) cleanCss,
  ) {
    if (original == null) return '';
    final copy = dom.Element.tag('body');
    final legacy = <String, String>{};
    for (final MapEntry(:key, :value) in original.attributes.entries) {
      final name = key.toString().toLowerCase();
      if (_bodyOnlyAttributes.contains(name)) {
        legacy[name] = value;
      } else {
        copy.attributes[name] = value;
      }
    }
    _cleanAttributes(copy, fixImageUrl, cleanCss);
    final all = {
      for (final MapEntry(:key, :value) in copy.attributes.entries)
        key.toString(): value,
      // Colours only: nothing that could contain a URL.
      for (final MapEntry(:key, :value) in legacy.entries)
        if (RegExp(r'^#?[0-9a-zA-Z]{1,20}$').hasMatch(value.trim()))
          key: value.trim(),
    };
    return all.entries.map((e) => ' ${e.key}="${escapeHtml(e.value)}"').join();
  }

  static void _cleanAttributes(
    dom.Element element,
    String? Function(String) fixImageUrl,
    String Function(String) cleanCss,
  ) {
    final attributes = Map.of(element.attributes);
    element.attributes.clear();
    for (final MapEntry(:key, :value) in attributes.entries) {
      final name = key.toString().toLowerCase();
      if (!_allowedAttributes.contains(name)) continue;
      switch (name) {
        case 'href':
          final href = value.trim();
          final lower = href.toLowerCase();
          if (lower.startsWith('http://') ||
              lower.startsWith('https://') ||
              lower.startsWith('mailto:')) {
            element.attributes['href'] = href;
          }
        case 'src' || 'background':
          final fixed = fixImageUrl(value);
          if (fixed != null) element.attributes[name] = fixed;
        case 'style':
          element.attributes['style'] = cleanCss(value);
        default:
          element.attributes[name] = value;
      }
    }
  }
}

/// Plain text as HTML, to show it in the same WebView when needed (e.g. a
/// text-only mail with links). Escapes all the text.
String escapeHtml(String text) => const HtmlEscape().convert(text);
