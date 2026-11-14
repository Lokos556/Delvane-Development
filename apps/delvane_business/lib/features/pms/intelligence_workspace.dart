import 'overflow_row.dart';

import 'package:material_ui/material_ui.dart';

import '../workspace/workspace_models.dart';
import 'pms_controller.dart';
import 'pms_style.dart';
import 'operational_desk.dart';

/// Layout of the active v264 workspace; its existing chat/proposal APIs are unchanged.
class IntelligenceWorkspace extends StatefulWidget {
  const IntelligenceWorkspace({
    super.key,
    required this.c,
    required this.input,
    required this.openSearch,
    this.viewportHeight,
  });
  final PmsController c;
  final TextEditingController input;
  final VoidCallback openSearch;
  final double? viewportHeight;
  @override
  State<IntelligenceWorkspace> createState() => _IntelligenceWorkspaceState();
}

class _IntelligenceWorkspaceState extends State<IntelligenceWorkspace> {
  final focus = FocusNode(), thread = ScrollController();
  @override
  void dispose() {
    focus.dispose();
    thread.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (widget.c.saving || widget.input.text.trim().isEmpty) return;
    await widget.c.act(() async {
      await widget.c.mutate('POST', '/api/rosa/chat', {
        'message': widget.input.text,
        'language': widget.c.strings.language,
      });
      widget.input.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c,
        d = c.object('intelligence'),
        conversation = c.object('conversation'),
        provider = c.object('provider');
    final mobile = MediaQuery.sizeOf(context).width <= 760;
    final messages = optionalRows(conversation['messages']),
        proposals = optionalRows(conversation['proposals']);
    return SizedBox(
      height:
          ((widget.viewportHeight ??
                      (MediaQuery.sizeOf(context).height -
                          MediaQuery.viewInsetsOf(context).bottom -
                          (mobile ? MediaQuery.viewPaddingOf(context).top : 0) -
                          (mobile &&
                                  MediaQuery.viewInsetsOf(context).bottom == 0
                              ? MediaQuery.viewPaddingOf(context).bottom
                              : 0))) -
                  (mobile ? 94 : 34))
              .clamp(mobile ? 180 : 360, 100000),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!mobile)
            Container(
              height: 70,
              padding: EdgeInsets.symmetric(horizontal: mobile ? 12 : 20),
              decoration: const BoxDecoration(
                color: Color(0xA6FFFCF6),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Row(
                children: [
                  Image.asset(PmsStyle.logo, width: 44, height: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ui('Delvane AI'),
                          style: TextStyle(
                            fontFamily: 'Georgia',
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (!mobile)
                          Text(
                            provider['external_fallback_configured'] == true
                                ? ui('Local-first · External AI ready')
                                : ui('Local-first · No external AI'),
                            style: const TextStyle(fontSize: 10),
                          ),
                      ],
                    ),
                  ),
                  if (!mobile)
                    PmsIconButton(
                      '⌕',
                      label: ui('Search Delvane'),
                      size: 38,
                      onPressed: widget.openSearch,
                    ),
                  TextButton(
                    onPressed: () => c.navigate(PmsPage.simulation),
                    child: Text(
                      ui(c.mode).toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              mobile ? 8 : 32,
              16,
              mobile ? 8 : 20,
              12,
            ),
            child: mobile
                ? PmsOverflowRow(
                    child: Row(
                      children: metrics(d)
                          .map((w) => SizedBox(width: 160, child: w))
                          .toList(),
                    ),
                  )
                : Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 24),
                          child: InkWell(
                            onTap: () => openOperationalDesk(context, c),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  ui('LIVE BRIEFING'),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1,
                                  ),
                                ),
                                Text(
                                  text(d, 'brief'),
                                  style: const TextStyle(
                                    fontFamily: 'Georgia',
                                    fontSize: 14,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 6,
                        child: Row(
                          children: metrics(d)
                              .map((w) => Expanded(child: w))
                              .toList(),
                        ),
                      ),
                    ],
                  ),
          ),
          Expanded(
            child: messages.isEmpty && proposals.isEmpty
                ? Center(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset(PmsStyle.logo, width: 72, height: 72),
                            const SizedBox(height: 24),
                            Text(
                              ui('Start a conversation with Delvane'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Georgia',
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              ui(
                                'Answers use the current Delvane database. Writes still pass through authority rules.',
                              ),
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    controller: thread,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final message in messages)
                          Align(
                            alignment: message['role'] == 'user'
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: PmsCard(
                                color: message['role'] == 'user'
                                    ? const Color(0xFFFFF4C9)
                                    : const Color(0x99FFFFFF),
                                child: SelectableText(text(message, 'content')),
                              ),
                            ),
                          ),
                        for (final proposal in proposals)
                          PmsCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  text(
                                    proposal,
                                    'summary',
                                    text(proposal, 'action_type'),
                                  ),
                                ),
                                PmsBadge(text(proposal, 'status')),
                                if (proposal['status'] == 'awaiting_approval')
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      for (final choice in [
                                        'approve',
                                        'decline',
                                      ])
                                        PmsButton(
                                          choice == 'approve'
                                              ? ui('Approve')
                                              : ui('Decline'),
                                          onPressed: c.saving
                                              ? null
                                              : () => c.act(() async {
                                                  await c.mutate(
                                                    'POST',
                                                    '/api/rosa/proposals/${idPath(text(proposal, 'id'))}/resolve',
                                                    {'decision': choice},
                                                  );
                                                }),
                                        ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: mobile ? 8 : 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PmsOverflowRow(
                  child: Row(
                    children: [
                      if (!mobile)
                        Text(
                          ui('TRY ASKING'),
                          style: TextStyle(fontSize: 9, letterSpacing: .5),
                        ),
                      for (final prompt in [
                        'Anything concerning tomorrow?',
                        'Who still needs registration?',
                        "Which properties aren't ready?",
                        "Anna called in sick. Move today's cleaning to Erika.",
                      ])
                        TextButton(
                          onPressed: () {
                            widget.input.text = prompt;
                            focus.requestFocus();
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            textStyle: const TextStyle(
                              fontFamily: PmsStyle.font,
                              fontSize: 10,
                            ),
                          ),
                          child: Text(c.t(prompt)),
                        ),
                    ],
                  ),
                ),
                PmsCard(
                  radius: 24,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  color: const Color(0xE6FFFFFF),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: TextField(
                          onTapOutside: (_) =>
                              FocusManager.instance.primaryFocus?.unfocus(),
                          key: const ValueKey('intelligence-composer'),
                          controller: widget.input,
                          focusNode: focus,
                          minLines: 1,
                          maxLines: 3,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => send(),
                          style: const TextStyle(fontSize: 14),
                          decoration: InputDecoration(
                            hintText: ui(
                              'Ask Delvane anything about the operation',
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            fillColor: Colors.transparent,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 8,
                            ),
                          ),
                        ),
                      ),
                      PmsIconButton(
                        '➤',
                        label: ui('Send message'),
                        onPressed: c.saving ? null : send,
                      ),
                    ],
                  ),
                ),
                if (!mobile)
                  Padding(
                    padding: EdgeInsets.only(top: 5),
                    child: Text(
                      ui(
                        'Answers use the current Delvane database. Writes still pass through authority rules.',
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 8),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> metrics(Json d) => [
    for (final entry in [
      ('Needs you', optionalRows(d['approvals']).length, 'decisions'),
      ('Delvane handling', d['handled'] ?? 0, 'active items'),
      ('Exceptions', optionalRows(d['exceptions']).length, 'detected'),
      ('Next 48h', optionalRows(d['arrivals']).length, 'arrivals'),
    ])
      InkWell(
        onTap: () => openOperationalDesk(
          context,
          widget.c,
          tab: switch (entry.$1) {
            'Needs you' => 1,
            'Exceptions' => 2,
            'Next 48h' => 3,
            _ => 0,
          },
        ),
        child: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.c.t(entry.$1),
                style: TextStyle(
                  fontSize: MediaQuery.sizeOf(context).width <= 760 ? 13 : 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.c.t(entry.$3),
                      style: TextStyle(
                        fontSize: MediaQuery.sizeOf(context).width <= 760
                            ? 11
                            : 10,
                      ),
                    ),
                  ),
                  Text(
                    '${entry.$2}',
                    style: const TextStyle(fontFamily: 'Georgia', fontSize: 24),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
  ];
}
