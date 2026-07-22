import 'package:flutter/material.dart';

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
class AiChatSheet extends StatefulWidget {
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
  State<AiChatSheet> createState() => _AiChatSheetState();
}

class _AiChatSheetState extends State<AiChatSheet> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  AiCoachPresenter get _presenter => widget.presenter;

  bool get _advisorMode =>
      widget.entryPoint == AiCoachEntryPoint.financeAdvisor &&
      _presenter.advisorLedger != null;
  LedgerPresenter? get _ledger => _presenter.advisorLedger;

  String? _lastLoggedSummary;

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
    if (text.isEmpty) return;
    _controller.clear();
    // Dismiss keyboard first so its animation starts before the rebuild.
    FocusScope.of(context).unfocus();
    Future.delayed(Duration.zero, () {
      _presenter.send(text);
      _scrollToBottom();
    });
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

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            _DragHandle(),
            _SheetHeader(meta: meta, presenter: _presenter),
            Divider(
                height: 1, color: Theme.of(context).colorScheme.outlineVariant),
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
                  if (!_presenter.isModelAvailable &&
                      !_presenter.isDownloading) {
                    return _DownloadPrompt(presenter: _presenter);
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
              child: ListenableBuilder(
                listenable: _presenter,
                builder: (_, __) => _InputBar(
                  controller: _controller,
                  focusNode: _focusNode,
                  enabled: _presenter.isModelAvailable &&
                      !_presenter.isResponding &&
                      !_presenter.isInitializing,
                  onSend: _send,
                ),
              ),
            ),
          ],
        ),
      ),
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
  const _SheetHeader({required this.meta, required this.presenter});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Row(
        children: [
          Icon(meta.icon, color: cs.onSurfaceVariant, size: 18),
          const SizedBox(width: 10),
          Text(
            meta.label,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          if (presenter.entryPoint == AiCoachEntryPoint.financeAdvisor) ...[
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
              ? const _TypingIndicator()
              : isUser
                  // The user typed plain text — render verbatim (no Markdown).
                  ? Text(
                      message.text,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 14,
                        height: 1.45,
                      ),
                    )
                  // Coach replies carry light Markdown — render it properly so
                  // '##', '**', and '-' don't leak into the bubble as text.
                  : ChatMarkdown(
                      message.text,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _ctrl
        ..stop()
        ..value = 0.5;
    } else if (!_ctrl.isAnimating) {
      _ctrl.repeat();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          return AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) {
              final offset = ((_ctrl.value - i * 0.15) % 1.0);
              final opacity = offset < 0.5 ? offset * 2 : (1 - offset) * 2;
              return Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withValues(alpha: opacity.clamp(0.2, 1.0)),
                  shape: BoxShape.circle,
                ),
              );
            },
          );
        }),
      );
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final VoidCallback onSend;

  const _InputBar({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onSend,
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
