import 'package:flutter_test/flutter_test.dart';
import 'package:kaamos_mail/src/data/imap_mail_service.dart';

void main() {
  group('parseInternalDate', () {
    test('parses the IMAP format and converts to UTC', () {
      expect(
        parseInternalDate('17-Jul-1996 02:44:25 -0700'),
        DateTime.utc(1996, 7, 17, 9, 44, 25),
      );
      expect(
        parseInternalDate(' 6-Nov-2026 21:04:13 +0100'),
        DateTime.utc(2026, 11, 6, 20, 4, 13),
      );
    });

    test('wrong format = null', () {
      expect(parseInternalDate(null), isNull);
      expect(parseInternalDate('ieri'), isNull);
      expect(parseInternalDate('17-Xyz-1996 02:44:25 -0700'), isNull);
    });
  });
}
