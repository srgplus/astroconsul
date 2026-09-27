"""Who may write to whom in the chats, and how much.

The owner's rule for the messenger lives here and nowhere else, so changing
it is one line: the chat routes, the "Message" button on a chart
(`can_message`) and the people a new chat can be started with all ask
`may_write`.

The rest of what a chat needs (a chart of your own on both sides, no block
either way) is checked around it and does not change with it.
"""

from __future__ import annotations

# Anti-spam, per sender. Generous for two people talking, tight for one
# person pasting the same line into every chat they have.
MESSAGES_PER_MINUTE = 30
MESSAGES_PER_DAY = 500

# Conversations an account may start in a day: chats whose first message is
# its own. Answering somebody else's first message never counts.
NEW_CHATS_PER_DAY = 20


def may_write(sender_follows_recipient: bool, recipient_follows_sender: bool) -> bool:
    """Whether one account may write to another, from the follows between
    them. "Follows" means follows at least one chart the other account owns.

    Mutual follow: both of them chose the other, so nobody gets a message
    from a stranger. To let one side's follow be enough, return
    `sender_follows_recipient or recipient_follows_sender` instead.
    """
    return sender_follows_recipient and recipient_follows_sender
