import 'package:flutter/widgets.dart';

import 'payment_event_drain_service.dart';

/// Runs [PaymentEventDrainService.drainAndIngest] every time the app comes to
/// the foreground.
///
/// Draining only from `main()` is not enough. The payment-notification
/// listener is a bound service in the same process as the Activity, so the
/// process stays alive long after the user leaves the app — returning to
/// Receipt Drop resumes the existing Flutter engine rather than creating a
/// new one, and `main()` does not run again. A category picked on the
/// floating overlay would then sit in the native queue until something killed
/// the process, which is why a receipt could be confirmed as "saved" and
/// still never show up on the home screen.
class PaymentEventDrainListener extends StatefulWidget {
  const PaymentEventDrainListener({super.key, required this.child});

  final Widget child;

  @override
  State<PaymentEventDrainListener> createState() =>
      _PaymentEventDrainListenerState();
}

class _PaymentEventDrainListenerState extends State<PaymentEventDrainListener>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Deliberately unawaited: the drain writes through the normal
      // repository, and the home screen's Drift stream picks the rows up on
      // its own once they land.
      PaymentEventDrainService.drainAndIngest();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
