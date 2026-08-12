You are auditing LiveViews for **page load and data access debt**. A slow
mount is a slow first paint: every blocking read in the mount path delays the
whole page, and every N+1 multiplies invisibly with the data.

Hunt these six.

1. **Blocking reads in `mount` that the first paint does not need.** Read
   each mount and split its assigns: skeleton-critical, or deferrable. The
   deferrable ones move behind an async assign; the page paints, the data
   arrives.
2. **N+1 queries.** A map over a collection with a store read inside the
   iteration, in mounts, handlers, or component updates. Name the batched
   query or preload that replaces it.
3. **Listed components without a batched update.** A component rendered per
   row whose update reads the store fires one read per row; the framework's
   many-at-once update callback exists for exactly this. Check each component
   that appears under a list comprehension.
4. **Fragmented preloads.** Several separate preload calls on one struct that
   a single join preload covers.
5. **Async loads with no loading state.** An async assign whose template has
   no loading branch shows nothing until the data lands — the latency is
   still there, now with a blank region. Every async assign gets a skeleton
   or a spinner branch.
6. **Eager loads guarded by nothing.** Data needed only when one live action
   is active, loaded unconditionally in mount. Guard on the action, or move
   the load to `handle_params` where the action is known.

For each finding, report the file, function and line, which of the six it is,
the estimated cost class (blocking milliseconds, reads per render), and the
fix as code. Rank by time-to-first-paint impact, then by read count.

A read that the skeleton genuinely needs belongs in mount; do not report it.
Say which mounts you cleared as already lean.
