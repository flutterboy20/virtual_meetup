import 'dart:convert';

import 'package:protocol/protocol.dart';
import 'package:server/server.dart';
import 'package:test/test.dart';

/// A socket that records what it was sent.
class FakeConnection implements PlayerConnection {
  final List<String> sent = [];
  bool closed = false;

  List<ProtocolMessage> get received =>
      sent.map(decodeMessage).toList(growable: false);

  List<AdminErrorMessage> get errors =>
      received.whereType<AdminErrorMessage>().toList(growable: false);

  List<ConfigMessage> get configs =>
      received.whereType<ConfigMessage>().toList(growable: false);

  @override
  void send(String data) => sent.add(data);

  @override
  void close() => closed = true;
}

/// A valid config document padded to exactly [bytes] characters.
///
/// The padding goes into the tagline, so the document stays *valid* JSON that
/// the store would otherwise happily accept — which is what makes the size
/// guard the only thing that can be refusing it.
String documentOf(int bytes) {
  final base = jsonEncode({'tagline': ''});
  final padding = 'a' * (bytes - base.length);
  final document = jsonEncode({'tagline': padding});
  return document.substring(0, bytes);
}

void main() {
  const token = 'a-long-enough-test-token';

  group('ConfigStore.apply', () {
    test('accepts a document at the limit', () {
      final store = ConfigStore.inMemory();
      final document = documentOf(maxConfigDocumentBytes);
      expect(document.length, equals(maxConfigDocumentBytes));

      expect(store.apply(document), isNotNull);
      expect(store.config.tagline, hasLength(greaterThan(1000)));
    });

    test('refuses a document one character over the limit', () {
      final store = ConfigStore.inMemory();
      final before = store.config;

      expect(store.apply(documentOf(maxConfigDocumentBytes + 1)), isNull);
      // The live config is untouched — a refused push changes nothing.
      expect(store.config, equals(before));
    });

    test('refuses a document far over the limit', () {
      final store = ConfigStore.inMemory();

      expect(store.apply(documentOf(maxConfigDocumentBytes * 4)), isNull);
      expect(store.config, equals(AppConfig.defaults));
    });

    test('the cap is below the admin frame ceiling, on purpose', () {
      // If it were the other way round the frame guard would fire first and a
      // moderator would see a silent drop instead of a sentence.
      expect(maxConfigDocumentBytes, lessThan(maxAdminFrameBytes));
    });
  });

  group('an admin pushing an oversized config', () {
    late MapRelays relays;
    late AdminHub hub;
    late FakeConnection connection;
    late AdminSession session;

    setUp(() {
      relays = MapRelays(log: (_) {});
      hub = AdminHub(relays: relays, token: token, log: (_) {});
      connection = FakeConnection();
      session = hub.open(connection)
        ..handleData(encodeMessage(const AdminAuthMessage(token: token)));
    });

    test('is refused with a sentence naming the problem', () {
      session.handleData(
        encodeMessage(
          AdminSetConfigMessage(
            document: documentOf(maxConfigDocumentBytes + 1),
          ),
        ),
      );

      final error = connection.errors.single;
      expect(error.reason, equals(AdminError.badRequest));
      // A sentence, not a silent drop: it names the size, the limit, and the
      // fact that nothing changed.
      expect(error.detail, contains('${maxConfigDocumentBytes + 1}'));
      expect(error.detail, contains('$maxConfigDocumentBytes'));
      expect(error.detail, contains('Nothing was changed'));
    });

    test('leaves the live config exactly as it was', () {
      final before = relays.config.config;

      session.handleData(
        encodeMessage(
          AdminSetConfigMessage(
            document: documentOf(maxConfigDocumentBytes + 1),
          ),
        ),
      );

      expect(relays.config.config, equals(before));
    });

    test('a document at the limit is still accepted and broadcast', () {
      final configsBefore = connection.configs.length;

      session.handleData(
        encodeMessage(
          AdminSetConfigMessage(document: documentOf(maxConfigDocumentBytes)),
        ),
      );

      expect(connection.errors, isEmpty);
      expect(connection.configs.length, greaterThan(configsBefore));
    });

    test('the socket survives, so the moderator can try again', () {
      session
        ..handleData(
          encodeMessage(
            AdminSetConfigMessage(
              document: documentOf(maxConfigDocumentBytes + 1),
            ),
          ),
        )
        ..handleData(
          encodeMessage(
            const AdminSetConfigMessage(document: '{"tagline":"Hello"}'),
          ),
        );

      expect(connection.closed, isFalse);
      expect(relays.config.config.tagline, equals('Hello'));
    });
  });

  group('the admin frame guard', () {
    test('drops a frame over the ceiling, before it is decoded', () {
      final relays = MapRelays(log: (_) {});
      final hub = AdminHub(relays: relays, token: token, log: (_) {});
      final connection = FakeConnection();
      final session = hub.open(connection);

      // A frame that *is* a valid auth message and would otherwise authorise
      // this socket, made too big by padding. Nothing comes back and the
      // socket is not authorised, so nothing decoded it.
      final padded =
          '{"type":"adminAuth","version":$protocolVersion,'
          '"token":"$token","pad":"${'x' * maxAdminFrameBytes}"}';
      expect(padded.length, greaterThan(maxAdminFrameBytes));

      session.handleData(padded);

      expect(connection.sent, isEmpty);
      expect(session.isAuthorized, isFalse);
    });

    test('a frame under the ceiling is read as normal', () {
      final relays = MapRelays(log: (_) {});
      final hub = AdminHub(relays: relays, token: token, log: (_) {});
      final connection = FakeConnection();
      final session = hub.open(connection)
        ..handleData(encodeMessage(const AdminAuthMessage(token: token)));

      expect(session.isAuthorized, isTrue);
    });
  });
}
