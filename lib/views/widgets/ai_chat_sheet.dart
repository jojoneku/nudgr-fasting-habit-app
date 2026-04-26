import 'package:flutter/material.dart';

import '../../app_colors.dart';
import '../../models/ai_chat_message.dart';
import '../../models/ai_coach_context.dart';
import '../../presenters/ai_coach_presenter.dart';

/// Entry point labels and icons per context.
const _entryMeta = {
  AiCoachEntryPoint.nutrition: (label: 'Nutrition Scan', icon: '🍱'),
  AiCoachEntryPoint.fasting: (label: 'Fast Commander', icon: '⚡'),
  AiCoachEntryPoint.stats: (label: 'Shadow Monarch', icon: '👁'),
  AiCoachEntryPoint.treasury: (label: 'Ledger Protocol', icon: '💰'),
  AiCoachEntryPoint.general: (label: 'The System', icon: '🖥'),
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

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    _presenter.send(text);
    _scrollToBottom();
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
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            _DragHandle(),
            _SheetHeader(meta: meta),
            const Divider(height: 1, color: Color(0xFF2A3140)),
            Expanded(
              child: ListenableBuilder(
                listenable: _presenter,
                builder: (_, __) {
                  if (!_presenter.isModelAvailable && !_presenter.isDownloading) {
                    return _DownloadPrompt(presenter: _presenter);
                  }
                  if (_presenter.isDownloading) {
                    return _DownloadProgress(presenter: _presenter);
                  }
                  WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
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
            Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: ListenableBuilder(
                listenable: _presenter,
                builder: (_, __) => _InputBar(
                  controller: _controller,
                  focusNode: _focusNode,
                  enabled: _presenter.isModelAvailable && !_presenter.isResponding,
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
            color: AppColors.textSecondary.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

class _SheetHeader extends StatelessWidget {
  final ({String label, String icon}) meta;
  const _SheetHeader({required this.meta});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
        child: Row(
          children: [
            Text(meta.icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Text(
              meta.label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  width: 0.5,
                ),
              ),
              child: const Text(
                'AI',
                style: TextStyle(
                  color: AppColors.primary,
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
      return const Center(
        child: Text(
          'Ask me anything.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
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
                ? AppColors.primary.withValues(alpha: 0.18)
                : const Color(0xFF242D3A),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isUser ? 16 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 16),
            ),
            border: isUser
                ? Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    width: 0.5,
                  )
                : null,
          ),
          child: message.isStreaming && message.text.isEmpty
              ? const _TypingIndicator()
              : Text(
                  message.text,
                  style: TextStyle(
                    color: isUser
                        ? AppColors.primary
                        : AppColors.textPrimary,
                    fontSize: 14,
                    height: 1.45,
                  ),
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
      duration: const Duration(milliseconds: 900),
    )..repeat();
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
                  color: AppColors.textSecondary.withValues(alpha: opacity.clamp(0.2, 1.0)),
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
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 12),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(
            top: BorderSide(color: Color(0xFF2A3140), width: 1),
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
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: enabled ? 'Ask your coach…' : 'Coach not ready…',
                  hintStyle: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                  filled: true,
                  fillColor: const Color(0xFF141A22),
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
                    borderSide: const BorderSide(
                      color: Color(0xFF2A3140),
                      width: 1,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: AppColors.primary,
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
                  ? AppColors.primary
                  : AppColors.textSecondary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.send_rounded,
              color: widget.enabled ? Colors.black : AppColors.textSecondary,
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
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🧠', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 20),
            const Text(
              'AI Coach',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Download the on-device model to unlock\ncoaching, food analysis, and insights.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '~586 MB • One-time download • Private',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: presenter.downloadModel,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Download AI Coach',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      );
}

class _DownloadProgress extends StatelessWidget {
  final AiCoachPresenter presenter;
  const _DownloadProgress({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final progress = presenter.downloadProgress ?? 0;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('⬇️', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 20),
          Text(
            'Downloading AI Coach… $progress%',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress / 100.0,
              backgroundColor: AppColors.surface,
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Keep the app open during download.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
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
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppColors.danger.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: AppColors.danger, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: AppColors.danger,
                  fontSize: 12,
                ),
              ),
            ),
            GestureDetector(
              onTap: onDismiss,
              child: const Icon(Icons.close, color: AppColors.danger, size: 16),
            ),
          ],
        ),
      );
}
