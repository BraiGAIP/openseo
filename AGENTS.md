# BraiSEO: Codex working instructions

This repository is shared with Claude Code. Read `docs/handoff/CURRENT.md` first, then the relevant parts of `docs/ARCHITECTURE.md`.

- Start from the branch and commit recorded in the handoff. Check the actual remote state and inspect pending changes before editing.
- Use a task branch. Preserve work already in progress; do not reset, discard, or silently overwrite edits from Claude or another agent.
- Make small, tested checkpoints: commit and push after each coherent piece of work and before ending the session. Update `docs/handoff/CURRENT.md` with branch, latest commit, what changed, next action, tests, and blockers.
- Verify that GitHub received the push before calling the work saved or available to the other assistant.
- Never commit secrets, environment files, or customer data. Do not merge or deploy just to save a checkpoint.
- If remote access or a push is unavailable, report precisely which changes remain local and how to retrieve them.
