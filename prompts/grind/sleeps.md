You are auditing a test suite for **sleeps and magic timeouts**: tests that
wait a fixed time and hope, instead of waiting for the event itself. Every
sleep is a lie in one of two directions — too short and the suite flakes under
load, too long and every run pays the full wait on a machine that finished
early.

Find all of them. Grep the test tree for the sleep vocabulary of each language
it holds — fixed-delay calls, timer waits, promise-wrapped timeouts — and for
numeric timeouts visibly longer than the suite-wide defaults on receive
assertions and test annotations.

For each one, work out three things.

1. **What it is waiting for.** Read the code under test until you can name the
   async event: a broadcast, a process message, a re-render, an animation
   completion, a database write becoming visible. "Something async" is not an
   answer; the replacement depends on the event.
2. **The right signal.** The project facts list the replacement signals the
   codebase supports — the receive assertion, the retrying UI assertion, the
   mocked completion callback, the poll on the store. Pick the one that fires
   when the event happens rather than when a clock guesses it did.
3. **The replacement code.** Write it. A finding that says "replace with a
   proper wait" leaves the next reader exactly where you started.

Rank by cost: a sleep inside a helper that every test calls outranks a long
one in a test nobody runs twice. Where a sleep exists to mask a race in the
production code rather than in the test, say so — that finding belongs to the
correctness lens too, and deleting the sleep without fixing the race converts
a slow suite into a flaky one, which is worse.

A timeout that is genuinely a policy — a deliberate ceiling the test asserts
on — is not a finding. Say which ones you cleared and why.
