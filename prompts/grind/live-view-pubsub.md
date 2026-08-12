You are auditing LiveViews for **spammy PubSub patterns**: broadcast and
subscription shapes that thrash the DOM, flood process mailboxes, and ship
bytes to every connected client for events most of them never needed.

Hunt these six.

1. **High-frequency broadcasts with no coalescing.** A topic that fires on
   every write, every sample, every keystroke, handled by a subscriber that
   assigns on each message. Name the debounce or coalesce point — at the
   broadcaster or in the handler — and write it in the finding, as the code
   the fix asks for.
2. **Broad topics filtered in the handler.** Subscribing to a collection-wide
   topic and discarding most messages in `handle_info` still wakes the
   process per message. The fix is a scoped topic keyed by the entity id;
   read the centralized topics module the project facts name, and propose the
   scoped topic there.
3. **Full structs on the wire.** Broadcasting a whole record means every
   subscriber holds and diffs it. Broadcast the id and the event kind;
   subscribers that care fetch what they need.
4. **Subscriptions without a connected guard.** A subscribe in `mount` that
   does not check `connected?(socket)` subscribes the static render pass too
   — a dangling subscription per page load.
5. **Expensive work per message.** A `handle_info` that runs a query or a
   heavy computation on every broadcast serializes that cost through the
   process mailbox; move it behind an async start, or coalesce first.
6. **Mailbox overload shapes.** One LiveView subscribed to several
   high-frequency topics with direct assigns has no backpressure at all.
   Name the topics and the rate; this is the finding to rank first when the
   rates multiply.

For each finding, report the file and line, the topic, which shape it is, and
the fix as code — the scoped topic, the guard, the coalesce, the id-only
broadcast. Rank by messages per second times subscriber count. A broadcast
that is genuinely rare and small is not a finding; say which you cleared.
