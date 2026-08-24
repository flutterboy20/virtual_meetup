import 'dart:math';

// What a session id is, and what it is not.
//
// A session id is the client's claim to *be the same player as before*. The
// socket dies constantly — a phone leaves wifi, a laptop lid closes, a tab
// backgrounds — and the player must survive all of it. Connection identity is
// the socket; session identity outlives it.
//
// It is a bearer token, so it is generated on the device with a real random
// source and never shown to anybody. That is a deliberate, bounded risk: the
// worst somebody can do with a stolen one is take over a bean at a
// conference. We are not protecting a bank account, so 128 bits of randomness
// and no server-side secret is the right amount of machinery.

/// How many hex characters a session id is: 32, i.e. 128 bits.
const int sessionIdLength = 32;

/// Whether [value] is shaped like a session id this project issues.
///
/// The server checks this before trusting an id off the wire. It proves
/// nothing about who sent it — that is not what it is for. It stops a client
/// from posting a megabyte of text, or a `../`, or an empty string as its
/// identity and having the server key a map on it.
bool isValidSessionId(String value) {
  if (value.length != sessionIdLength) return false;
  for (var i = 0; i < value.length; i++) {
    final code = value.codeUnitAt(i);
    final isDigit = code >= 0x30 && code <= 0x39;
    final isLowerHex = code >= 0x61 && code <= 0x66;
    if (!isDigit && !isLowerHex) return false;
  }
  return true;
}

/// Returns a fresh session id: [sessionIdLength] hex characters of randomness.
///
/// Defaults to [Random.secure] because this is a bearer token — a guessable
/// one would let somebody walk into a stranger's bean. [random] is injectable
/// so tests and the load test can be deterministic; nothing else should pass
/// it.
///
/// Generated on the *client*, not handed out by the server. That is the point
/// of it: the client has to be able to say "I am the same person as before"
/// on a socket the server has never seen, which it cannot do with an identity
/// the server would have to look up first.
String newSessionId([Random? random]) {
  final source = random ?? Random.secure();
  final buffer = StringBuffer();
  for (var i = 0; i < sessionIdLength; i++) {
    buffer.write(source.nextInt(16).toRadixString(16));
  }
  return buffer.toString();
}
