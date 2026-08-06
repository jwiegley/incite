You have just committed your work. Before continuing, get it independently audited.

Call the `fess-audit` tool (exposed by the agent-functor MCP server). You do not
need to pass anything to it — agent-functor hands the auditor your full
conversation so far, and it runs on a different backend so its judgement is
genuinely independent of yours.

The call returns a run id immediately. Poll the `output` tool with that run id
until the run reports `finished`, then read the findings. For every finding that
is real, fix it now. If it reports nothing actionable, say so in one line and move
on. Do not skip the audit, and do not argue findings away without evidence.

Keep the working plan as your output for the next step.
