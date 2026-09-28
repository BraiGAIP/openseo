# BraiSEO — current handoff

Updated: 2026-09-28, 17:33 EEST. Shared starting point for Claude Code and Codex.

## Repository and checkpoint

- Repository: [BraiGAIP/openseo](https://github.com/BraiGAIP/openseo); product name **BraiSEO**. Internal repository and package names still use `openseo`.
- This checkpoint branch: [`codex/deploy-success-handoff-20260928`](https://github.com/BraiGAIP/openseo/tree/codex/deploy-success-handoff-20260928), based on `main` commit `fb0fbe231831822fbe78dcb4b53f58a2e6689a7f`. Use the branch link for its current pushed tip.
- PR #1 (application) and PR #2 (Fly workflow fix) are merged into `main`. PR #3 added the shared Claude/Codex instructions. Detailed feature and test history: [phase 1c report](2026-09-28-session-report-phase-1c.md).
- If resuming an interrupted local Claude Code session, run `git status` and preserve any unpushed local edits before switching branches.

## Deployment verified on 2026-09-28

- Fly organization is **BRAI apps**, slug `brai-apps`. GitHub Actions reads the non-secret repository variable `FLY_ORG=brai-apps`.
- The user replaced the `FLY_API_TOKEN` repository secret with a new organization token at 17:28 EEST. The token value was not read, logged, or committed. Earlier tokens and the earlier failed workflow attempts are historical; do not troubleshoot from those failures as if they were current.
- [Web deployment run](https://github.com/BraiGAIP/openseo/actions/runs/36427166555), latest job `108975283537`: **success**. Fly app `braiseo-web` was created and deployed; the workflow smoke test for `/fi` passed. A browser opened [the Finnish landing page](https://braiseo-web.fly.dev/fi) and [the login form](https://braiseo-web.fly.dev/fi/login); both displayed BraiSEO.
- [Worker deployment run](https://github.com/BraiGAIP/openseo/actions/runs/36427166875), latest job `108975378216`: **success**, including app creation, staging secrets, deployment, and `flyctl status`. Fly app name: `braiseo-workers`.
- These checks establish that both deployments completed and the public web pages load. No real sign-in, Supabase data flow, or scheduled rank check has been verified yet.

## Next actions and open decisions

1. Inspect the existing Supabase Auth Site URL and redirect allow-list. Intended values are `https://braiseo-web.fly.dev` and `https://braiseo-web.fly.dev/**`; their current settings have not been confirmed. Do not overwrite blindly.
2. Verify a real email-link sign-in and a complete rank-check/data flow. Confirm DataForSEO Labs availability; the KD column depends on it. Handle tokens and customer data only through the intended secret stores.
3. The publicly reachable landing page currently says `Avoin lähdekoodi · AGPL-3.0` and displays Free/Pro/Agency prices. The owner had left the license decision open; confirm the desired public claims and prices before wider launch.
4. Once deployment and data flow are stable, continue SERP change alerts and later the site-audit crawler.

## Checkpoint routine

Work on a task branch, commit and push coherent changes, and update this file with the branch, pushed tip, verification, next action, and blockers. Check GitHub received the push. Never commit secrets, environment files, or customer data. Do not merge or deploy solely to save a checkpoint.
