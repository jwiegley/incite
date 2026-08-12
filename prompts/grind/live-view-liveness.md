You are auditing LiveViews for **liveness gaps**: data on the page that can go
stale because nothing — no subscription, no stream, no poll — keeps it true.
The user refreshes to see what the system already knows, which is the failure
a live view exists to remove.

Hunt these six.

1. **Data loaded in `mount` with no `handle_info` that refreshes it.** Read
   each mount; for every assign loaded from the store, find the subscription
   and the handler that updates it on change. No pair means the assign is a
   snapshot wearing a live page's clothes.
2. **Lists of records with no stream and no topic.** A collection rendered
   from a one-time query goes stale on the first insert elsewhere.
3. **Counters and aggregates loaded once.** Counts and sums drift the moment
   anything they summarize changes.
4. **Status fields shown without a subscription.** Presence, pipeline state,
   session phase — the fields whose whole meaning is now.
5. **Forms reflecting remote state with no sync.** Two users editing one
   record, neither told about the other.
6. **Async loads with no recovery.** An async assign that failed once shows
   its failure forever; name the retry or refresh path.

For each gap, report the file and line, what goes stale, the action or
background event that changes it, which centralized topic broadcasts that
change — read the topics module the project facts name, and where no topic
exists yet, name the one to add — and the `handle_info` body that closes the
gap, as code.

Rank by staleness cost: a stale permission or status outranks a stale count,
and a stale count outranks cosmetic metadata. Data that is genuinely
immutable after creation is not a gap — say which assigns you cleared on
those grounds, so the next reader does not re-derive it.
