import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

/// Live countdown and elapsed time for one group-buy campaign.
/// Uses server timestamps from the group_buys record; device time is only
/// used to render the countdown between refreshes.
class GroupBuyCountdown extends StatefulWidget {
  const GroupBuyCountdown({
    super.key,
    required this.startsAt,
    required this.endsAt,
    this.compact = false,
  });

  final DateTime startsAt;
  final DateTime endsAt;
  final bool compact;

  @override
  State<GroupBuyCountdown> createState() => _GroupBuyCountdownState();
}

class _GroupBuyCountdownState extends State<GroupBuyCountdown> {
  Timer? _timer;
  DateTime _now = DateTime.now().toUtc();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now().toUtc());
      }
    });
  }

  @override
  void didUpdateWidget(covariant GroupBuyCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startsAt != widget.startsAt ||
        oldWidget.endsAt != widget.endsAt) {
      _now = DateTime.now().toUtc();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _duration(Duration value) {
    final seconds = value.inSeconds.clamp(0, 315360000);
    final days = seconds ~/ 86400;
    final hours = (seconds % 86400) ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remainingSeconds = seconds % 60;

    if (days > 0) {
      return '${days}j ${hours.toString().padLeft(2, '0')}h';
    }
    if (hours > 0) {
      return '${hours}h ${minutes.toString().padLeft(2, '0')}m ${remainingSeconds.toString().padLeft(2, '0')}s';
    }
    return '${minutes}m ${remainingSeconds.toString().padLeft(2, '0')}s';
  }

  String _elapsed(Duration value) {
    final minutes = value.inMinutes;
    if (minutes < 1) return 'vient de commencer';
    if (minutes < 60) return 'commencé il y a $minutes min';
    final hours = value.inHours;
    final rest = minutes % 60;
    if (hours < 24) {
      return rest == 0
          ? 'commencé il y a $hours h'
          : 'commencé il y a $hours h $rest min';
    }
    final days = value.inDays;
    return 'commencé il y a $days j';
  }

  @override
  Widget build(BuildContext context) {
    final startsAt = widget.startsAt.toUtc();
    final endsAt = widget.endsAt.toUtc();
    final colorScheme = Theme.of(context).colorScheme;

    final Widget content;
    if (_now.isBefore(startsAt)) {
      content = Text(
        'Commence dans ${_duration(startsAt.difference(_now))}',
        style: TextStyle(
          color: colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      );
    } else if (_now.isBefore(endsAt)) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _elapsed(_now.difference(startsAt)),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(Icons.timer_outlined, size: 16, color: colorScheme.primary),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  'Se termine dans ${_duration(endsAt.difference(_now))}',
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    } else {
      content = Text(
        'Regroupage terminé',
        style: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    if (widget.compact &&
        !_now.isBefore(startsAt) &&
        _now.isBefore(endsAt)) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _elapsed(_now.difference(startsAt)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.timer_outlined,
              size: 14,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                'Fin dans ${_duration(endsAt.difference(_now))}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
            ),
          ],
        ),
      );
    }

    if (widget.compact) return content;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: content,
    );
  }
}
