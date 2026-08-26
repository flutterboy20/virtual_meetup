import 'package:protocol/protocol.dart';
import 'package:test/test.dart';

void main() {
  group('protocolVersion', () {
    test('is 5 — Phase 13 added JoinRejection.worldFull', () {
      expect(protocolVersion, equals(6));
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
