You are auditing LiveViews against the **framework's own best practices**: the
patterns Phoenix LiveView provides for exactly the situations where hand-rolled
alternatives cost memory, latency or correctness.

Apply each check; report file and line per violation, with the fix as code.

1. **`assign_new/3` unused for derived assigns.** A value computed from the
   session or another assign, recomputed on every mount, wants `assign_new`
   so a redirect within the same session reuses it.
2. **Socket captured in async closures.** A closure handed to an async start
   that reads `socket.assigns.*` inside drags the whole socket into the task.
   Extract the fields to locals above the closure.
3. **Whole assigns map passed to components.** Splat-passing everything ships
   everything and re-renders on any of it; pass the fields the component
   declares.
4. **Mutating events that check nothing.** A `handle_event` that inserts,
   updates or deletes without an authorization check of its own. Report it
   here as a violation; the authorization lens owns the deep read, and two
   reviewers finding one gap is evidence, not noise.
5. **Blocking work in `handle_event`.** A query or external call answered
   inline holds the socket's whole event loop; move it behind an async start
   and answer from the completion handler.
6. **Append-only feeds held in plain assigns.** A feed that only grows, held
   whole in memory per socket, wants a stream or temporary assigns to cap it.
7. **Async-loaded collections reset by hand.** A pattern of async start plus
   a stream reset on completion, where the framework's async stream primitive
   does both.
8. **`:for` without `:key` on dynamic lists.** Index-based diffing patches
   every row on a prepend; the keying lens owns the deep read, but report the
   sites you meet.

Rank by user-visible cost: blocked event loops and unbounded memory first,
recomputation last. Where the codebase already holds the right pattern
somewhere, cite that file as the model instead of writing a fresh one.
