import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/ai_chat_message.dart';
import '../../models/ai_coach_context.dart';
import '../../presenters/ai_coach_presenter.dart';
import '../../presenters/ledger_presenter.dart';
import 'advisor_log_card.dart';
import 'advisor_memory_sheet.dart';
import 'chat_markdown.dart';
import 'system/system.dart';

/// Entry point labels and icons per context.
const _entryMeta = {
  AiCoachEntryPoint.nutrition: (
    label: 'Nutrition Scan',
    icon: Icons.restaurant_outlined
  ),
  AiCoachEntryPoint.fasting: (
    label: 'Fast Commander',
    icon: Icons.timer_outlined
  ),
  AiCoachEntryPoint.stats: (
    label: 'Shadow Monarch',
    icon: Icons.bar_chart_outlined
  ),
  AiCoachEntryPoint.treasury: (
    label: 'Ledger Protocol',
    icon: Icons.account_balance_wallet_outlined
  ),
  AiCoachEntryPoint.financeAdvisor: (
    label: 'Money Mentor',
    icon: Icons.savings_outlined
  ),
  AiCoachEntryPoint.general: (
    label: 'The System',
    icon: Icons.psychology_outlined
  ),
};

/// Shows the AI Coach chat sheet. Opens as a draggable bottom sheet.
///
/// Usage:
/// ```dart
/// AiChatSheet.show(context, presenter: aiCoachPresenter,
///     entryPoint: AiCoachEntryPoint.nutrition);
/// ```
class AiChatSheet extends StatelessWidget {
  final AiCoachPresenter presenter;
  final AiCoachEntryPoint entryPoint;

  const AiChatSheet({
    super.key,
    required this.presenter,
    required this.entryPoint,
  });

  static Future<void> show(
    BuildContext context, {
    required AiCoachPresenter presenter,
    AiCoachEntryPoint entryPoint = AiCoachEntryPoint.general,
  }) {
    presenter.openSession(entryPoint);
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AiChatSheet(presenter: presenter, entryPoint: entryPoint),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, __) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: AiChatBody(
          presenter: presenter,
          entryPoint: entryPoint,
          showDragHandle: true,
        ),
      ),
    );
  }
}

/// The chat surface itself — header, message list, advisor log card, and input
/// bar — with no opinion about its container.
///
/// Mobile wraps it in [AiChatSheet]'s draggable bottom sheet; the web companion
/// wraps it in a docked side panel. Extracted so the two platforms share one
/// chat implementation rather than one per form factor.
class AiChatBody extends StatefulWidget {
  final AiCoachPresenter presenter;
  final AiCoachEntryPoint entryPoint;

  /// Bottom-sheet affordance — off in a docked container, which is not
  /// draggable.
  final bool showDragHandle;

  /// Whether the header prints the entry-point label. Off in the web dock,
  /// which is narrow enough that the label competes with the four trailing
  /// controls and ellipsises to "Mone…"; the dock prints the name itself in the
  /// strip above, where there is room.
  final bool showEntryLabel;

  /// Whether an unavailable model should offer the on-device download flow.
  /// False on web, which has no on-device tier: there the unavailable state is
  /// terminal (sign in / configure the endpoint), and offering a download the
  /// platform cannot perform would be a dead end.
  final bool allowModelDownload;

  const AiChatBody({
    super.key,
    required this.presenter,
    required this.entryPoint,
    this.showDragHandle = false,
    this.showEntryLabel = true,
    this.allowModelDownload = true,
  });

  @override
  State<AiChatBody> createState() => _AiChatBodyState();
}

class _AiChatBodyState extends State<AiChatBody> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  AiCoachPresenter get _presenter => widget.presenter;

  bool get _advisorMode =>
      widget.entryPoint == AiCoachEntryPoint.financeAdvisor &&
      _presenter.advisorLedger != null;
  LedgerPresenter? get _ledger => _presenter.advisorLedger;

  String? _lastLoggedSummary;

  /// A photo the user has attached but not yet sent (shown as a preview chip
  /// above the input). Advisor mode only.
  Uint8List? _pendingImage;

  @override
  void initState() {
    super.initState();
    if (_advisorMode) _ledger!.addListener(_onLedgerSideEffects);
  }

  /// Bridge ledger commits back into the conversation: post a "✓ Logged …"
  /// note when an in-chat entry commits, and swallow any form-fallback so it
  /// doesn't leak to the hub bar behind this sheet.
  void _onLedgerSideEffects() {
    if (!mounted) return;
    final ledger = _ledger!;
    final summary = ledger.lastCommittedSummary;
    if (summary != null && summary != _lastLoggedSummary) {
      _lastLoggedSummary = summary;
      _presenter.appendAssistantNote('✓ $summary');
      ledger.clearLastCommittedSummary();
      _scrollToBottom();
    }
    if (ledger.pendingFormPrefill != null) {
      ledger.consumeFormPrefill();
      _presenter.appendAssistantNote(
          "I couldn't pin that down — try rephrasing the amount and where it "
          "came from, and I'll prepare it again.");
    }
  }

  @override
  void dispose() {
    if (_advisorMode) _ledger!.removeListener(_onLedgerSideEffects);
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    final image = _pendingImage;
    if (text.isEmpty && image == null) return;
    _controller.clear();
    setState(() => _pendingImage = null);
    // Dismiss keyboard first so its animation starts before the rebuild.
    FocusScope.of(context).unfocus();
    Future.delayed(Duration.zero, () {
      _presenter.send(text, image: image);
      _scrollToBottom();
    });
  }

  /// Pick a bill / receipt / statement photo (camera or gallery) to attach.
  Future<void> _attachPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _PhotoSourceSheet(),
    );
    if (source == null || !mounted) return;
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 90,
      );
      if (picked == null || !mounted) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() => _pendingImage = bytes);
    } catch (_) {
      // Permission denied / no camera — no-op.
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final meta = _entryMeta[widget.entryPoint]!;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Column(
      children: [
        if (widget.showDragHandle) _DragHandle(),
        _SheetHeader(
          meta: meta,
          presenter: _presenter,
          showLabel: widget.showEntryLabel,
        ),
        Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
        Expanded(
          child: ListenableBuilder(
            listenable: _presenter,
            builder: (_, __) {
              if (_presenter.isInitializing) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        color: Theme.of(context).colorScheme.primary,
                        strokeWidth: 2,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Loading AI Coach…',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                );
              }
              if (!_presenter.isModelAvailable && !_presenter.isDownloading) {
                return widget.allowModelDownload
                    ? _DownloadPrompt(presenter: _presenter)
                    : const _CloudUnavailable();
              }
              if (_presenter.isDownloading) {
                return _DownloadProgress(presenter: _presenter);
              }
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => _scrollToBottom());
              return _MessageList(
                messages: _presenter.messages,
                scrollController: _scrollController,
                isResponding: _presenter.isResponding,
              );
            },
          ),
        ),
        if (_presenter.errorMessage != null)
          _ErrorChip(
            message: _presenter.errorMessage!,
            onDismiss: _presenter.clearError,
          ),
        if (_advisorMode)
          ListenableBuilder(
            listenable: _ledger!,
            builder: (_, __) => AdvisorLogCard(ledger: _ledger!),
          ),
        Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_pendingImage != null)
                _StagedImagePreview(
                  bytes: _pendingImage!,
                  onRemove: () => setState(() => _pendingImage = null),
                ),
              ListenableBuilder(
                listenable: _presenter,
                builder: (_, __) => _InputBar(
                  controller: _controller,
                  focusNode: _focusNode,
                  enabled: _presenter.isModelAvailable &&
                      !_presenter.isResponding &&
                      !_presenter.isInitializing,
                  onSend: _send,
                  // Photo upload is an advisor-only capability (its op is
                  // the only one wired for vision).
                  onAttach: _advisorMode ? _attachPhoto : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _DragHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .onSurfaceVariant
                .withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

class _SheetHeader extends StatelessWidget {
  final ({String label, IconData icon}) meta;
  final AiCoachPresenter presenter;
  final bool showLabel;
  const _SheetHeader({
    required this.meta,
    required this.presenter,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
      child: Row(
        children: [
          Icon(meta.icon, color: cs.onSurfaceVariant, size: 18),
          if (showLabel) ...[
            const SizedBox(width: 10),
            // Flexible so the title yields before the trailing controls in any
            // container narrower than a phone sheet.
            Flexible(
              child: Text(
                meta.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
          const Spacer(),
          if (presenter.entryPoint == AiCoachEntryPoint.financeAdvisor) ...[
            IconButton(
              icon: Icon(Icons.forum_outlined,
                  color: cs.onSurfaceVariant, size: 20),
              tooltip: 'Conversations',
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              onPressed: () => _ConversationsSheet.show(context, presenter),
            ),
            IconButton(
              icon: Icon(Icons.bookmark_border,
                  color: cs.onSurfaceVariant, size: 20),
              tooltip: 'Advisor memory',
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              onPressed: () => AdvisorMemorySheet.show(context, presenter),
            ),
            const SizedBox(width: 4),
          ],
          ListenableBuilder(
            listenable: presenter,
            builder: (_, __) => GestureDetector(
              onTap: presenter.isResponding ? null : presenter.toggleThinking,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: presenter.isThinkingEnabled
                      ? cs.primary.withValues(alpha: 0.2)
                      : cs.onSurfaceVariant.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: presenter.isThinkingEnabled
                        ? cs.primary.withValues(alpha: 0.5)
                        : cs.onSurfaceVariant.withValues(alpha: 0.2),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      presenter.isThinkingEnabled
                          ? Icons.psychology_outlined
                          : Icons.bolt_outlined,
                      color: presenter.isThinkingEnabled
                          ? cs.primary
                          : cs.onSurfaceVariant,
                      size: 13,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      presenter.isThinkingEnabled ? 'Think' : 'Fast',
                      style: TextStyle(
                        color: presenter.isThinkingEnabled
                            ? cs.primary
                            : cs.onSurfaceVariant,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: cs.primary.withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
            child: Text(
              'AI',
              style: TextStyle(
                color: cs.primary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  final List<AiChatMessage> messages;
  final ScrollController scrollController;
  final bool isResponding;

  const _MessageList({
    required this.messages,
    required this.scrollController,
    required this.isResponding,
  });

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return Center(
        child: Text(
          'Ask me anything.',
          style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 14),
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: messages.length,
      itemBuilder: (_, i) => _MessageBubble(message: messages[i]),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final AiChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == AiChatRole.user;

    return AnimatedOpacity(
      opacity: 1,
      duration: const Duration(milliseconds: 200),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isUser
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.18)
                : Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isUser ? 16 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 16),
            ),
            border: Border.all(
              color: isUser
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)
                  : Theme.of(context)
                      .colorScheme
                      .outlineVariant
                      .withValues(alpha: 0.4),
              width: 0.5,
            ),
            boxShadow: isUser
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: Theme.of(context).brightness == Brightness.dark
                            ? 0.10
                            : 0.05,
                      ),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
          ),
          child: message.isStreaming && message.text.isEmpty
              ? const _ThinkingLabel()
              : Column(
                  crossAxisAlignment: isUser
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (message.imageBytes != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 220),
                          child: Image.memory(
                            message.imageBytes!,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      if (message.text.isNotEmpty) const SizedBox(height: 8),
                    ],
                    if (message.text.isNotEmpty)
                      isUser
                          // The user typed plain text — render verbatim.
                          ? Text(
                              message.text,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontSize: 14,
                                height: 1.45,
                              ),
                            )
                          // Coach replies carry light Markdown — render it so
                          // '##', '**', and '-' don't leak into the bubble.
                          : ChatMarkdown(
                              message.text,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// A "thinking" status that cycles through playful words while the coach works
/// (the advisor replies in one shot, so a word cycler reads better than dots).
/// A small dot pulses beside the word; both settle to a static state when the
/// platform requests reduced motion.
class _ThinkingLabel extends StatefulWidget {
  const _ThinkingLabel();

  @override
  State<_ThinkingLabel> createState() => _ThinkingLabelState();
}

class _ThinkingLabelState extends State<_ThinkingLabel>
    with SingleTickerProviderStateMixin {
  static const _words = [
    'Thinking…',
    'Pondering…',
    'Crunching the numbers…',
    'Reading your finances…',
    'Weighing the options…',
    'Doing the math…',
  ];

  late final AnimationController _ctrl;
  int _wordIndex = 0;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..addStatusListener((status) {
        // Advance the word each time the pulse completes a cycle.
        if (status == AnimationStatus.completed) {
          if (!mounted) return;
          setState(() => _wordIndex = (_wordIndex + 1) % _words.length);
          _ctrl.forward(from: 0);
        }
      });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.of(context).disableAnimations;
    if (_reduceMotion) {
      _ctrl.stop();
    } else if (!_ctrl.isAnimating) {
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = _reduceMotion ? 'Thinking…' : _words[_wordIndex];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FadeTransition(
          opacity: _reduceMotion
              ? const AlwaysStoppedAnimation(0.6)
              : Tween(begin: 0.35, end: 1.0).animate(
                  CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
                ),
          child: Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(right: 8),
            decoration:
                BoxDecoration(color: cs.primary, shape: BoxShape.circle),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Text(
            label,
            key: ValueKey(label),
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 13,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final VoidCallback onSend;

  /// When non-null, shows a camera button that attaches a photo (advisor only).
  final VoidCallback? onAttach;

  const _InputBar({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onSend,
    this.onAttach,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: cs.outlineVariant, width: 1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (onAttach != null) ...[
            _AttachButton(enabled: enabled, onTap: onAttach!),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: enabled,
              maxLines: 4,
              minLines: 1,
              textInputAction: TextInputAction.newline,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                hintText: enabled ? 'Ask your coach…' : 'Coach not ready…',
                hintStyle: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 14,
                ),
                filled: true,
                fillColor: cs.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: cs.outlineVariant,
                    width: 1,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: cs.primary,
                    width: 1,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _SendButton(enabled: enabled, onSend: onSend),
        ],
      ),
    );
  }
}

/// ChatGPT-style history browser: lists saved conversations with a "New chat"
/// action; tap to reopen, trash to delete.
class _ConversationsSheet extends StatelessWidget {
  final AiCoachPresenter presenter;
  const _ConversationsSheet({required this.presenter});

  static Future<void> show(BuildContext context, AiCoachPresenter presenter) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      builder: (_) => _ConversationsSheet(presenter: presenter),
    );
  }

  static String _relativeTime(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return '${t.month}/${t.day}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: ListenableBuilder(
          listenable: presenter,
          builder: (context, _) {
            final convos = presenter.conversations;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 12, 6),
                  child: Row(
                    children: [
                      Text(
                        'Conversations',
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () {
                          presenter.startNewConversation();
                          Navigator.of(context).pop();
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('New chat'),
                      ),
                    ],
                  ),
                ),
                if (convos.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No saved conversations yet.',
                      style:
                          TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                    ),
                  ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: convos.length,
                    itemBuilder: (_, i) {
                      final c = convos[i];
                      final isCurrent = c.id == presenter.currentConversationId;
                      final preview = c.messages.isNotEmpty
                          ? c.messages.last.text
                          : 'Empty';
                      return _ConversationTile(
                        title: c.title,
                        subtitle:
                            '${_relativeTime(c.updatedAt)} · ${c.messages.length} msgs',
                        preview: preview,
                        isCurrent: isCurrent,
                        isArchive: c.isArchive,
                        onTap: () {
                          presenter.openConversation(c.id);
                          Navigator.of(context).pop();
                        },
                        onDelete: () => presenter.deleteConversation(c.id),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String preview;
  final bool isCurrent;
  final bool isArchive;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ConversationTile({
    required this.title,
    required this.subtitle,
    required this.preview,
    required this.isCurrent,
    required this.isArchive,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isCurrent
            ? cs.primary.withValues(alpha: 0.10)
            : cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color:
              isCurrent ? cs.primary.withValues(alpha: 0.4) : cs.outlineVariant,
          width: 0.5,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          child: Row(
            children: [
              Icon(
                isArchive
                    ? Icons.inventory_2_outlined
                    : Icons.chat_bubble_outline,
                size: 16,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline,
                    size: 18, color: cs.onSurfaceVariant),
                tooltip: 'Delete',
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;
  const _AttachButton({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant, width: 1),
        ),
        child: Icon(
          Icons.add_a_photo_outlined,
          size: 20,
          color: enabled
              ? cs.onSurfaceVariant
              : cs.onSurfaceVariant.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}

/// The staged (not-yet-sent) photo shown just above the input bar, with a
/// remove button.
class _StagedImagePreview extends StatelessWidget {
  final Uint8List bytes;
  final VoidCallback onRemove;
  const _StagedImagePreview({required this.bytes, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child:
                Image.memory(bytes, width: 64, height: 64, fit: BoxFit.cover),
          ),
          Positioned(
            top: -6,
            right: -6,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: cs.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Icon(Icons.close, size: 14, color: cs.onSurfaceVariant),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Camera-or-gallery chooser for attaching a photo to the advisor chat.
class _PhotoSourceSheet extends StatelessWidget {
  const _PhotoSourceSheet();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Attach a photo',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'A bill, receipt, statement, or credit offer',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 16),
            _PhotoSourceTile(
              icon: Icons.photo_camera_outlined,
              label: 'Take photo',
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            const SizedBox(height: 9),
            _PhotoSourceTile(
              icon: Icons.image_outlined,
              label: 'Choose from gallery',
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoSourceTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _PhotoSourceTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(icon, color: cs.primary, size: 22),
              const SizedBox(width: 14),
              Text(
                label,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatefulWidget {
  final bool enabled;
  final VoidCallback onSend;

  const _SendButton({required this.enabled, required this.onSend});

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scale = Tween(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown: widget.enabled ? (_) => _ctrl.forward() : null,
        onTapUp: widget.enabled
            ? (_) {
                _ctrl.reverse();
                widget.onSend();
              }
            : null,
        onTapCancel: () => _ctrl.reverse(),
        child: ScaleTransition(
          scale: _scale,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: widget.enabled
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.send_rounded,
              color: widget.enabled
                  ? Theme.of(context).colorScheme.onPrimary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              size: 20,
            ),
          ),
        ),
      );
}

class _DownloadPrompt extends StatelessWidget {
  final AiCoachPresenter presenter;
  const _DownloadPrompt({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.psychology_outlined, color: cs.primary, size: 48),
          const SizedBox(height: 20),
          Text(
            'AI Coach',
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Download the on-device model to unlock\ncoaching, food analysis, and insights.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '~586 MB • One-time download • Private',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
          ),
          const SizedBox(height: 28),
          AppPrimaryButton(
            label: 'Download AI Coach',
            onPressed: presenter.downloadModel,
            height: 48,
          ),
        ],
      ),
    );
  }
}

class _DownloadProgress extends StatelessWidget {
  final AiCoachPresenter presenter;
  const _DownloadProgress({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final progress = presenter.downloadProgress ?? 0;
    final isInitializing = progress >= 100;
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.download_outlined, color: cs.onSurfaceVariant, size: 40),
          const SizedBox(height: 20),
          Text(
            isInitializing
                ? 'Initializing AI model…'
                : 'Downloading AI Coach… $progress%',
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: isInitializing
                ? LinearProgressIndicator(
                    backgroundColor: cs.surfaceContainerHigh,
                    valueColor: AlwaysStoppedAnimation(cs.primary),
                    minHeight: 8,
                  )
                : LinearProgressIndicator(
                    value: progress / 100.0,
                    backgroundColor: cs.surfaceContainerLow,
                    valueColor: AlwaysStoppedAnimation(cs.primary),
                    minHeight: 8,
                  ),
          ),
          const SizedBox(height: 12),
          Text(
            isInitializing
                ? 'Loading model into memory — this takes a moment.'
                : 'Keep the app open during download.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ErrorChip extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const _ErrorChip({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: errorColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: errorColor.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: errorColor, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: errorColor,
                fontSize: 12,
              ),
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: Icon(Icons.close, color: errorColor, size: 16),
          ),
        ],
      ),
    );
  }
}

/// Terminal unavailable state for platforms with no on-device tier (web).
/// Offering the download flow there would be a dead end, so this names the two
/// things that actually gate the cloud tier instead.
class _CloudUnavailable extends StatelessWidget {
  const _CloudUnavailable();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 40, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              'Money Mentor is unavailable',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'The advisor runs in the cloud. Make sure you are signed in and '
              'that this build has an AI endpoint configured.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
