import 'package:flutter/material.dart';

import '../../services/gate_unsent_exits.dart';
import '../../theme/app_theme.dart';
import '../../widgets/smartpark_ui.dart';

/// Tells gate staff about exits recorded without a connection: how many are
/// still waiting to be sent, and any the server refused, which must be
/// recorded again or the vehicle stays "inside". Nothing when there are none.
class UnsentExitsBanner extends StatelessWidget {
  const UnsentExitsBanner({super.key, required this.unsent});

  final GateUnsentExits unsent;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: unsent,
      builder: (BuildContext context, _) {
        final List<UnsentExit> failed = unsent.failed;
        final List<UnsentExit> waiting = unsent.waiting;
        if (failed.isEmpty && waiting.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (failed.isNotEmpty) _failedBox(failed),
              if (failed.isNotEmpty && waiting.isNotEmpty)
                const SizedBox(height: 8),
              if (waiting.isNotEmpty) _waitingBox(waiting),
            ],
          ),
        );
      },
    );
  }

  static String _count(int n) => '$n exit${n == 1 ? '' : 's'}';

  static String _describe(UnsentExit exit) {
    final String plate = exit.plate.trim().isEmpty ? 'No plate' : exit.plate;
    final String day = spSameDate(exit.leftAt, DateTime.now())
        ? ''
        : ', ${spFormatDate(exit.leftAt)}';
    return '$plate${exit.walkIn ? ' (walk-in)' : ''} · left '
        '${spFormatClockTime(exit.leftAt)}$day';
  }

  Widget _failedBox(List<UnsentExit> failed) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 6),
      decoration: BoxDecoration(
        color: AppTheme.dangerSoft,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.dangerBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.error_outline_rounded, color: AppTheme.danger),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_count(failed.length)} '
                  '${failed.length == 1 ? 'was' : 'were'} not saved',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.danger,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              'Recorded without a connection, then refused when it came '
              'back, so the vehicle still shows as inside. Record each exit '
              'again: switch the scanner to Exit and scan the ticket or look '
              'up its plate. Walk-ins are checked out from the Walk-ins list.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: AppTheme.textDark,
              ),
            ),
          ),
          for (final UnsentExit exit in failed)
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    _describe(exit),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textDark,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => unsent.dismiss(exit),
                  child: const Text('Dismiss'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _waitingBox(List<UnsentExit> waiting) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.cloud_off_rounded,
            size: 20,
            color: AppTheme.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_count(waiting.length)} waiting to be sent. They go out by '
              'themselves when the connection is back. Stay signed in until '
              'then.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
