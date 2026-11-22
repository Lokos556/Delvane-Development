import 'chat_session.dart';

import 'package:flutter/rendering.dart';

import 'assistant_prompts.dart';
import 'section_picker.dart';
import 'overflow_row.dart';

import 'package:material_ui/material_ui.dart';

import 'pms_controller.dart';
import 'pms_style.dart';
import 'operational_desk.dart';

/// Existing operational conversation, now restricted to grounded read-only lookups.

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
  final focus = FocusNode();
  late final ScrollController thread;
  final _viewportKey = GlobalKey();
  final _messageKeys = <String, GlobalKey>{};
  bool _jumpVisible = false;
  int _scrollTicket = 0;
  double? _viewportHeight;

  @override
  void initState() {
    super.initState();
    final chat = widget.c.chat;
    if (!chat.initialized) {
      chat.syncHistory(widget.c.object('conversation'), notify: false);
    }
    thread = ScrollController(initialScrollOffset: chat.scrollOffset)
      ..addListener(_trackScroll);
    chat.addListener(_chatChanged);
    if (chat.followLatest) _scheduleScroll();
  }

  void _trackScroll() {
    if (!thread.hasClients) return;
    widget.c.chat.scrollOffset = thread.offset;
    final show = thread.position.extentAfter > 32;
    if (show != _jumpVisible && mounted) setState(() => _jumpVisible = show);
  }

  void _chatChanged() {
    if (!mounted) return;
    setState(() {});
    final chat = widget.c.chat;
    if (chat.change == ChatChange.submitted) {
      chat.followLatest = true;
      _scheduleScroll();
    } else if (chat.change == ChatChange.replied && chat.followLatest) {
      _scheduleScroll(answerId: chat.latestAnswerId);
    }
  }

  void _scheduleScroll({String? answerId}) {
    final ticket = ++_scrollTicket;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted ||
          !thread.hasClients ||
          ticket != _scrollTicket ||
          !widget.c.chat.followLatest) {
        return;
      }
      if (!mounted ||
          !thread.hasClients ||
          ticket != _scrollTicket ||
          !widget.c.chat.followLatest) {
        return;
      }
      var target = thread.position.maxScrollExtent;
      final box = _messageKeys[answerId]?.currentContext?.findRenderObject();
      if (box is RenderBox &&
          box.size.height > thread.position.viewportDimension - 24) {
        target =
            RenderAbstractViewport.of(box).getOffsetToReveal(box, 0).offset -
            12;
      }
      target = target
          .clamp(
            thread.position.minScrollExtent,
            thread.position.maxScrollExtent,
          )
          .toDouble();
      if (MediaQuery.disableAnimationsOf(context)) {
        thread.jumpTo(target);
      } else {
        await thread.animateTo(
          target,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
      // Settle an estimated lazy-list extent for a newly submitted short turn.
      if (answerId == null &&
          mounted &&
          thread.hasClients &&
          ticket == _scrollTicket &&
          widget.c.chat.followLatest &&
          widget.c.chat.busy &&
          thread.position.extentAfter > 1) {
        thread.jumpTo(thread.position.maxScrollExtent);
      }
    });
  }

  Future<void> send() async {
    final chat = widget.c.chat;
    final text = widget.input.text;
    if (chat.busy || text.trim().isEmpty) return;
    widget.input.clear();
    final accepted = await chat.send(text, widget.c.strings.language);
    if (!accepted && mounted && widget.input.text.isEmpty) {
      widget.input.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  Future<void> retry() async {
    final question = widget.c.chat.turn?.text;
    if (await widget.c.chat.retry() &&
        mounted &&
        widget.input.text == question) {
      widget.input.clear();
    }
  }

  @override
  void dispose() {
    ++_scrollTicket;
    widget.c.chat.removeListener(_chatChanged);
    focus.dispose();
    thread.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c,
        d = c.object('intelligence'),
        provider = c.object('provider');
    final mobile = MediaQuery.sizeOf(context).width <= 760;
    final messages = c.chat.messages;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final localizedPrompts = [
      for (final prompt in ownerAssistantPrompts) prompt.text(c.strings),
    ];
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
              constraints: const BoxConstraints(minHeight: 64),
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
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (!mobile)
                          Text(
                            provider['external_fallback_configured'] == true
                                ? ui('OpenAI configured · Facts from PMS')
                                : ui('Local-first · No external AI'),
                            style: const TextStyle(fontSize: 12),
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
                      c.modeLabel,
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
          if (!keyboardOpen)
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
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                  Text(
                                    intelligenceBrief(d),
                                    style: const TextStyle(
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
            child:
                messages.isEmpty && !c.chat.busy && c.chat.turn?.failed != true
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
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              ui(
                                'Read-only assistant. Answers use your accessible PMS records; no bookings, prices or messages are changed.',
                              ),
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : _conversation(),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: mobile ? 8 : 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  ui('Read-only assistant'),
                  style: const TextStyle(fontSize: 11, color: PmsStyle.muted),
                ),
                const SizedBox(height: 6),
                if (c.chatRefreshError != null)
                  TextButton(
                    onPressed: c.load,
                    child: Text(ui("Couldn't refresh history. Try again.")),
                  ),
                if (!keyboardOpen)
                  PmsSectionPicker(
                    pickerLabel: c.t('TRY ASKING'),
                    allowSegments: false,
                    selected: -1,
                    labels: localizedPrompts,
                    onChanged: (i) {
                      widget.input.value = TextEditingValue(
                        text: localizedPrompts[i],
                        selection: TextSelection.collapsed(
                          offset: localizedPrompts[i].length,
                        ),
                      );
                      focus.requestFocus();
                    },
                  ),
                const SizedBox(height: 10),
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
                          // Sending should not dismiss the IME or replace its focus.
                          onEditingComplete: () {},
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
                        onPressed: c.chat.busy ? null : send,
                      ),
                    ],
                  ),
                ),
                if (!mobile)
                  Padding(
                    padding: EdgeInsets.only(top: 5),
                    child: Text(
                      ui(
                        'Read-only assistant. Answers use your accessible PMS records; no bookings, prices or messages are changed.',
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

  Widget _conversation() {
    final chat = widget.c.chat;
    final messages = chat.messages;
    final historyCount = messages.length > 8 ? messages.length - 8 : 0;
    Widget row(int index) {
      if (index == messages.length) {
        return Padding(
          key: const ValueKey('chat-status'),
          padding: const EdgeInsets.only(bottom: 12),
          child: chat.busy
              ? const ChatThinkingIndicator()
              : Semantics(
                  liveRegion: true,
                  child: Row(
                    children: [
                      Expanded(child: Text(ui("Couldn't send. Try again."))),
                      TextButton(
                        key: const ValueKey('chat-retry'),
                        onPressed: retry,
                        child: Text(ui('Retry')),
                      ),
                    ],
                  ),
                ),
        );
      }
      final message = messages[index];
      return Padding(
        key: ValueKey(message.id),
        padding: const EdgeInsets.only(bottom: 14),
        child: Align(
          alignment: message.role == 'user'
              ? Alignment.centerRight
              : Alignment.centerLeft,
          child: Container(
            key: _messageKeys.putIfAbsent(message.id, () => GlobalKey()),
            constraints: const BoxConstraints(maxWidth: 760),
            child: PmsCard(
              color: message.role == 'user'
                  ? const Color(0xFFFFF4C9)
                  : const Color(0x99FFFFFF),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(message.content),
                  if (message.role != 'user' &&
                      message.metadata['read_only'] == true) ...[
                    const SizedBox(height: 8),
                    Text(
                      ui('Source: accessible PMS records · Read-only'),
                      style: const TextStyle(
                        fontSize: 11,
                        color: PmsStyle.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Stack(
      key: _viewportKey,
      children: [
        NotificationListener<ScrollMetricsNotification>(
          onNotification: (n) {
            if (_viewportHeight != n.metrics.viewportDimension) {
              _viewportHeight = n.metrics.viewportDimension;
              if (chat.followLatest) {
                _scheduleScroll(
                  answerId: chat.busy ? null : chat.latestAnswerId,
                );
              }
            }
            return false;
          },
          child: NotificationListener<UserScrollNotification>(
            onNotification: (n) {
              if (n.direction != ScrollDirection.idle) {
                ++_scrollTicket;
                chat.followLatest =
                    n.direction == ScrollDirection.reverse &&
                    n.metrics.extentAfter <= 8;
              } else if (n.metrics.extentAfter <= 8) {
                chat.followLatest = true;
              }
              return false;
            },
            child: Align(
              alignment: Alignment.bottomCenter,
              child: CustomScrollView(
                key: const PageStorageKey('delvane-conversation'),
                controller: thread,
                shrinkWrap: messages.length <= 8,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => row(index),
                        childCount: historyCount,
                        findChildIndexCallback: (key) {
                          final index = messages.indexWhere(
                            (m) => ValueKey(m.id) == key,
                          );
                          return index < 0 || index >= historyCount
                              ? null
                              : index;
                        },
                      ),
                    ),
                  ),
                  // The bounded newest turn is laid out even offscreen. A long
                  // response can reveal its start without first jumping to its end.
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 56),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        children: [
                          for (var i = historyCount; i < messages.length; i++)
                            row(i),
                          if (chat.busy || chat.turn?.failed == true)
                            row(messages.length),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_jumpVisible)
          Positioned(
            bottom: 8,
            right: 16,
            child: Material(
              color: PmsStyle.soft,
              borderRadius: BorderRadius.circular(22),
              child: TextButton.icon(
                key: const ValueKey('chat-jump-latest'),
                onPressed: () {
                  chat.followLatest = true;
                  _scheduleScroll();
                },
                icon: const Icon(Icons.arrow_downward, size: 18),
                label: Text(ui('Jump to latest')),
              ),
            ),
          ),
      ],
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
                  Text('${entry.$2}', style: const TextStyle(fontSize: 24)),
                ],
              ),
            ],
          ),
        ),
      ),
  ];
}

/// A real pending request indicator, never simulated response streaming.
class ChatThinkingIndicator extends StatefulWidget {
  const ChatThinkingIndicator({super.key});
  @override
  State<ChatThinkingIndicator> createState() => _ChatThinkingIndicatorState();
}

class _ChatThinkingIndicatorState extends State<ChatThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late final animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      animation.stop();
    } else {
      animation.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: ui('Delvane is responding…'),
    child: ExcludeSemantics(
      child: Row(
        children: [
          FadeTransition(
            opacity: animation.drive(Tween(begin: .35, end: 1.0)),
            child: const Text(
              '•••',
              style: TextStyle(fontSize: 24, color: PmsStyle.muted),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              ui('Delvane is responding…'),
              style: const TextStyle(color: PmsStyle.muted),
            ),
          ),
        ],
      ),
    ),
  );
}
