import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/widgets/smartpark_ui.dart';

/// Shows the latest value of one cached stream, in a phone or tablet
/// arrangement. Switching arrangement rebuilds the StreamBuilder in a new
/// spot, so it subscribes again, as when a phone layout turns into a tablet
/// one (split screen, density change).
class _Host extends StatefulWidget {
  const _Host({required this.source, required this.tablet});

  final Stream<String> source;
  final bool tablet;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with SpStreamCache<_Host> {
  int subscriptions = 0;

  @override
  Widget build(BuildContext context) {
    final Widget value = StreamBuilder<String>(
      stream: cachedStream('k', () {
        subscriptions++;
        return widget.source;
      }),
      builder: (BuildContext context, AsyncSnapshot<String> snapshot) =>
          Text(snapshot.data ?? 'empty'),
    );
    return MaterialApp(
      home: widget.tablet
          ? Center(child: value)
          : Align(alignment: Alignment.topLeft, child: value),
    );
  }
}

/// A stream event reaches the StreamBuilder on one frame and repaints it on
/// the next.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('a layout switch still shows the value already delivered', (
    WidgetTester tester,
  ) async {
    final StreamController<String> source =
        StreamController<String>.broadcast();
    addTearDown(source.close);

    await tester.pumpWidget(_Host(source: source.stream, tablet: false));
    source.add('Juliville Parking');
    await settle(tester);
    expect(find.text('Juliville Parking'), findsOneWidget);

    // Same state, new layout: the new StreamBuilder must not come up empty.
    await tester.pumpWidget(_Host(source: source.stream, tablet: true));
    await settle(tester);
    expect(find.text('Juliville Parking'), findsOneWidget);

    // And it keeps following later values.
    source.add('Updated');
    await settle(tester);
    expect(find.text('Updated'), findsOneWidget);

    final _HostState state = tester.state(find.byType(_Host));
    expect(state.subscriptions, 1, reason: 'the query is created only once');
  });

  testWidgets('errors are replayed too', (WidgetTester tester) async {
    final StreamController<String> source =
        StreamController<String>.broadcast();
    addTearDown(source.close);
    await tester.pumpWidget(_Host(source: source.stream, tablet: false));
    source.addError(StateError('offline'));
    await settle(tester);
    await tester.pumpWidget(_Host(source: source.stream, tablet: true));
    await settle(tester);
    // No data, but the builder must have received the error, not nothing.
    expect(find.text('empty'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
