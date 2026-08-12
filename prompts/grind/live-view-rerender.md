You are auditing LiveViews for **unnecessary re-renders**: assigns and
handlers that make the diff engine work on changes nobody can see. Every
needless assign is a diff pass, a patch on the wire, and a step toward the UI
feeling slow under load.

Hunt these six anti-patterns.

1. **Unconditional assigns.** A `handle_info` or `handle_event` that assigns
   a value without comparing it to what the socket already holds. Same value,
   full diff pass.
2. **Whole-list replacement where a stream fits.** Reassigning a full list
   when one item changed; the fix is a stream insert or delete for the one
   item.
3. **Broad assigns passed into components.** A component re-renders whenever
   any assign it receives changes; passing a whole user struct where two
   fields are read re-renders it on every unrelated field change. Split to
   per-component props.
4. **LiveComponents with no `update/2` short-circuit.** An update that never
   compares incoming assigns re-renders on identical data.
5. **Timer ticks that always assign.** A periodic tick that assigns a fresh
   timestamp or re-reads state re-renders on every beat, visible change or
   not. Guard the assign on an actual difference.
6. **Handlers that ignore relevance.** A broad topic handled by re-assigning
   regardless of whether the event concerns anything this socket shows.
   Filter first; assign only on a hit.

For each finding, report the file, function and line, which anti-pattern it
is, the current code, and the guarded or streamed replacement as code.

Rank by frequency times payload: a per-second tick over a large assign
outranks a rare handler over a small one. A re-render that is genuinely
always visible — the value truly changes every time — is correct; say which
you cleared.
