# BraiSEO — current handoff

Updated: 2026-09-28 (user's Claude Code session report + GitHub check). This file is the shared starting point for Claude Code and Codex. Update it with every pushed checkpoint.

## Where the work stands

- Repository: [BraiGAIP/openseo](https://github.com/BraiGAIP/openseo), product name **BraiSEO**. Internal repository and package names still use `openseo`.
- PR #1 was merged into `main` at `6880197d8979b28dd43ad8166f11f70916b78123`. It includes the web app, Python worker, DataForSEO/Serper integrations, keyword difficulty, and SERP change tracking.
- PR #3 merged the Claude/Codex checkpoint instructions into `main` at `1b534114d7e966f951c2981d453b3dce3d4d444d`.
- Detailed phase 1c report: [2026-09-28 session report](2026-09-28-session-report-phase-1c.md). Local checks reported there: 59 worker tests, database tests, and web lint/typecheck/build passed. The user also supplied a Claude Code transcript reporting green PR #1 CI.
- The user confirms that **GitHub Actions secrets have been added**, and reports updating `FLY_API_TOKEN` at about 16:28 EEST on 2026-09-28. Do not ask to add all secrets again. Check the exact token type, destination secret name and Fly organization access if authorization remains invalid.
- **Deployment still blocked by Fly authentication.** PR #2 was merged into `main` at `a1a3f190f97e3e65b110f8b4b56160c1c7e9848e`; it added Fly organization detection and strips surrounding whitespace from worker credentials. Both new deployment runs failed at the `Create the Fly app if it does not exist` step: `flyctl orgs list --json` returned `Error: unauthorized` ([web run](https://github.com/BraiGAIP/openseo/actions/runs/36427166555), [worker run](https://github.com/BraiGAIP/openseo/actions/runs/36427166875)). The configuration checks passed, so `FLY_API_TOKEN` is present but Fly rejects it for this command. No app was created or deployed by those runs. At the user's request, both failed workflows were rerun after a reported token update. The second web job `108949593976` and worker job `108949695339` again failed at `flyctl orgs list --json` with `Error: unauthorized`. The user then created/saved a new Fly organization token for **BRAI apps** under the existing `FLY_API_TOKEN` secret. The third reruns, web job `108953652396` and worker job `108953747709`, still failed at `flyctl orgs list --json`, this time with `401 Unauthorized` followed by the workflow's misleading `Several Fly organizations ()` message. The workflow currently leaves `FLY_ORG` unset and attempts to list organizations even with an organization-scoped token. Set the non-secret Actions repository variable `FLY_ORG` to the exact slug of BRAI apps from its Fly dashboard URL, then rerun both failed deployments. This skips the failing organization-list call. If `flyctl apps create` still returns 401, troubleshoot the token's permissions and exact secret value at that stage. Do not expose token values in logs or commits.
- Supabase Auth Site URL / Redirect URL and DataForSEO Labs availability have **not** been confirmed by the user in this handoff. The intended auth URL is `https://braiseo-web.fly.dev` and redirect pattern `https://braiseo-web.fly.dev/**`. Do not change production settings based only on this note.
- The repository is public. Do not commit secrets, environment files, or customer data.

## Urgent next action

1. Obtain the exact slug of the Fly organization **BRAI apps** from its Fly dashboard URL. Set it as the non-secret GitHub Actions repository variable `FLY_ORG` in `BraiGAIP/openseo` → Settings → Secrets and variables → Actions → Variables. Its display name is not necessarily the slug. Do not paste the token into chat.
2. Rerun failed web and worker deployments and inspect each stage. If app creation still reports 401, investigate token permissions or whether the full `FlyV1 ` value was saved in `FLY_API_TOKEN`.
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
