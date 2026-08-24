import 'package:client/core/theme.dart';
import 'package:client/core/world_palette.dart';
import 'package:flutter/material.dart';
import 'package:protocol/protocol.dart';

/// The two places to go, with a live head-count on each.
///
/// **The counts are the point.** People follow people: a picker without them
/// is a coin toss, and a coin toss splits a crowd of 250 evenly over two
/// venues, which is the fastest way to make both of them feel empty. With the
/// numbers on the cards, the crowd does what crowds do and clumps — and the
/// person who wants the quiet one can still choose it, on purpose.
///
/// A card, not a dropdown or a segmented control, because this is the second
/// most important thing on the screen after the Join button and it has to be
/// readable and thumb-sized on a phone held one-handed while standing up.
class MapPicker extends StatelessWidget {
  /// Creates the picker.
  const MapPicker({
    required this.selected,
    required this.onSelected,
    required this.countOf,
    super.key,
  });

  /// Which map is currently chosen.
  final MapId selected;

  /// Called when the player picks a map.
  final ValueChanged<MapId> onSelected;

  /// How many people are on a map, or `null` if that is not known.
  final int? Function(MapId map) countOf;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final map in MapId.values) ...[
          if (map != MapId.values.first) const SizedBox(width: 10),
          Expanded(
            child: _MapCard(
              map: map,
              isSelected: map == selected,
              count: countOf(map),
              onTap: () => onSelected(map),
            ),
          ),
        ],
      ],
    );
  }
}

/// One place, as a card: a swatch of its own colours, a name, a head-count.
class _MapCard extends StatelessWidget {
  const _MapCard({
    required this.map,
    required this.isSelected,
    required this.count,
    required this.onTap,
  });

  final MapId map;
  final bool isSelected;
  final int? count;
  final VoidCallback onTap;

  /// The zone whose colours stand for this map on the card.
  ///
  /// The map's *own* palette rather than a fresh set of card colours, for the
  /// same reason the minimap uses the floors' colours: a picker that teaches
  /// a colour and then shows a different one inside is worse than a plain
  /// list.
  WorldZone get _face => switch (map) {
    MapId.conference => WorldZone.atrium,
    MapId.beach => WorldZone.beachSand,
  };

  /// The second colour in the swatch, so a card is a place and not a block.
  WorldZone get _accentFace => switch (map) {
    MapId.conference => WorldZone.hall,
    MapId.beach => WorldZone.beachSea,
  };

  @override
  Widget build(BuildContext context) {
    final colors = WorldPalette.of(_face);
    final accent = WorldPalette.of(_accentFace);

    return Semantics(
      button: true,
      selected: isSelected,
      label: '${map.label}${count == null ? '' : ', $count here'}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: AppTheme.surface.withValues(alpha: isSelected ? 0.9 : 0.5),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSelected
                  ? colors.floor
                  : AppTheme.ink.withValues(alpha: 0.08),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The swatch: the two colours this place is actually painted in.
              SizedBox(
                height: 26,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    children: [
                      Expanded(flex: 3, child: ColoredBox(color: colors.floor)),
                      Expanded(flex: 2, child: ColoredBox(color: accent.floor)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      map.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.ink,
                        fontSize: 14,
                        fontWeight: isSelected
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                  if (isSelected)
                    Icon(Icons.check_circle, size: 15, color: colors.floor),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                _headCount,
                style: const TextStyle(
                  color: AppTheme.mutedInk,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The line under the name.
  ///
  /// Three answers, not two. A dash means the server did not tell us, and it
  /// is deliberately not "0 here" — one of those invites you in and the other
  /// warns you off, and printing the wrong one is how a working beach ends up
  /// deserted all afternoon.
  String get _headCount => switch (count) {
    null => '—',
    0 => 'Empty — be the first',
    1 => '1 person here',
    final n => '$n people here',
  };
}
