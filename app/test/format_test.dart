import 'package:flutter_test/flutter_test.dart';
import 'package:kontena/core/format.dart';

void main() {
  test('usd formats cents', () {
    expect(usd(123456), '\$1,234.56');
    expect(usdShort(10000), '\$100');
    expect(usdShort(10050), '\$100.50');
  });
  test('initials', () {
    expect(initials('Chidi Okafor'), 'CO');
    expect(initials('Ama'), 'A');
    expect(initials(''), '?');
  });
}
