import 'package:delvane_business/core/localization/web_strings.dart';
import 'package:flutter/material.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../shared/components.dart';
import 'workspace_models.dart';
import 'workspace_repository.dart';

class RecordPage extends StatefulWidget {
  const RecordPage({
    super.key,
    required this.auth,
    required this.repository,
    required this.workspace,
    required this.ref,
    this.openReservation,
  });
  final AuthController auth;
  final WorkspaceRepository repository;
  final OperationalWorkspace workspace;
  final RecordRef ref;
  final ValueChanged<String>? openReservation;
  @override
  State<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> {
  late Future<RecordDetail> result;
  @override
  void initState() {
    super.initState();
    result = _guardedLoad();
  }

  Future<RecordDetail> _guardedLoad() {
    final next = _load();
    // A 401 may remove this route before the next frame attaches FutureBuilder.
    // Keep the error on the original future for the builder without an unhandled branch.
    next.ignore();
    return next;
  }

  Future<RecordDetail> _load() async {
    await widget.auth.revalidate();
    final user = widget.auth.user;
    if (user == null) {
      throw const ApiException('Sign in again.', statusCode: 401);
    }
    return widget.repository.detail(user, widget.ref, widget.workspace);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(ui('${widget.ref.kind.name} record')),
      actions: [
        IconButton(
          tooltip: 'Refresh record',
          onPressed: () => setState(() {
            result = _guardedLoad();
          }),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<RecordDetail>(
      future: result,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    snapshot.error is ApiException
                        ? (snapshot.error as ApiException).message
                        : ui('Record unavailable.'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => setState(() {
                      result = _guardedLoad();
                    }),
                    child: Text(ui('Retry')),
                  ),
                ],
              ),
            ),
          );
        }
        final detail = snapshot.requireData;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      detail.title,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      ui(
                        'Connected to isolated development data · Read-only workspace',
                      ),
                    ),
                    const Divider(height: 28),
                    for (final entry in detail.fields.entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final label = Text(
                              entry.key,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            );
                            final value = SelectableText(
                              entry.value.isEmpty
                                  ? ui('Not provided')
                                  : entry.value,
                            );
                            return constraints.maxWidth < 480
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      label,
                                      const SizedBox(height: 2),
                                      value,
                                    ],
                                  )
                                : Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(width: 185, child: label),
                                      Expanded(child: value),
                                    ],
                                  );
                          },
                        ),
                      ),
                    if (detail.checklist.isNotEmpty) ...[
                      Text(
                        ui('Cleaning checklist'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      for (final item in detail.checklist)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            item.completed
                                ? Icons.check_circle_outline
                                : Icons.radio_button_unchecked,
                          ),
                          title: Text(item.label),
                          subtitle: Text(
                            item.completed ? ui('Completed') : ui('Pending'),
                          ),
                        ),
                    ],
                    if (detail.links.isNotEmpty) const Divider(height: 24),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final link in detail.links)
                          OutlinedButton.icon(
                            icon: const Icon(Icons.arrow_forward, size: 16),
                            label: Text(link.label),
                            onPressed:
                                link.ref.kind == RecordKind.reservation &&
                                    widget.openReservation != null
                                ? () => widget.openReservation!(link.ref.id)
                                : () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => RecordPage(
                                        auth: widget.auth,
                                        repository: widget.repository,
                                        workspace: widget.workspace,
                                        ref: link.ref,
                                        openReservation: widget.openReservation,
                                      ),
                                    ),
                                  ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
