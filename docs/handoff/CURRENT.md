# BraiSEO — current handoff

Updated: 2026-09-28 (user's Claude Code session report + GitHub check). This file is the shared starting point for Claude Code and Codex. Update it with every pushed checkpoint.

## Where the work stands

- Repository: [BraiGAIP/openseo](https://github.com/BraiGAIP/openseo), product name **BraiSEO**. Internal repository and package names still use `openseo`.
- PR #1 was merged into `main` at `6880197d8979b28dd43ad8166f11f70916b78123`. It includes the web app, Python worker, DataForSEO/Serper integrations, keyword difficulty, and SERP change tracking.
- PR #3 merged the Claude/Codex checkpoint instructions into `main` at `1b534114d7e966f951c2981d453b3dce3d4d444d`.
- Detailed phase 1c report: [2026-09-28 session report](2026-09-28-session-report-phase-1c.md). Local checks reported there: 59 worker tests, database tests, and web lint/typecheck/build passed. The user also supplied a Claude Code transcript reporting green PR #1 CI.
- The user confirms that **GitHub Actions secrets have been added**, and reports updating `FLY_API_TOKEN` at about 16:28 EEST on 2026-09-28. Do not ask to add all secrets again. Check the exact token type, destination secret name and Fly organization access if authorization remains invalid.
- **Deployment still blocked by Fly authentication.** PR #2 was merged into `main` at `a1a3f190f97e3e65b110f8b4b56160c1c7e9848e`; it added Fly organization detection and strips surrounding whitespace from worker credentials. Both new deployment runs failed at the `Create the Fly app if it does not exist` step: `flyctl orgs list --json` returned `Error: unauthorized` ([web run](https://github.com/BraiGAIP/openseo/actions/runs/36427166555), [worker run](https://github.com/BraiGAIP/openseo/actions/runs/36427166875)). The configuration checks passed, so `FLY_API_TOKEN` is present but Fly rejects it for this command. No app was created or deployed by those runs. At the user's request, both failed workflows were rerun after a reported token update. The new web job `108949593976` and worker job `108949695339` again failed at `flyctl orgs list --json` with `Error: unauthorized`. Check whether the updated secret is the full Fly org-scoped token for the correct organization and is saved under `BraiGAIP/openseo` → Actions → `FLY_API_TOKEN`. Do not expose token values in logs or commits. Do not blindly rerun again until the token identity and location are confirmed.
- Supabase Auth Site URL / Redirect URL and DataForSEO Labs availability have **not** been confirmed by the user in this handoff. The intended auth URL is `https://braiseo-web.fly.dev` and redirect pattern `https://braiseo-web.fly.dev/**`. Do not change production settings based only on this note.
- The repository is public. Do not commit secrets, environment files, or customer data.

## Urgent next action

1. Verify the Fly token's **type and organization** in the Fly dashboard, and verify that the GitHub Actions repository secret named exactly `FLY_API_TOKEN` in `BraiGAIP/openseo` shows a recent update. Check that the full token, including the `FlyV1 ` prefix, was copied. Never paste the token into a chat or repository.
2. Once the token is confirmed/corrected, start a fresh web and worker deployment and inspect each stage. If Fly lists multiple organizations, set the non-secret repository variable `FLY_ORG` to the intended slug.
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
