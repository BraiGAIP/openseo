# OpenSEO – istuntoraportti 27.9.2026

> **Tarkoitus:** tästä tiedostosta uusi Claude Code -istunto jatkaa suoraan.
> **Sijainti:** repo `BraiGAIP/openseo`, haara `claude/phase-1-mvp`, polku `docs/handoff/2026-09-27-session-report.md`.
> Kun haaran PR on mergetty, sama tiedosto löytyy `main`-haarasta.

---

## 1. Tiivistelmä

| Osa-alue | Tila |
|---|---|
| Arkkitehtuuri & päätökset (D1–D14) | ✅ valmis – `docs/ARCHITECTURE.md` |
| GitHub-repo `BraiGAIP/openseo` | ✅ luotu, `main` sisältää vaiheen 0 (historia säilytetty) |
| Supabase-projekti "OpenSEO" | ✅ käytössä, 4 migraatiota ajettu, pg_cron-ajastukset päällä |
| Tietokantatestit (RLS, kiintiöt, jono) | ✅ 13 skenaariota, CI vihreä `main`-haarassa |
| Vaihe 1a – web-sovellus (Next.js 16) | ✅ runko valmis haarassa `claude/phase-1-mvp` (lint, typecheck, build OK) |
| Vaihe 1b – Python-worker (Fly.io) | ⏳ **ei aloitettu** – seuraava tehtävä |
| Väliaikainen PR `BraiGAIP/akku-turvan-mestari#4` | ⚠️ suljettava käsin (Claude-sovelluksella ei oikeutta) |

---

## 2. Tehdyt päätökset (käyttäjän hyväksymät)

1. **Oma repo + oma Supabase-projekti** EU-alueella → toteutettu.
2. **Lisenssi AGPL-3.0** → `LICENSE` repon juuressa.
3. **Markkina:** kansainvälinen, englanti ensin, **fi/sv**-käännökset valmiina.
4. **Hinnoittelu:** Free 0 €, Pro 49 €/kk, Agency 149 €/kk (+ Enterprise sopimuksella) → seedattu `public.plans`-tauluun.
5. **AI:** kevyet mallit + Batch API massatöihin, Opus syvällisiin analyyseihin (bulk = `claude-haiku-4-5`, standard = `claude-sonnet-5`, deep = `claude-opus-5`).
6. **Workerit:** Fly.io, region `fra`.

Kaikki perustelut: `docs/ARCHITECTURE.md` §0 (päätösloki).

---

## 3. Ympäristöt ja tunnisteet

| Asia | Arvo |
|---|---|
| GitHub-repo | https://github.com/BraiGAIP/openseo (yksityinen) |
| Kehityshaara | `claude/phase-1-mvp` |
| Supabase-projekti | `OpenSEO`, ref **`itxtluifqbxxrealkpfj`**, region `eu-central-1`, Postgres 17, **Free-taso** |
| Supabase URL | `https://itxtluifqbxxrealkpfj.supabase.co` |
| Julkinen avain | Supabase Dashboard → Project Settings → API Keys (`sb_publishable_…`) – **ei repossa**, `apps/web/.env.local` |
| pg_cron | `openseo-enqueue-rank-checks` (10 min), `openseo-maintenance` (03:17), `openseo-stripe-usage-sync` (15 min) |
| Storage-bucketit | `reports`, `branding` (RLS: polun 1. kansio = organization_id) |

### Migraatiot (tiedostonimi = Supabasen historiaversio)

| Tiedosto | Sisältö |
|---|---|
| `20260927110858_openseo_core_schema.sql` | Koko multi-tenant-skeema, RLS, RPC:t, seed (paketit, 25 audit-tarkistusta) |
| `20260927110923_openseo_scheduling.sql` | pg_cron + 3 ajastusta |
| `20260927111357_openseo_fk_indexes.sql` | FK-indeksit (Supabase advisor: 0 unindexed FK) |
| `20260927120117_openseo_rank_summary.sql` | `ctr_for_position()` + `project_rank_summary()` dashboardille |

Tuotantokannan skeeman sormenjälki on todettu identtiseksi testatun kannan kanssa (`tests/db/fingerprint.sql`).

---

## 4. Mitä tässä istunnossa rakennettiin (vaihe 1a, haara `claude/phase-1-mvp`)

**Monorepo (npm workspaces):** `apps/web`, `packages/shared`; juuren `package.json`-skriptit `dev`, `build`, `lint`, `typecheck`, `test:db`.

**`packages/shared`**
- `src/database.types.ts` – Supabasesta generoidut tyypit (sis. `project_rank_summary`).
- `src/index.ts` – `Tables`/`Enums`-apurit, `LOCALES`, `PlanLimits`, `SEARCH_LOCATIONS` (DataForSEO-sijaintikoodit).

**`apps/web` (Next.js 16.3, React 19.2, Tailwind v4, next-intl 4, @supabase/ssr 0.12, Recharts 3)**
- **i18n:** `src/i18n/{routing,request,navigation}.ts`, käännökset `messages/{en,fi,sv}.json` (avaimet täsmäävät). Englanti `/`, suomi `/fi`, ruotsi `/sv`. Kieli luetaan `next/root-params`-rajapinnalla.
- **Proxy:** `src/proxy.ts` (Next 16:ssa `middleware` → `proxy`): next-intl-reititys + Supabase-session päivitys + `/app`-polkujen suojaus.
- **Auth:** magic link (`app/[locale]/login`), callback `app/auth/callback/route.ts` (PKCE code tai token_hash).
- **Sivut:**
  - `/` – etusivu + hinnasto (luetaan `public.plans`-taulusta anon-avaimella).
  - `/app` → ohjaa ensimmäiseen työtilaan.
  - `/app/[org]` – projektit, uusi projekti -lomake (admin/owner), kiintiöiden käyttö (`get_usage_summary`).
  - `/app/[org]/projects/[projectId]` – KPI-kortit (seurattavat, keskisijoitus, top 3, top 10, näkyvyys + muutos jakson alusta), sijoituskaavio (käänteinen y-akseli, max 8 avainsanaa, värit pysyvät avainsanalla), avainsanataulukko (muutos ▲/▼, paras, volyymi, URL), avainsanojen lisäys (monta riviä kerralla) ja poisto, aikavälivalinta 7/30/90 pv.
- **Server actions:** `app/[locale]/app/actions.ts` – `createProject`, `addKeywords` (upsert, duplikaatit ohitetaan), `deleteKeyword`, `loadKeywordHistory`, `signOut`. Virheet mapataan käännettäviksi koodeiksi (`lib/errors.ts`, esim. `plan_limit_exceeded:max_keywords`).
- **Datakerros:** `src/lib/data.ts` (kaikki kyselyt käyttäjän JWT:llä → RLS pätee).
- **Visualisointi:** dataviz-ohjeiden mukainen validoitu 8-värinen paletti light/dark (`src/app/globals.css`), taulukkonäkymä kaavion rinnalla, tooltip + selite.

**Tietokanta:** uusi migraatio 0004 + testit (`project_rank_summary` kunnioittaa RLS:ää).

**CI (`.github/workflows/ci.yml`):** DB-testit + web (lint, typecheck, build).

### Varmennettu
- `npm run lint` ✅ · `npm run typecheck` ✅ · `npm run build` ✅ (myös ilman ympäristömuuttujia)
- `tests/db/run.sh` → ALL TESTS PASSED
- Ajotesti: `/`, `/fi`, `/sv` renderöityvät oikeilla kielillä (200), `/login` 200, `/app` ja `/fi/app/...` ohjaavat kirjautumiseen (307).

### Ei varmennettu (ja miksi)
- **Kirjautuminen ja hinnasto tuotantokantaa vasten:** tämän pilvi-istunnon verkkorajoitus estää yhteydet `*.supabase.co`-osoitteeseen. Sovellus käsittelee tämän siististi (hinnasto piilotetaan). Testattava omalla koneella tai Vercelissä.

---

## 5. Käyttäjän tehtävät (tarvitaan ennen täyttä käyttöä)

1. **Sulje PR** https://github.com/BraiGAIP/akku-turvan-mestari/pull/4 mergeämättä (Claude ei saanut oikeutta).
2. **Supabase Auth -asetukset** (Dashboard → Authentication → URL Configuration):
   - Site URL: tuotanto-osoite (esim. `https://app.openseo.xyz`) – kehityksessä `http://localhost:3000`
   - Redirect URLs: `http://localhost:3000/auth/callback`, `https://<tuotanto>/auth/callback`, Vercel preview `https://*-braigaip.vercel.app/auth/callback`
3. **Paikallinen ajo:** `apps/web/.env.local` (katso `.env.example`), sitten `npm install && npm run dev`.
4. **DataForSEO-tili** (vaihe 1b): tunnukset tarvitaan oikeaan sijoitusdataan. Ilman niitä worker toimii mock-providerilla.
5. **Ennen ensimmäistä maksavaa asiakasta:** Supabase-organisaatio Pro-tasolle (25 $/kk: varmuuskopiot/PITR, ei pysähtymistä).
6. **Connectorit:** Stripe-connector vaatii valtuutuksen claude.ai:n asetuksissa (vaihe 4).

---

## 6. Seuraavat askeleet (vaihe 1b → 2)

### 6.1 Python-worker (seuraava tehtävä)
Hakemisto `workers/python/`:
- `openseo_workers/runner.py` – silmukka `claim_jobs` → dispatch → `heartbeat_job` (30 s) → `complete_job`/`fail_job` (RPC:t ovat jo kannassa, vain `service_role`).
- `providers/` – `SerpProvider`-protokolla + `mock`, `dataforseo` (Standard queue, adaptiivinen syvyys), `serper` (fallback), `provider_cache`-välimuisti.
- `rank/handler.py` – `rank_check`-jobi: payload `{"keyword_ids": [...], "check_date": "YYYY-MM-DD"}` → hae SERP → upsert `keyword_positions (keyword_id, check_date)` (trigger päivittää `keyword_tracking`-snapshotin) → `record_usage('serp_query', …, p_enforce_quota => false, provider_cost_usd)`.
- Testit: pytest + end-to-end paikallista Postgresia vasten (`tests/db/supabase_stub.sql` + migraatiot) mock-providerilla: `enqueue_due_rank_checks()` → claim → positions → snapshot.
- `Dockerfile`, `fly.toml` (process groups `rank`, `crawl`, `render`, `ai`, `misc`; region `fra`), yhteys Supavisorin kautta (`DATABASE_URL`, transaction mode 6543).

### 6.2 Muut vaiheen 1 viimeistelyt
- Organisaatioasetukset (nimi, kieli, jäsenten kutsu `invite_member` / `accept_invitation`).
- Vercel-deploy + ympäristömuuttujat.
- Playwright-savutesti kirjautumisesta (tarvitsee Supabase-yhteyden).

### 6.3 Vaihe 2
Site audit -crawler (25 tarkistusta, `request_site_audit` RPC valmiina), kilpailijat + keyword gap.

---

## 7. Tärkeät tekniset huomiot uudelle istunnolle

- **Next.js 16 poikkeaa koulutusdatasta:** lue `node_modules/next/dist/docs/` ennen koodausta (`apps/web/AGENTS.md`). Keskeiset: `proxy.ts` (ei `middleware.ts`), async `params`/`searchParams`/`cookies()`, `PageProps<'/route'>`/`LayoutProps` -tyyppiapurit, `next typegen` ennen `tsc`.
- **Migraatioiden ajo Supabaseen:** Supabase MCP `apply_migration` → nimeä tiedosto **Supabasen tallentaman version** mukaan (`select version,name from supabase_migrations.schema_migrations`), jotta `supabase db push` ei aja sitä uudelleen. Aja aina ensin `tests/db/run.sh` ja lopuksi sormenjälkivertailu (`FINGERPRINT=1 tests/db/run.sh` vs. `tests/db/fingerprint.sql` tuotannossa).
- **Tyyppien päivitys** migraation jälkeen: Supabase MCP `generate_typescript_types` → `packages/shared/src/database.types.ts`.
- **Tenant-turva:** älä koskaan luota asiakkaan `organization_id`:hen – triggerit johtavat sen. Maksulliset toiminnot RPC:n kautta, plan-rajat triggereissä.
- **Kaavion värit:** paletin järjestys on CVD-turvallisuusmekanismi – älä järjestä uudelleen; max 8 sarjaa; väri seuraa avainsanaa, ei järjestystä.
- **Verkko:** tämän ympäristön egress estää `*.supabase.co`, `dataforseo.com` ja `gnu.org`; npm- ja PyPI-rekisterit toimivat.

---

## 8. Aloituskehote uuteen istuntoon

Kopioi tämä uuden Claude Code -istunnon ensimmäiseksi viestiksi (valitse repoksi `BraiGAIP/openseo`):

```
Jatka OpenSEO-projektia. Lue ensin docs/handoff/2026-09-27-session-report.md
haarasta claude/phase-1-mvp sekä docs/ARCHITECTURE.md. Tee seuraavaksi
vaihe 1b: Python-worker (workers/python) – runner, providers (mock, DataForSEO,
Serper), rank_check-handler, pytest + end-to-end-testi paikallista Postgresia
vasten, Dockerfile ja fly.toml. Jatka samaan haaraan ja päivitä raportti.
```
