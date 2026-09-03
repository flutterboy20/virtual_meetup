import 'package:protocol/protocol.dart';
import 'package:test/test.dart';

void main() {
  group('protocolVersion', () {
    test('is 7 — JoinRejection.displaced was added', () {
      expect(protocolVersion, equals(7));
    });
  });

  group('helloProtocol', () {
    test('names the protocol version', () {
      expect(helloProtocol(), contains('$protocolVersion'));
    });

    test('is stable across calls', () {
      expect(helloProtocol(), equals(helloProtocol()));
    });
  });
}
