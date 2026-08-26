/// The two typefaces the whole app is set in.
///
/// Names only, and **no Flutter import** — the world's signage is drawn with
/// `dart:ui` paragraphs rather than widgets, and those files must be able to
/// name a face without pulling `material.dart` into the render loop with it.
/// `core/theme.dart` reads the same two constants, which is what keeps the
/// lobby and the world from ending up in two different fonts.
///
/// Both are bundled, not fetched. A face that arrives over the network is a
/// face that arrives late on venue wifi, and a wordmark that swaps typeface a
/// second after the page paints is the first thing anybody sees.
abstract final class AppFonts {
  /// The wordmark and the big headings.
  ///
  /// Bricolage Grotesque, at one weight and one weight only. It is a face
  /// with opinions — tapered joints, a slightly wonky rhythm, letters that
  /// are not quite the same width as each other — and opinions are exactly
  /// what a wordmark wants and what a settings row does not. It appears on
  /// the front door and on nothing that has a form field in it.
  static const String display = 'BricolageGrotesque';

  /// Everything else: UI, body copy, and the signs inside the world.
  ///
  /// Archivo, a signage grotesque. Picked for the room this app is pretending
  /// to be: booth banners, session boards, wayfinding. It holds up at 11px in
  /// a muted grey on the admin screen and at 22px on a beach hut sign, which
  /// is the whole range this project has.
  static const String text = 'Archivo';
}
