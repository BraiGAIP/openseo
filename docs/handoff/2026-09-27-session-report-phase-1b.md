# OpenSEO – istuntoraportti: vaihe 1b (Python-worker & DataForSEO)

> **Päivä:** 27.9.2026
> **Repo / haara:** `BraiGAIP/openseo`, haara `claude/phase-1-mvp` (PR [#1](https://github.com/BraiGAIP/openseo/pull/1))
> **Tämä tiedosto:** `docs/handoff/2026-09-27-session-report-phase-1b.md`
> **Edellinen raportti:** `docs/handoff/2026-09-27-session-report.md` (vaiheet 0 ja 1a)

---

## 1. Tiivistelmä

| Tehtävä (käyttäjän pyyntö) | Tila |
|---|---|
| 1. DataForSEO-provider `DATAFORSEO_LOGIN` / `DATAFORSEO_PASSWORD` -muuttujilla | ✅ `workers/python/openseo_workers/providers/dataforseo.py` |
| 2. `rank_check`-handler, joka hakee sijoitus- ja hakusanadatan ja päivittää Supabasen | ✅ `workers/python/openseo_workers/rank/handler.py` |
| 3. Automaattinen fallback mock-provideriin ilman API-avaimia | ✅ `providers/__init__.py` → `build_serp_provider()` |
| 4. pytest-testit + Dockerfile + fly.toml | ✅ 22 testiä vihreänä, Docker-image rakennettu ja ajettu, `fly.toml` valmis |
| Istuntoraportti | ✅ tämä tiedosto |

**Mitä EI voitu varmentaa tässä ympäristössä:** oikeaa DataForSEO-kutsua (ei tunnuksia, ja hiekkalaatikon verkko estää `dataforseo.com`:n) eikä Fly.io-deployta (ei Fly-tunnuksia). Kaikki muu on testattu, ks. §5.

---

## 2. Rakenne

```
workers/python/
├── pyproject.toml              # httpx, psycopg[binary], psycopg-pool; dev: pytest, pytest-asyncio, ruff
├── Dockerfile                  # python:3.12-slim, ei-root-käyttäjä (uid 10001)
├── .dockerignore
├── fly.toml                    # app openseo-workers, region fra, process group "rank"
├── README.md                   # konfiguraatio, kehitys, deploy
├── openseo_workers/
│   ├── __main__.py             # python -m openseo_workers [--queues …] [--once]
│   ├── config.py               # Settings.from_env()
│   ├── db.py                   # psycopg3-pooli, SET LOCAL ROLE service_role, kaikki SQL
│   ├── runner.py               # claim → dispatch → heartbeat → complete/fail, SIGTERM-käsittely
│   ├── providers/
│   │   ├── base.py             # SerpQuery, SerpResult, KeywordMetrics, ProviderError, protokollat
│   │   ├── dataforseo.py       # DataForSEO v3 REST
│   │   ├── mock.py             # deterministinen demodata
│   │   └── __init__.py         # build_serp_provider(): valinta + fallback
│   └── rank/handler.py         # rank_check-jobin logiikka
└── tests/
    ├── fixtures/task_get_advanced.json   # realistinen DataForSEO-vastaus
    ├── test_dataforseo.py      # HTTP-kerros MockTransportilla
    ├── test_providers.py       # provider-valinta, config, mock
    └── test_rank_check_e2e.py  # oikea PostgreSQL + kaikki migraatiot
```

---

## 3. Toteutuksen keskeiset ratkaisut

### 3.1 DataForSEO-provider
API-kenttien nimet ja endpointit on tarkistettu DataForSEO:n **virallisesta Python-kirjastosta** (`dataforseo-client` 2.1.7, PyPI), koska heidän dokumentaatiosivustonsa on estetty tässä ympäristössä. Tilakoodit 20100 / 40601 / 40602 on varmistettu erikseen.

| Toiminto | Endpoint | Huom. |
|---|---|---|
| SERP, standard (oletus) | `POST /v3/serp/google/organic/task_post` → `GET /v3/serp/google/organic/task_get/advanced/{id}` | ≤ 100 tehtävää / POST; pollataan kunnes `20000` (`40601`/`40602` = kesken) |
| SERP, live | `POST /v3/serp/google/organic/live/advanced` | 1 tehtävä / kutsu, noin 3× kalliimpi |
| Hakuvolyymi | `POST /v3/keywords_data/google_ads/search_volume/live` | ≤ 1000 avainsanaa / kutsu, laskutus per kutsu; enintään 80 merkkiä ja 10 sanaa per avainsana |

- **Autentikointi:** HTTP Basic (`DATAFORSEO_LOGIN`:`DATAFORSEO_PASSWORD`).
- **`stop_crawl_on_match`:** tärkein kustannussäästö. Jokainen SERP-tehtävä pyytää DataForSEO:ta lopettamaan haun, kun projektin domain (myös alidomainit) löytyy. Laskutus tapahtuu vain haettujen sivujen mukaan, joten sijoitus 3 maksaa yhden sivun, vaikka `depth` olisi 100. Parametri löytyi kirjaston mallista, ja se korvaa aiemmin suunnitellun "adaptiivisen syvyyden" (arkkitehtuuridokumentin §8.3 päivitetty).
- **Jatkettavat tehtävät:** standard-jonon tehtävä-id:t tallennetaan `private.provider_cache`-tauluun. Jos job aikakatkaistaan tai kaatuu ja yritetään uudelleen, pollausta jatketaan eikä uusia (maksullisia) tehtäviä luoda.
- **Virheluokittelu:** `5xxxx`, HTTP 429/5xx ja verkkovirheet uudelleenyritetään (backoff kannan `fail_job`issa). `4xxxx` (esim. 40100 väärät tunnukset, 40200 saldo loppu) → job merkitään `dead` eikä rahaa palaa turhaan.
- **Parsinta:** orgaaninen sijoitus = `rank_group`, ja paras osuma domainille tai sen alidomaineille valitaan. SERP-featuret tulevat `item_types`-kentästä. AI Overview -omistus päätellään `ai_overview`-elementin `references`-kentästä (myös sisäkkäisistä).

### 3.2 Fallback mock-provideriin
`build_serp_provider(settings)`:

| `SERP_PROVIDER` | Tunnukset | Tulos |
|---|---|---|
| `auto` (oletus) | molemmat asetettu | DataForSEO |
| `auto` | puuttuu (tai vain toinen) | **Mock** + selkeä varoitus lokiin |
| `mock` | – | Mock (pakotettu) |
| `dataforseo` | puuttuu | käynnistysvirhe (suositus tuotantoon) |

Mock-data tallennetaan `keyword_positions.provider = 'mock'` -merkinnällä, joten UI voi näyttää "demodata"-merkinnän. Mock on deterministinen: sama avainsana, domain ja päivä antavat aina saman tuloksen.

### 3.3 `rank_check`-handler
Payload (kannan `enqueue_due_rank_checks()` luo): `{"keyword_ids": [...], "check_date": "YYYY-MM-DD"}`.

1. Hakee aktiiviset avainsanat ja projektin domainin.
2. **Hakusanametriikat:** vanhentuneet (> 30 pv) tai puuttuvat → ensin jaettu välimuisti `private.keyword_metrics`, sitten provider. Myös "ei dataa" -vastaukset välimuistitetaan, jottei niistä makseta joka ajolla. Arvot kopioidaan `keyword_tracking`-tauluun (`search_volume`, `cpc_usd`, `competition`, `monthly_searches`, `metrics_updated_at`).
3. **SERPit:** yksi kysely per uniikki (avainsana, markkina, laite, syvyys, domain). Saman päivän välimuisti on `provider_cache`-taulussa ja jaetaan tenanttien kesken, esim. toimisto ja sen asiakas seuraavat samaa sivustoa.
4. **Sijoitukset:** upsert `keyword_positions (keyword_id, check_date)` → kannan trigger päivittää `keyword_tracking`-snapshotin (current/previous/best). `estimated_traffic` = CTR(sijoitus) × hakuvolyymi lasketaan SQL:ssä samalla `ctr_for_position()`-funktiolla kuin dashboardissa.
5. **Käytön mittaus:** `record_usage` organisaatiokohtaisesti (`serp_query` = haetut sivut, `keyword_lookup` = avainsanat), mukana idempotenssiavain `job:{id}:…`. Uudelleenajo ei siis tuplaa laskutusta. `p_enforce_quota => false`, koska ajastettua seurantaa rajaa `max_keywords` eikä kuukausikiintiö. Provider-kustannus kirjataan `provider_cost_usd`-kenttään katelaskentaa varten.

### 3.4 Runner ja tietokanta
- `claim_jobs` (FOR UPDATE SKIP LOCKED) → rinnakkain `WORKER_CONCURRENCY` jobia, heartbeat 30 s välein.
- `SIGTERM` lopettaa uusien jobien ottamisen ja antaa käynnissä olevien valmistua (Fly `kill_timeout = 300`).
- Jokainen tietokantaoperaatio tehdään omassa lyhyessä transaktiossa, joka aloitetaan komennolla `SET LOCAL ROLE service_role`. Tämä on turvallista Supavisorin transaktiopoolauksen kanssa (portti 6543), ja prepared statementit on siksi pois päältä. Pitkiä API-odotuksia ei tehdä transaktion sisällä.
- Käynnistyksessä tarkistetaan, että kannan merkistö on `UTF8`. Muuten worker pysähtyy selkeään virheeseen (ks. §4).

---

## 4. Testauksen aikana löytyneet ja korjatut bugit

1. **NULL-sijoitus kaatoi upsertin.** Kun avainsana ei sijoitu, sama `NULL`-parametri meni sekä `smallint`-sarakkeeseen että `integer`-funktioon, ja PostgreSQL:n tyyppipäättely epäonnistui (`AmbiguousParameter`). Korjaus: eksplisiittiset tyyppimuunnokset (`::smallint`, `::integer`, `::text[]`, `::boolean`).
2. **`SQL_ASCII`-kanta.** Ilman `LANG`-muuttujaa `initdb` loi testikannan `SQL_ASCII`-merkistöllä, jolloin psycopg palautti tekstin tavuina ja jonon nimi näkyi muodossa `b'rank_check'`. Tuotanto (Supabase) on aina UTF8, mutta testiympäristöjen pitää vastata sitä. Korjaukset:
   - `tests/db/run.sh` ja pytest-fixture luovat klusterin komennolla `-E UTF8 --locale=C`.
   - Worker kieltäytyy käynnistymästä muulla kuin UTF8-kannalla. Varmennettu: vanha `SQL_ASCII`-kanta → `RuntimeError: database encoding must be UTF8`.
3. **Mock ei sijoittanut mitään oletussyvyydellä 20** (arpoi väliltä 1–60). Korjattu arpomaan tarkistussyvyyden sisältä, ja lisätty testi.

---

## 5. Varmennus

| Tarkistus | Tulos |
|---|---|
| `ruff check` + `ruff format --check` | ✅ |
| `pytest -q` (myös ilman `LANG`-muuttujaa) | ✅ **22 passed** |
| `tests/db/run.sh` (13 tietokantaskenaariota + rank summary) | ✅ ALL TESTS PASSED |
| Docker-image (`docker build`) | ✅ rakentuu, ajaa ei-root-käyttäjänä, ilman `DATABASE_URL` → exit 2 |
| **Kontti päästä päähän** oikeaa PostgreSQL:ää vasten (migraatiot, suomenkieliset avainsanat) | ✅ job `succeeded`, 4 sijoitusriviä, hakuvolyymit, `usage_records` (`serp_query` 8, `keyword_lookup` 4) |

Testien kattavuus:
- **`test_dataforseo.py` (httpx MockTransport):**
  - Basic auth -otsake ja `stop_crawl_on_match` pyynnössä.
  - Standard-jonon post → `40602` → valmis; duplikaatit postataan vain kerran.
  - **Uudelleenyritys jatkaa samaa tehtävää ilman uutta maksullista POSTia.**
  - Live-tila: yksi tehtävä per kutsu.
  - Virheluokittelu (401, 40200, 50000, 503).
  - Hakuvolyymien 1000 avainsanan erät ja suodatus (> 80 merkkiä, > 10 sanaa).
  - Parsinta: paras alidomain-osuma, AI Overview -viittaus sisäkkäisestä elementistä, kustannus ja sivumäärä.
- **`test_providers.py`:** fallback ilman tunnuksia (ja vain toisella tunnuksella), DataForSEO tunnuksilla, `SERP_PROVIDER=dataforseo` ilman tunnuksia → virhe, pakotettu mock, env-parsinta, mockin determinismi ja syvyysraja.
- **`test_rank_check_e2e.py` (oikea PostgreSQL + kaikki migraatiot, worker `service_role`-roolilla):**
  - Kaksi tenanttia, sama avainsana ja domain → **vain yksi maksullinen DataForSEO-tehtävä**, ja toinen tenantti saa tuloksen välimuistista.
  - Sijoitus 12 (alidomain `blog.`), `current_position`-snapshot, `owns_ai_overview`, `estimated_traffic` = 19 (CTR 0,01 × 1900), hakuvolyymi haettu kerran.
  - `usage_records` oikein.
  - Uudelleenajettu job on idempotentti.
  - Mock-fallback merkitsee rivit `mock`-tunnuksella.
  - Viallinen payload → `dead` ilman uudelleenyrityksiä.

**CI** (`.github/workflows/ci.yml`) sisältää nyt neljä jobia: tietokantatestit, web (lint/typecheck/build), worker (ruff + pytest sis. Postgres-e2e) ja workerin Docker-imagen buildin.

---

## 6. Käyttöönotto – käyttäjän tehtävät

1. **DataForSEO-tili:** rekisteröidy ja lataa saldoa (minimi 50 $, uusille tileille 1 $ ilmaista kokeilusaldoa). API-tunnukset löytyvät DataForSEO:n dashboardista (API Access). Aloita kokeilu `DATAFORSEO_MODE=standard`-tilassa.
2. **Fly.io:**
   ```bash
   fly apps create openseo-workers
   fly secrets set --app openseo-workers \
     DATABASE_URL='<Supabase Dashboard → Connect → Transaction pooler URI, portti 6543>' \
     DATAFORSEO_LOGIN='…' DATAFORSEO_PASSWORD='…' SERP_PROVIDER=dataforseo
   fly deploy --config workers/python/fly.toml workers/python
   ```
   `DATABASE_URL` tarvitsee Supabasen tietokantasalasanan (Dashboard → Project Settings → Database). Älä laita sitä repoon.
3. **Supabase Auth -paluuosoitteet** (edellisestä raportista, yhä tekemättä): Authentication → URL Configuration → lisää `http://localhost:3000/auth/callback` ja tuotanto-osoite.
4. Sulje vanha PR `BraiGAIP/akku-turvan-mestari#4`, jos et ole vielä sulkenut.

**Kustannusarvio (DataForSEO, standard):** 0,0006 $/sivu, lisäsivut 0,75 × perushinta. Kun `stop_crawl_on_match` on päällä, top 10 -sijoitus maksaa yhden sivun. 500 avainsanan päivittäinen seuranta ≈ 15 000–21 000 sivua/kk ≈ **9–16 $/kk**. Hakuvolyymi maksaa kerran 30 päivässä per 1000 avainsanaa ja markkina.

---

## 7. Seuraavat askeleet

1. **Ensimmäinen oikea ajo:** kun tunnukset ja Fly-deploy ovat valmiit, lisää web-sovelluksessa projekti ja pari avainsanaa. pg_cron luo `rank_check`-jobin 10 minuutin sisällä, ja worker käsittelee sen. Tarkista `select status, result from jobs` ja dashboard.
2. **UI:** näytä "demodata"-merkintä, kun sijoitusten `provider = 'mock'`. Lisää "Tarkista nyt" -nappi (live-tila, kuluttaa `serp_query`-kiintiötä).
3. **Serper-fallback** (arkkitehtuurin D6) ja `keyword_metrics`-jono uusien avainsanojen välittömälle volyymihaulle.
4. **Fly-autoskaalaus** jonon pituuden mukaan (nyt kiinteästi 1 kone, noin 2–4 $/kk).
5. **Vaihe 2:** site audit -crawler (`site_audit`-jono, `request_site_audit` RPC on jo kannassa) ja kilpailija-analyysi.

---

## 8. Aloituskehote seuraavaan istuntoon

```
Jatka OpenSEO-projektia (repo BraiGAIP/openseo, haara claude/phase-1-mvp).
Lue ensin docs/handoff/2026-09-27-session-report-phase-1b.md ja docs/ARCHITECTURE.md.
Tee seuraavaksi: (1) web-UI:hin demodata-merkintä mock-sijoituksille ja "Tarkista nyt"
-nappi, (2) Serper-fallback-provider workeriin, (3) aloita vaihe 2: site audit -crawler.
Aja testit (tests/db/run.sh, workers/python: pytest, apps/web: lint/typecheck/build)
ja päivitä istuntoraportti.
```
