import 'package:flutter_test/flutter_test.dart';
import 'package:kaamos_mail/src/ui/screens/mail_home.dart';

void main() {
  test('the compose window has a fixed size, like Gmail', () {
    for (final h in [600.0, 800.0, 1080.0, 2160.0]) {
      expect(composeWindowHeight(h), 480, reason: 'window $h px tall');
    }
  });

  test('on a short window it shrinks to fit inside the margins', () {
    expect(composeWindowHeight(480 + 32), 480);
    expect(composeWindowHeight(400), 400 - 32);
  });
}
