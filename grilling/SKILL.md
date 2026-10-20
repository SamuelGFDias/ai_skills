---
name: grilling
description: Grill the user relentlessly about a plan, decision, or idea. Use when the user wants to stress-test their thinking, or uses any 'grill' trigger phrases.
---

Interview the user relentlessly until you reach a shared understanding. Map this as a **design tree**: every decision branches into the decisions that hang off it.

Work the tree in **rounds**. The **frontier** is every decision whose prerequisites are already settled: the questions you can ask _now_ without guessing at answers you haven't heard yet. Ask the frontier in one round, then wait for the user's answers before the next round.

**Always ask through the `AskUserQuestion` tool, never as free text in the chat.** The tool is deferred: load it with `ToolSearch` (`select:AskUserQuestion`) before the first use. Rules:

- One call takes 1-4 questions. If the frontier has more than 4, send the 4 most blocking ones and the rest in the next call of the same round.
- Each question: a short `header` (the question title), a `question` body that ends with `?`, and 2-4 mutually exclusive `options` (use `multiSelect: true` only when the choices are not exclusive). Put the facts and trade-offs in each option's `description`.
- Put your recommended answer **first**, labelled with "(Recommended)". Word each question so accepting the recommendation is the easy path. Don't add an "Other" option; the tool provides it.
- Don't ask what has a conventional default or what you can verify yourself; decide that and mention it.

Each round the user answers reshapes the tree: settled decisions push the frontier outward and unblock questions that depended on them. Recompute the frontier and ask the next round. A question whose answer depends on another question still open in this round belongs to a _later_ round, not this one.

Finding _facts_ is your job, never the user's. When a frontier question needs a fact from the environment (filesystem, tools, etc.), dispatch a sub-agent to find it; don't ask the user for anything you could look up yourself. Don't block on it: a running exploration is an unsettled prerequisite, so only the questions downstream of it wait for the sub-agent to report; ask the rest of the frontier now. The _decisions_ are the user's: put each to them and wait.

The session is done when the frontier is empty: every branch of the design tree visited, nothing left silently assumed. Do not act on it until the user confirms you have reached a shared understanding.
