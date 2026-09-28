# BraiSEO — current handoff

Updated: 2026-09-28 (user's Claude Code session report + GitHub check). This file is the shared starting point for Claude Code and Codex. Update it with every pushed checkpoint.

## Where the work stands

- Repository: [BraiGAIP/openseo](https://github.com/BraiGAIP/openseo), product name **BraiSEO**. Internal repository and package names still use `openseo`.
- PR #1 was merged into `main` at `6880197d8979b28dd43ad8166f11f70916b78123`. It includes the web app, Python worker, DataForSEO/Serper integrations, keyword difficulty, and SERP change tracking.
- PR #3 merged the Claude/Codex checkpoint instructions into `main` at `1b534114d7e966f951c2981d453b3dce3d4d444d`.
- Detailed phase 1c report: [2026-09-28 session report](2026-09-28-session-report-phase-1c.md). Local checks reported there: 59 worker tests, database tests, and web lint/typecheck/build passed. The user also supplied a Claude Code transcript reporting green PR #1 CI.
- The user confirms that **GitHub Actions secrets have been added**. Do not ask to add them again without first checking a specific missing secret or failed deployment.
- **Deployment still blocked by Fly authentication.** PR #2 was merged into `main` at `a1a3f190f97e3e65b110f8b4b56160c1c7e9848e`; it added Fly organization detection and strips surrounding whitespace from worker credentials. Both new deployment runs failed at the `Create the Fly app if it does not exist` step: `flyctl orgs list --json` returned `Error: unauthorized` ([web run](https://github.com/BraiGAIP/openseo/actions/runs/36427166555), [worker run](https://github.com/BraiGAIP/openseo/actions/runs/36427166875)). The configuration checks passed, so `FLY_API_TOKEN` is present but Fly rejects it for this command. No app was created or deployed by those runs. The user must replace the GitHub `FLY_API_TOKEN` secret with a fresh Fly org-scoped token that can manage the target organization; do not expose token values in logs or commits. Then re-run both failed workflows and inspect the next result.
- Supabase Auth Site URL / Redirect URL and DataForSEO Labs availability have **not** been confirmed by the user in this handoff. The intended auth URL is `https://braiseo-web.fly.dev` and redirect pattern `https://braiseo-web.fly.dev/**`. Do not change production settings based only on this note.
- The repository is public. Do not commit secrets, environment files, or customer data.

## Urgent next action

1. The user replaces the existing GitHub Actions `FLY_API_TOKEN` with a freshly generated Fly org-scoped token for the organization that will host `braiseo-web` and `braiseo-workers`. The token must be updated in GitHub directly; never paste it into a chat or repository.
2. Re-run the failed web and worker deploy workflows. If they reach the next stage, inspect any new failure and address it without leaking credentials. If Fly lists multiple organizations, set the non-secret repository variable `FLY_ORG` to the intended slug.
3. Verify the app and a real login and data flow before saying it is live. Confirm Supabase Auth URLs and DataForSEO Labs only if needed.
4. On returning to the interrupted Claude Code environment, preserve any unpushed edits (`git status`). Once deployment is stable, resume SERP change alerts and later the site audit crawler.

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
