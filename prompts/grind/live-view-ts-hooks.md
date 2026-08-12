You are auditing LiveViews for **interactions that should be client-side
hooks**. Every event a template sends travels the socket to the server, runs a
handler, and ships a diff back — tens to hundreds of milliseconds of latency
and a slice of server CPU. For an interaction that touches no server state,
that round trip buys nothing, and a TypeScript hook does the whole job in the
browser.

Hunt these seven.

1. **Toggles with no server side effect.** Accordions, panels, dropdowns,
   diff expanders — handlers whose whole body flips a boolean assign. The
   open state that nothing persists or broadcasts is client state.
2. **Purely visual state.** Tab selection with no URL change, hover and
   selection highlights, sort order over a list already fully on the client,
   a theme preview before save.
3. **Per-keystroke validation round trips.** A change event that runs a
   format check — a pattern, a length — with no store lookup fires once per
   keypress. Validate in the hook; involve the server on submit.
4. **Clipboard, download and open-link events.** The browser owns these; a
   server round trip to copy a string is two network hops for a local verb.
5. **Animation triggers.** An event whose handler only causes a class change
   or an animation, with no data mutation.
6. **Hooks that echo.** Existing hooks that push an event whose handler sends
   the same data straight back as a client event. The round trip transforms
   nothing; the hook can act locally.
7. **Debounced round trips that need no server.** A debounce attribute still
   sends the event — later. Where the debounced handler touches no store, the
   debounce belongs in the hook and the event disappears entirely.

For each opportunity, report the file, event and line, which of the seven it
is, the current handler body, the hook — its name and a TypeScript sketch —
and whether it still pushes anything to the server (a final confirm, say) or
nothing at all. Note the registration the project facts require for a new
hook; it is part of the fix.

Rank by interactions saved: a per-keystroke round trip on a busy form
outranks a rare toggle. State that must survive a reconnect belongs on the
server, whatever the latency — say which candidates you rejected on those
grounds, so the boundary stays legible.
