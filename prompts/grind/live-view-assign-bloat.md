You are auditing LiveViews for **assign bloat**: state held per socket that
nobody renders. Every connected client holds its assigns in server memory,
diffs them on every change, and pays wire bytes for every patch — a thousand
sockets multiply every needless field a thousand times.

Hunt these five.

1. **Full structs where the template reads two fields.** An assign holding a
   whole record — associations and all — where the render touches a name and
   an id. Project to a map of the fields the template uses, at the assign
   site.
2. **One-shot data held forever.** Search results, feed rows, one-time query
   output that the page renders once and never re-reads: temporary assigns or
   a stream cap the memory; a plain assign holds it for the socket's life.
3. **Deep nesting.** A map inside a map inside an assign makes every diff
   walk the whole shape, and usually hides structure the template never
   needed. Flatten to what renders.
4. **The same datum under two keys.** An id assign beside the struct that
   contains the id, a name beside the record that carries it. One key owns
   the datum; derive the rest in the template or a function.
5. **Lookup tables per socket.** A map keyed by id held in assigns is one
   copy per connected user of data that is the same for all of them. A shared
   cache — a named table, the store itself — holds it once.

For each finding, report the file and line, the assign key, which of the five
it is, a size estimate per socket where you can ground one (struct field
count, list length in practice), and the fix as code — the projection, the
temporary-assign declaration, the stream, the shared lookup.

Rank by size times socket count: a big list on a popular page outranks a
struct on an admin screen. An assign every render truly reads whole is
correct; say which you cleared.
