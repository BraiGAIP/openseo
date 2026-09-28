# BraiSEO — current handoff

Updated: 2026-09-28 (user's Claude Code session report + GitHub check). This file is the shared starting point for Claude Code and Codex. Update it with every pushed checkpoint.

## Where the work stands

- Repository: [BraiGAIP/openseo](https://github.com/BraiGAIP/openseo), product name **BraiSEO**. Internal repository and package names still use `openseo`.
- PR #1 was merged into `main` at `6880197d8979b28dd43ad8166f11f70916b78123`. It includes the web app, Python worker, DataForSEO/Serper integrations, keyword difficulty, and SERP change tracking.
- PR #3 merged the Claude/Codex checkpoint instructions into `main` at `1b534114d7e966f951c2981d453b3dce3d4d444d`.
- Detailed phase 1c report: [2026-09-28 session report](2026-09-28-session-report-phase-1c.md). Local checks reported there: 59 worker tests, database tests, and web lint/typecheck/build passed. The user also supplied a Claude Code transcript reporting green PR #1 CI.
- The user confirms that **GitHub Actions secrets have been added**. Do not ask to add them again without first checking a specific missing secret or failed deployment.
- **Deployment remains unresolved.** The supplied Claude Code transcript says both Fly deployments failed soon after PR #1 was merged. Claude's investigation identified a hardcoded `personal` Fly organization and a suspected invisible character in the DataForSEO password secret. Claude started working on a fix, but at this checkpoint no new deployment-fix branch or PR was visible via the connected GitHub repository; local/unpushed edits cannot be inspected here. Do not claim the app is live.
- Supabase Auth Site URL / Redirect URL and DataForSEO Labs availability have **not** been confirmed by the user in this handoff. The intended auth URL is `https://braiseo-web.fly.dev` and redirect pattern `https://braiseo-web.fly.dev/**`. Do not change production settings based only on this note.
- The repository is public. Do not commit secrets, environment files, or customer data.

## Urgent next action

1. In the interrupted Claude Code environment, check its branch and `git status`; preserve and push any unfinished Fly deployment fix before closing or resetting that environment. Another assistant cannot see local edits.
2. Inspect the failed GitHub Actions deployment logs and the active Fly organization. If the fix was already pushed, resume its branch or PR; otherwise implement and push a small branch with the verified fix. Avoid printing or committing secret values.
3. Run the relevant tests/CI, then check a fresh web and worker deployment and a real login before describing the app as deployed.
4. Once deployment is stable, resume the phase 1c report's next tasks: SERP change alerts and later the site audit crawler.

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
