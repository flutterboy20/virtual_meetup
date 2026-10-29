import 'package:client/core/theme.dart';
import 'package:flutter/material.dart';
import 'package:protocol/protocol.dart';

/// The two places to go, as venue wayfinding signs with a live head-count.
///
/// **The counts are the point.** People follow people: a picker without them
/// is a coin toss, and a coin toss splits a crowd of 250 evenly over two
/// venues, which is the fastest way to make both of them feel empty. With the
/// numbers on the signs, the crowd does what crowds do and clumps — and the
/// person who wants the quiet one can still choose it, on purpose.
///
/// Signs, stacked, rather than two cards side by side: a full-width row is a
/// bigger target for a thumb on a phone held one-handed while standing up,
/// and black-and-yellow wayfinding is the one visual language everybody at a
/// venue already reads without thinking.
class MapPicker extends StatelessWidget {
  /// Creates the picker.
  const MapPicker({
    required this.selected,
    required this.onSelected,
    required this.countOf,
    super.key,
    this.compact = false,
  });

  /// Which map is currently chosen.
  final MapId selected;

  /// Called when the player picks a map.
  final ValueChanged<MapId> onSelected;

  /// How many people are on a map, or `null` if that is not known.
  final int? Function(MapId map) countOf;

  /// Whether to give ground on a short phone: shorter signs, same targets
  /// (still well over 44px tall).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final map in MapId.values) ...[
          if (map != MapId.values.first) const SizedBox(height: 8),
          _HallSign(
            map: map,
            isSelected: map == selected,
            count: countOf(map),
            height: compact ? 46 : 54,
            onTap: () => onSelected(map),
          ),
        ],
      ],
    );
  }
}

/// One place, as a sign: an arrow, its name, a head-count.
class _HallSign extends StatelessWidget {
  const _HallSign({
    required this.map,
    required this.isSelected,
    required this.count,
    required this.height,
    required this.onTap,
  });

  final MapId map;
  final bool isSelected;
  final int? count;
  final double height;
  final VoidCallback onTap;

  /// Which way the sign points. Different per place, so the two signs read
  /// as two directions rather than as one sign printed twice.
  IconData get _arrow => switch (map) {
    MapId.conference => Icons.arrow_forward_rounded,
    MapId.beach => Icons.north_east_rounded,
  };

  @override
  Widget build(BuildContext context) {
    // The chosen sign is lit — black with yellow, the way a venue marks the
    // way you are going — and the other is an outline.
    final fg = isSelected ? LanyardColors.signal : LanyardColors.ink;
    final countColor = isSelected
        ? LanyardColors.badge
        : LanyardColors.mutedInk;

    return Semantics(
      button: true,
      selected: isSelected,
      label: '${map.label}${count == null ? '' : ', $count here'}',
      container: true,
      child: Material(
        color: isSelected ? LanyardColors.ink : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: LanyardColors.ink, width: isSelected ? 0 : 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: height,
            // The label above already says all of this, once; read out as
            // well it would be "Conference, 18 here, Conference, 18 people
            // here".
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(_arrow, color: fg, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        map.label,
                        overflow: TextOverflow.ellipsis,
                        style: LanyardText.sign.copyWith(color: fg),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Flexible too: on a narrow phone "Empty — be the first"
                    // and the place's name share the row rather than the
                    // count pushing the name off the edge.
                    Flexible(
                      child: Text(
                        _headCount,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          color: countColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The line beside the name.
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
