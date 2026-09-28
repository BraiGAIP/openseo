# BraiSEO: Claude Code working instructions

This repository is the shared source of truth for Claude Code and Codex. Read `docs/handoff/CURRENT.md` and the relevant architecture notes before changing code.

- Work in a task branch. Never reset, discard, or overwrite changes in an existing working tree.
- After each coherent piece of work, commit and push the branch to GitHub. Make a checkpoint before a long-running task, before pausing, and before ending a session. Do not wait for the whole project to finish.
- Update `docs/handoff/CURRENT.md` at each checkpoint with the branch, latest commit, completed work, next action, tests, and blockers. Push that update with the code. A local commit alone is not available to the other assistant.
- Confirm that the push succeeded. If it fails, say explicitly that the latest work exists only in the current environment and give the local branch/commit.
- Do not put API keys, passwords, access tokens, customer data, or environment files into Git. Keep migrations and production changes distinct; record what was applied and what remains pending.
- Do not merge into `main` or deploy simply to make a checkpoint. Use the feature branch and a pull request when ready.
- When handing off, give the GitHub repository, branch, latest pushed commit, and link to `docs/handoff/CURRENT.md`.

A browser or cloud session and a Desktop local session may use different working copies. Check `git status` before switching environments; uncommitted local edits are not in GitHub.
