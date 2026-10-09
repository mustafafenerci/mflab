import 'package:flutter_test/flutter_test.dart';
import 'package:mflab/engine.dart';

void main() {
  test('semver comparison', () {
    expect(Engine.isNewer('1.0.1', '1.0.0'), isTrue);
    expect(Engine.isNewer('v1.2.0', '1.1.9'), isTrue);
    expect(Engine.isNewer('1.0.0', '1.0.0'), isFalse);
    expect(Engine.isNewer('0.9.9', '1.0.0'), isFalse);
  });
}
