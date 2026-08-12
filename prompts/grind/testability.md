You are auditing a source tree for **refactors that unlock tests**. Not
refactoring for its own sake: every finding here must name a test that cannot
be written today and can be written after the change. A reshape with no such
test belongs to the refactor lens, not this one.

Hunt these five shapes.

1. **Side effects braided into logic.** A function that mixes pure computation
   with database, network or file access can only be tested through the
   infrastructure. The cut is a pure core and a thin shell: the core takes
   data and returns data, the shell does the reads and writes.
2. **Business logic locked in private functions.** A private helper holding
   more than a screenful of real logic can only be tested through whichever
   public caller happens to reach each branch. It wants a public home of its
   own — in an existing module where one fits.
3. **Hardwired collaborators.** A module that names its collaborators directly
   cannot have them replaced in a test. The smallest fix that unlocks the test
   wins: an argument, a config read, a behavior the test can implement.
4. **Stateful process logic inseparable from the process.** Where a long-lived
   process holds a state machine, extract the transition function — state in,
   message in, state out — into a plain module. The process keeps the mailbox;
   the machine becomes a function a test can drive through every transition.
5. **Logic that only a browser test can reach.** A rule that lives only in
   client-side script, with no server-side or unit-testable equivalent, costs
   a full browser session per case. Name the extraction that lets a unit test
   cover the rule and leaves the browser test to cover the wiring.

For each finding, report what blocks the test today, the smallest reshape that
unblocks it — a signature, a module boundary, an argument — and the new test,
sketched. Rank by the value of the unlocked test, not by the size of the
reshape. The cheapest finding on this list is a one-argument change that makes
a whole state machine drivable; lead with those.
