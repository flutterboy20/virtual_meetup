import 'package:flutter/painting.dart' show Color;
import 'package:protocol/protocol.dart';

/// How one zone is painted.
class ZoneColors {
  /// Creates a zone's colours.
  const ZoneColors({
    required this.floor,
    required this.accent,
    required this.grid,
    required this.ink,
  });

  /// The flat fill of the zone's floor.
  final Color floor;

  /// The colour its furniture and its floor markings are painted in.
  final Color accent;

  /// The faint motion-cue grid drawn over the floor.
  final Color grid;

  /// The colour text painted flat on this floor is written in.
  ///
  /// Per zone rather than one global value, because the hall is the only dark
  /// room in a daylight world: pale ink that reads as "painted on concrete"
  /// everywhere else would be invisible there, and dark ink that works there
  /// would be invisible everywhere else.
  final Color ink;
}

/// The colour of every zone, in one table.
///
/// Lives in `core/` rather than in `game/` because two very different things
/// need the same answer: the Flame floor renderer, and the Flutter minimap
/// widget. A minimap whose colours drift from the world's is worse than no
/// minimap — it teaches the player a mapping and then lies about it.
///
/// **Phase 9 rebased this light.** The world used to be a set of dark rooms,
/// which photographs well and reads badly: the venue is a daylight one, and a
/// dark floor under a phone's auto-brightness in a bright hall turns into a
/// grey smear. Everything below is a warm daylight scheme — sunlit poolside,
/// terracotta food court, green garden, neutral stone atrium, cool code lab,
/// gold sponsor row — with the conference hall deliberately left deep, because
/// an auditorium reads dark even at noon and that is the one room whose job is
/// to make a lit stage the brightest thing in it.
///
/// The seven hues are far apart on purpose. The readability test for this
/// world is not a laptop; it is a phone held at arm's length in a bright
/// convention hall, where "two slightly different blues" is one blue. Seven is
/// the ceiling, which is the other reason the two map corners stay void.
abstract final class WorldPalette {
  /// What is outside the building: the ground the venue sits on.
  ///
  /// Something rather than nothing, because the camera can see past the edge
  /// of an arm, and a void reads as a rendering bug. Under the daylight
  /// rebase it also has to read as *ground* — dry paving in the sun — rather
  /// than as the hole the old near-black turned into.
  static const Color outside = Color(0xFFBCB29B);

  /// The line drawn around the outside of the whole building.
  static const Color wall = Color(0xFF6E6450);

  /// The colour of the local player's marker on the minimap.
  ///
  /// Crimson, not the old amber: the sponsor row's floor is gold now, and a
  /// marker that disappears in one room is a marker you cannot trust.
  static const Color you = Color(0xFFE23E57);

  /// The colour of everybody else's dot on the minimap.
  static const Color others = Color(0xFF17242C);

  /// The pale halo drawn behind [others] so a dot survives the dark hall.
  static const Color othersHalo = Color(0xCCF2F8FB);

  /// Returns the colours of [zone].
  static ZoneColors of(WorldZone zone) => switch (zone) {
    // Neutral warm stone. The atrium is the room every other room is seen
    // against, so it is the one that must not have an opinion.
    WorldZone.atrium => const ZoneColors(
      floor: Color(0xFFEDE6D8),
      accent: Color(0xFF8C7A57),
      grid: Color(0x14584B33),
      ink: Color(0x24584B33),
    ),
    // Deep indigo: an auditorium reads dark even in daylight, and this is the
    // one room whose lit stage should be the brightest thing in it.
    WorldZone.hall => const ZoneColors(
      floor: Color(0xFF303C63),
      accent: Color(0xFF7E90DA),
      grid: Color(0x1AA9B8E8),
      ink: Color(0x26D6E2FF),
    ),
    // Burnt gold: the booths bring their own brand colours, so the floor they
    // stand on stays warm and quiet rather than competing with them.
    WorldZone.sponsorRow => const ZoneColors(
      floor: Color(0xFFF5D89A),
      accent: Color(0xFFB27C1E),
      grid: Color(0x146B4A0F),
      ink: Color(0x246B4A0F),
    ),
    // Sunlit poolside: the palest, coolest floor in the world, so that the
    // pool sitting in the middle of it reads as deeper water rather than as
    // a blue rectangle.
    WorldZone.lounge => const ZoneColors(
      floor: Color(0xFFA9DCE6),
      accent: Color(0xFF1B7385),
      grid: Color(0x14114C58),
      ink: Color(0x24114C58),
    ),
    // Terracotta: the food court is the warm, busy, street-corner room.
    WorldZone.foodCourt => const ZoneColors(
      floor: Color(0xFFE8A582),
      accent: Color(0xFFA8482A),
      grid: Color(0x146B2C19),
      ink: Color(0x246B2C19),
    ),
    // Cool blue-grey: the only cold light room, which is exactly what a lab
    // full of screens should feel like next to a terracotta tea stall.
    WorldZone.codeLab => const ZoneColors(
      floor: Color(0xFFC3D4E6),
      accent: Color(0xFF2F6288),
      grid: Color(0x141E3F57),
      ink: Color(0x241E3F57),
    ),
    // Lawn green, pushed yellow so it never becomes "the other teal".
    WorldZone.garden => const ZoneColors(
      floor: Color(0xFFC6DC96),
      accent: Color(0xFF43813B),
      grid: Color(0x142B5325),
      ink: Color(0x242B5325),
    ),

    // ---- The beach ------------------------------------------------------
    //
    // Three hues, and the constraint on them is *within the beach* first:
    // dark timber, bright sand, deep water is a value ladder you can read on
    // a phone at arm's length without looking at the hue at all. They are
    // also kept clear of the seven above, even though the two maps are never
    // on screen together — the minimap teaches a colour mapping, and a
    // mapping that means one thing here and another there is worse than none.

    // Weathered timber. Nothing else in the world is a mid-brown, which is
    // what makes the boardwalk read as a built thing standing on sand.
    WorldZone.beachBoardwalk => const ZoneColors(
      floor: Color(0xFFA9713F),
      accent: Color(0xFF5E3417),
      grid: Color(0x1A3A2210),
      ink: Color(0x2E3A2210),
    ),
    // Hot, dry sand: more saturated than the atrium's stone and oranger than
    // the sponsor row's gold, so it is neither of them at a glance.
    WorldZone.beachSand => const ZoneColors(
      floor: Color(0xFFEDC079),
      accent: Color(0xFFB06A22),
      grid: Color(0x1476400F),
      ink: Color(0x2676400F),
    ),
    // Deep water. The floor colour barely shows — `WaterComponent` paints
    // its own gradient over the whole rect — but what does show through at
    // the rim has to read as *depth*, which the lounge's pale poolside blue
    // would not.
    WorldZone.beachSea => const ZoneColors(
      floor: Color(0xFF115C74),
      accent: Color(0xFF37A6C4),
      grid: Color(0x1AAEE6F4),
      ink: Color(0x2ED9F3FA),
    ),
  };
}
