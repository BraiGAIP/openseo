# BraiSEO — current handoff

Updated: 2026-09-28 (user's Claude Code session report + GitHub check). This file is the shared starting point for Claude Code and Codex. Update it with every pushed checkpoint.

## Where the work stands

- Repository: [BraiGAIP/openseo](https://github.com/BraiGAIP/openseo), product name **BraiSEO**. Internal repository and package names still use `openseo`.
- PR #1 was merged into `main` at `6880197d8979b28dd43ad8166f11f70916b78123`. It includes the web app, Python worker, DataForSEO/Serper integrations, keyword difficulty, and SERP change tracking.
- PR #3 merged the Claude/Codex checkpoint instructions into `main` at `1b534114d7e966f951c2981d453b3dce3d4d444d`.
- Detailed phase 1c report: [2026-09-28 session report](2026-09-28-session-report-phase-1c.md). Local checks reported there: 59 worker tests, database tests, and web lint/typecheck/build passed. The user also supplied a Claude Code transcript reporting green PR #1 CI.
- The user confirms that **GitHub Actions secrets have been added**. Do not ask to add them again without first checking a specific missing secret or failed deployment.
- **Deployment remains unresolved.** Both Fly deployment runs after PR #1 failed. Claude's fix is already pushed in [draft PR #2](https://github.com/BraiGAIP/openseo/pull/2), commit `4c4d3970447ff718ee845fda296dc128831f5694`; GitHub shows 5/5 CI checks passing. It replaces the hardcoded Fly organization with optional `FLY_ORG` or detection via `flyctl orgs list --json`, and strips surrounding whitespace from worker credentials to handle a reported U+2028 separator. **PR #2 is not merged or deployed.** Its merge triggers both Fly deployment workflows; verify deployment and authentication afterward. Any additional local/unpushed edits cannot be inspected here.
- Supabase Auth Site URL / Redirect URL and DataForSEO Labs availability have **not** been confirmed by the user in this handoff. The intended auth URL is `https://braiseo-web.fly.dev` and redirect pattern `https://braiseo-web.fly.dev/**`. Do not change production settings based only on this note.
- The repository is public. Do not commit secrets, environment files, or customer data.

## Urgent next action

1. Resume from [draft PR #2](https://github.com/BraiGAIP/openseo/pull/2); review the fix and check whether the interrupted Claude environment has any additional unpushed changes (`git status`). Preserve them.
2. When authorized to deploy, mark PR #2 ready and merge it. This triggers both Fly deployment workflows. Confirm the actual web and worker runs and fix any new failures. Do not print or commit secret values.
3. Verify a real login and data flow before describing the app as deployed. Confirm the Supabase Auth URLs and DataForSEO Labs if needed.
4. Once deployment is stable, resume SERP change alerts and later the site audit crawler.

## Checkpoint routine

- Work in a task branch. After each coherent piece of work, update this file with the **pushed** branch and commit, completed work, verification, exact next action, blockers, and production changes; commit and push. Do not merge or deploy just to save a checkpoint.
- If GitHub push fails, state plainly that the changes remain only in the current environment.

## Next checkpoint template

- Branch and latest **pushed** commit:
- Completed since last checkpoint:
- Verification / tests:
- Pending work and exact next action:
- Blockers or external configuration still needed:
- Production changes applied or pending:
