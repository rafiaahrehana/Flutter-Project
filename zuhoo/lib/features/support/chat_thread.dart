import 'package:flutter/material.dart';

import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import 'support_models.dart';

/// A conversation, drawn as bubbles.
///
/// Presentational on purpose — it renders what it is given and emits text when
/// the composer is used. Which endpoint the messages came from, and whether a
/// reply is internal, are decisions the screen above makes; a widget that
/// guessed either would be the wrong place to get it wrong.
class ChatThread extends StatelessWidget {
  const ChatThread({
    super.key,
    required this.messages,
    required this.currentUserId,
    required this.controller,
    required this.onSend,
    this.sending = false,
    this.disabled = false,
    this.disabledNotice,
    this.placeholder = 'Write a message',
  });

  final List<SupportMessage> messages;

  /// Whose messages sit on the right. Null while the profile is still loading,
  /// in which case everything renders as the other party — briefly wrong in a
  /// harmless direction rather than confidently wrong.
  final int? currentUserId;

  final TextEditingController controller;
  final VoidCallback onSend;
  final bool sending;

  /// A settled ticket takes no more replies.
  final bool disabled;
  final String? disabledNotice;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (messages.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              'No messages yet — start the conversation.',
              textAlign: TextAlign.center,
              style: TextStyle(color: bos.muted, fontSize: 13.5),
            ),
          )
        else
          for (var i = 0; i < messages.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _Bubble(
              message: messages[i],
              mine: currentUserId != null &&
                  messages[i].sentById == currentUserId,
            ),
          ],
        const SizedBox(height: 16),
        Divider(height: 1, color: bos.borderLight),
        const SizedBox(height: 12),
        if (disabled)
          Text(
            disabledNotice ?? 'This conversation is closed.',
            textAlign: TextAlign.center,
            style: TextStyle(color: bos.muted, fontSize: 12.5),
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: placeholder,
                    isDense: true,
                  ),
                  onSubmitted: (_) => onSend(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: sending ? null : onSend,
                style: IconButton.styleFrom(backgroundColor: bos.brand),
                icon: sending
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded,
                        size: 18, color: Colors.white),
              ),
            ],
          ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine});

  final SupportMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    // Own messages take the brand fill with white text; everyone else's take a
    // neutral surface. Side alone is not enough to tell them apart at a glance
    // on a narrow screen.
    final background = mine
        ? bos.brand
        : (bos.isDark ? bos.bgHover : bos.bgSubtle);
    final foreground = mine ? Colors.white : bos.text;
    final metaColour =
        mine ? Colors.white.withValues(alpha: 0.75) : bos.muted;

    return Row(
      mainAxisAlignment:
          mine ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!mine) ...[
          Avatar(initials: _initials(message.sentByName), size: 28),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.72,
            ),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(14),
                topRight: const Radius.circular(14),
                bottomLeft: Radius.circular(mine ? 14 : 4),
                bottomRight: Radius.circular(mine ? 4 : 14),
              ),
              border: mine ? null : Border.all(color: bos.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!mine && message.sentByName != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      message.sentByName!,
                      style: TextStyle(
                        color: bos.brandInk,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                Text(
                  message.message,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
                if (message.hasAttachment) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.attach_file_rounded,
                          size: 13, color: metaColour),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          message.attachmentFileName ?? 'Attachment',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: metaColour, fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Labelled, not merely styled: an internal note reaching a
                    // client is a privacy failure, and the only defence at
                    // reading time is that it says what it is.
                    if (message.isInternal) ...[
                      Icon(Icons.lock_outline_rounded,
                          size: 11, color: metaColour),
                      const SizedBox(width: 3),
                      Text(
                        'Internal',
                        style: TextStyle(
                          color: metaColour,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    if (message.isResolution) ...[
                      Icon(Icons.check_circle_outline_rounded,
                          size: 11, color: metaColour),
                      const SizedBox(width: 3),
                      Text(
                        'Resolution',
                        style: TextStyle(
                          color: metaColour,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      Fmt.relative(message.createdAt),
                      style: TextStyle(color: metaColour, fontSize: 10.5),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _initials(String? name) {
    final parts = (name ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}
