import 'package:material_ui/material_ui.dart';

import '../workspace/workspace_models.dart';
import 'pms_controller.dart';
import 'pms_style.dart';

class GuestDeliveryStatus extends StatelessWidget {
  const GuestDeliveryStatus({
    super.key,
    required this.delivery,
    this.invitationStatus = '',
    this.onRetry,
  });

  final Json delivery;
  final String invitationStatus;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final state = text(delivery, 'state');
    final synthetic = delivery['test_mode'] == true;
    String label(String state) => switch (state) {
      'queued' => 'Email queued',
      'sending' => 'Sending invitation',
      'provider_accepted' =>
        synthetic ? 'Test provider accepted' : 'Provider accepted',
      'provider_delayed' => 'Delivery delayed at recipient server',
      'delivered' =>
        synthetic ? 'Test delivery confirmed' : 'Delivery confirmed',
      'retry_scheduled' => 'Delivery retry scheduled',
      'permanent_failed' => 'Delivery failed',
      'unconfirmed' => 'Delivery outcome unconfirmed',
      'cancelled' => 'Cancelled',
      'awaiting_approval' =>
        'Pre-check-in invitation awaits approval in Reception.',
      'simulated_sent' => 'Pre-check-in invitation simulated locally.',
      'receipt_accepted' => 'Provider acceptance receipt received',
      'receipt_delivered' => 'Delivery confirmation receipt received',
      'receipt_delayed' => 'Delivery delay receipt received',
      'receipt_bounced' ||
      'receipt_failed' ||
      'receipt_suppressed' => 'Delivery failure receipt received',
      _ => 'Invitation prepared',
    };
    final failure = switch (delivery['failure_code']) {
      'provider_unavailable' => 'Email provider unavailable',
      'provider_throttled' => 'Email provider temporarily limited',
      'invalid_recipient' => 'Invalid recipient email',
      'provider_rejected' => 'Email rejected by provider',
      'provider_bounced' => 'Recipient server rejected the email',
      'provider_suppressed' => 'Email suppressed by provider',
      'invitation_expired' => 'Invitation expired before delivery',
      'outcome_unknown' => 'Provider outcome is unknown',
      _ => null,
    };
    final last = text(delivery, 'last_attempt_at');
    final next = text(delivery, 'next_attempt_at');
    final delivered = text(delivery, 'delivered_at');
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      title: Text(ui('Invitation details')),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: PmsBadge(
            ui(label(state.isEmpty ? invitationStatus : state)),
            tone: state == 'delivered' ? 'ready' : 'neutral',
          ),
        ),
        if (synthetic) Text(ui('Test only. No guest email was sent.')),
        if (last.isNotEmpty)
          Text('${ui('Last attempt')} · ${uiDateTime(last)}'),
        if (delivered.isNotEmpty)
          Text('${ui('Confirmed at')} · ${uiDateTime(delivered)}'),
        if (failure != null) Text(ui(failure)),
        if (state == 'retry_scheduled' && next.isNotEmpty)
          Text('${ui('Next retry')} · ${uiDateTime(next)}'),
        if (delivery['attempts'] is int)
          Text('${ui('Delivery attempts')} · ${delivery['attempts']}'),
        for (final event in optionalRows(delivery['history']))
          Text(
            '${ui(label(text(event, 'kind')))} · ${uiDateTime(text(event, 'created_at'))}',
          ),
        if (delivery['can_retry'] == true)
          PmsButton(ui('Retry delivery now'), onPressed: onRetry),
      ],
    );
  }
}
