import 'package:flutter_test/flutter_test.dart';
import 'package:kaamos_mail/src/ui/screens/mail_home.dart';

void main() {
  test('the compose window is a bit less than half of the window', () {
    expect(composeWindowHeight(1000), 450);
    expect(composeWindowHeight(1377), closeTo(619.65, 0.01));
  });

  test('it never gets too small or too big', () {
    expect(composeWindowHeight(600), 360, reason: 'min 360');
    expect(composeWindowHeight(2160), 720, reason: 'max 720 on 4K');
  });

  test('on a short window it still fits inside the margins', () {
    expect(composeWindowHeight(380), 380 - 32);
  });
}
