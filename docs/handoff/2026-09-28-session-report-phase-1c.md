# BraiSEO (ent. OpenSEO) – istuntoraportti: vaihe 1c (käyttöönotto, Tarkista nyt, Serper, KD, SERP-muutokset)

> **Päivä:** 27.–28.9.2026
> **Repo / haara:** `BraiGAIP/openseo`, haara `claude/phase-1-mvp` (PR [#1](https://github.com/BraiGAIP/openseo/pull/1))
> **Tämä tiedosto:** `docs/handoff/2026-09-28-session-report-phase-1c.md`
> **Edelliset raportit:** `docs/handoff/2026-09-27-session-report.md` (0 ja 1a), `docs/handoff/2026-09-27-session-report-phase-1b.md` (1b)

---

## 1. Tiivistelmä

Pyyntö ("Vaihe 1b: Python-worker & DataForSEO-integraatio") sisälsi osin jo tehtyä työtä. Taulukko näyttää, mitä pyydettiin ja missä se on.

| Pyyntö | Tila | Missä |
|---|---|---|
| Runner, `providers/dataforseo.py` (`DATAFORSEO_LOGIN`/`PASSWORD`), mock-fallback | ✅ jo vaiheessa 1b | `workers/python/openseo_workers/` |
| `providers/serper.py` | ✅ tässä istunnossa | `providers/serper.py`, `providers/fallback.py` |
| `rank_check`: DataForSEO-sijoitukset, sijoitusmuutokset, tallennus Supabaseen | ✅ | `rank/handler.py`; tietokannan snapshot-triggeri pitää yllä nykyisen, edellisen ja parhaan sijoituksen |
| "Blogin SEO-tarkistuslogiikat": rank tracking, **keyword difficulty**, **SERP-muutokset** | ✅ tässä istunnossa | Blogia ei ollut olemassa, joten määritelmät on kirjattu: `docs/ARCHITECTURE.md` §8.6 |
| Pytest-yksikkötestit ja e2e paikallista PostgreSQL:ää vasten | ✅ **59 testiä** (1b:n lopussa 22) | `workers/python/tests/` |
| Dockerfile ja fly.toml Fly.io:ta varten | ✅ ja automaattinen deploy GitHub Actionsista | `workers/python/`, `apps/web/`, `.github/workflows/` |

Käyttäjän valinnat tässä istunnossa:
- Fly.io myös web-sovellukselle (Vercelin sijaan).
- Keyword difficulty tulee DataForSEO Labsista.
- SERP-muutoksista seurataan kaikki neljä tyyppiä.
- Määritelmät päätän minä, koska blogia ei vielä ole.

---

## 2. Mitä rakennettiin (commitit PR #1:ssä)

| Commit | Sisältö |
|---|---|
| `d2a1885` | Workerin deploy Fly.io:hon GitHub Actionsista (`deploy-worker.yml`) |
| `4c76ad2` | "Tarkista nyt" -nappi, demodata-ilmoitus, Serper-fallback, migraatio `20260927203700` |
| `02286dd` | Web-sovelluksen deploy Fly.io:hon (standalone Next.js, `apps/web/Dockerfile`, `apps/web/fly.toml`, `deploy-web.yml`) |
| (tämä) | Keyword difficulty, SERP-muutostapahtumat, migraatio `20260928110148`, UI (KD-sarake, "SERP-muutokset"-kortti), testit ja dokumentaatio |

### 2.1 Keyword difficulty (KD 0–100)
- **Lähde:** DataForSEO Labs `POST /v3/dataforseo_labs/google/bulk_keyword_difficulty/live`, enintään 1 000 avainsanaa kutsussa. Kentät tarkistettiin virallisesta `dataforseo-client` 2.1.7 -kirjastosta: `result[0].items[{keyword, keyword_difficulty}]`.
- **Päivitys:** KD haetaan hakuvolyymin kanssa 30 päivän välein ja tallennetaan `private.keyword_metrics`-välimuistiin (jaettu asiakkaiden kesken). Se kopioidaan `keyword_tracking.keyword_difficulty`-sarakkeeseen.
- **Virheet:**
  - Labs ei käytössä tilillä (pysyvä virhe) → KD jää tyhjäksi, volyymi toimii silti.
  - Tilapäinen katkos → koko metriikkahaku yritetään uudelleen seuraavalla ajolla, sijoitukset tallentuvat joka tapauksessa.
- **Näyttö:** 0–29 helppo · 30–49 kohtalainen · 50–69 vaikea · 70–100 erittäin vaikea.
- **Kytkin:** `DATAFORSEO_KEYWORD_DIFFICULTY` (oletus päällä).

### 2.2 SERP-muutokset
- **Logiikka:** `rank/changes.py` on puhdas funktio, joka vertaa tarkistusta avainsanan edelliseen tarkistukseen.
- **Tallennus:** tulokset menevät tauluun `public.keyword_events` (RLS: katselijat näkevät oman organisaationsa tapahtumat, kirjoitus vain workerilla).
- **Tapahtumat:**
  - alkoi/lakkasi sijoittumasta
  - top 3 / top 10 sisään/ulos
  - vähintään ±5 sijan hyppy (`RANK_JUMP_THRESHOLD`)
  - sijoittuva URL vaihtui
  - SERP-elementti ilmestyi/poistui
  - AI Overview -maininta alkoi/loppui
  - kilpailija tuli top 10:een tai putosi sieltä
- **Säännöt:**
  - Sijoitustapahtumia on enintään yksi tarkistusta kohden, ja merkittävin voittaa. Esimerkiksi 15 → 2 raportoidaan vain "nousi kolmen kärkeen".
  - Ensimmäisestä tarkistuksesta ei synny tapahtumia.
  - Demodatan ja oikean datan välinen vaihto ei synny tapahtumaksi.
  - Saman päivän uusintatarkistus korvaa päivän tapahtumat.
- **Kilpailijavertailu:** jokaisen tarkistuksen top 10 -domainit tallennetaan `keyword_positions.top_domains`-sarakkeeseen.
- **UI:** projektisivun oikeassa palstassa on "SERP-muutokset"-syöte, jossa on väri- ja nuolimerkinnät (hyvä / huono / neutraali uutinen). Tekstit on käännetty EN/FI/SV.

### 2.3 Aiemmin tässä istunnossa (PR:ssä jo aiemmin)
- **"Tarkista nyt":**
  - `request_rank_check()` vaatii admin-roolin, sallii yhden tarkistuksen tunnissa per projekti ja tarkistaa kiintiön.
  - Worker ohittaa päivän välimuistin ja käyttää DataForSEO:n live-endpointia rinnakkain.
- **Demodata-ilmoitus**, kun sijoitukset tulevat mock-providerilta (`keyword_tracking.last_provider`).
- **Serper-fallback:**
  - Jos DataForSEO epäonnistuu, samat SERPit haetaan Serperistä. Sivutus 10 tulosta kerrallaan pysähtyy omaan domainiin.
  - Hitaasti jonossa olevia DataForSEO-tehtäviä ei korvata Serperillä, koska uudelleenyritys on halvempi.
- **Fly.io-deploy molemmille sovelluksille:**
  - Web (`braiseo-web`) nukkuu, kun sitä ei käytetä, ja maksaa noin 0–4 $/kk.
  - Worker (`braiseo-workers`) on aina päällä ja maksaa noin 3,3 $/kk.

---

## 3. Tietokanta

| Migraatio | Sisältö | Tuotannossa |
|---|---|---|
| `20260927203700_openseo_rank_check_now` | `keyword_tracking.last_provider`, `request_rank_check()` | ✅ |
| `20260928110148_openseo_serp_changes` | `keyword_positions.top_domains`, enum `keyword_event_kind`, taulu `keyword_events` (RLS, scope-triggeri, uniikki per avainsana + päivä + tyyppi + kohde) | ✅ |

Supabase-projektin tietoturvatarkistus (advisors) ei löytänyt uusia varoituksia. Jäljellä ovat vain tarkoitukselliset `SECURITY DEFINER` -RPC:t, jotka tarkistavat roolin itse.

---

## 4. Varmennus

- **Worker** (`ruff check`, `ruff format --check`, `pytest`): **59 passed**. Uudet testit kattavat:
  - kaikki muutossäännöt yksikkötesteinä (13 testiä)
  - KD:n eräajon (1 500 → 1 000 + 500), Labs puuttuu → volyymi säilyy, katkos → uudelleenyritys, kytkin pois
  - e2e: kahden päivän ajo, jossa sijoitus putoaa 8 → 12, URL vaihtuu, AI Overview -maininta alkaa, kilpailija tulee ja poistuu, KD tallentuu, ja uusintatarkistus ei tuota tuplatapahtumia
- **Tietokanta** (`tests/db/run.sh`): ALL TESTS PASSED, mukana uusi kohta 7b:
  - tapahtuman organisaatio johdetaan avainsanasta
  - toinen asiakas ei näe tapahtumia
  - kirjautunut käyttäjä ei voi kirjoittaa
  - uniikkius
- **Web:** lint, typecheck ja build menevät läpi. Kaikki 15 muutostekstiä renderöityvät EN/FI/SV.
- **Web-kontti** (edellinen commit): `/`, `/fi`, `/sv` ja `/login` → 200, `/app` → 307; ajetaan ei-root-käyttäjänä.

**Ei varmennettavissa tästä hiekkalaatikosta:**
- oikeat DataForSEO/Serper-kutsut (verkkoyhteys estetty)
- Fly.io-deploy
- kirjautuminen tuotanto-Supabaseen

KD- ja muutos-UI:ta ei ole nähty selaimessa kirjautuneena. Syy on sama: `*.supabase.co` on estetty.

---

## 5. Käyttäjän tehtävät (järjestyksessä)

1. **GitHub-secretit:** https://github.com/BraiGAIP/openseo/settings/secrets/actions
   - `FLY_API_TOKEN`
   - `DATABASE_URL` (Supabase → Connect → Transaction pooler, portti 6543, salasana paikalleen)
   - `DATAFORSEO_LOGIN`, `DATAFORSEO_PASSWORD`
   - valinnainen `SERPER_API_KEY`
2. **Supabase → Authentication → URL Configuration:**
   - Site URL `https://braiseo-web.fly.dev`
   - Redirect URLs `https://braiseo-web.fly.dev/**`
3. **Yhdistä PR #1:** Ready for review → Merge. Kummankin sovelluksen deploy käynnistyy automaattisesti (Actions-välilehti).
4. **Ensimmäinen testi:**
   1. Kirjaudu omalla sähköpostillasi.
   2. Luo projekti ja lisää avainsanat.
   3. Sijoitukset ja KD tulevat noin 10 minuutissa, tai heti "Tarkista nyt" -napilla.
   4. SERP-muutokset näkyvät toisesta tarkistuksesta alkaen, eli seuraavana päivänä.
5. **DataForSEO Labs:** tarkista, että Labs-API on tilillä käytössä. Ilman sitä KD jää tyhjäksi.
6. **Ennen asiakkaita: oma SMTP**, esim. Resend. Supabasen oma sähköposti lähettää vain tiimin jäsenille, 2 viestiä tunnissa.

**Kustannusarvio (Pro-asiakas, 500 avainsanaa):**
- SERP noin 9–16 $/kk
- KD noin 0,06 $ per 500 avainsanaa per 30 päivää (pyöristyy nollaan)
- volyymi noin 0,075 $ per kutsu per 30 päivää

---

## 5b. Nimenvaihto: OpenSEO → BraiSEO

**Käyttäjän päätökset:**
- Kaikki näkyvä nimetään uudelleen, samoin Fly-sovellukset.
- Koodin sisäiset nimet (`@openseo/*`, `openseo_workers`, repo `BraiGAIP/openseo`, Supabase-projekti "OpenSEO") pysyvät ennallaan.
- Arkkitehtuurin päätösloki: D15.

| Kohde | Uusi |
|---|---|
| Käyttöliittymän tekstit, sivujen otsikot (EN/FI/SV) | BraiSEO |
| Fly-sovellukset | `braiseo-web` → https://braiseo-web.fly.dev, `braiseo-workers` |
| Workerin User-Agent DataForSEO:lle | `BraiSEO-worker/0.1 (+https://brai.build)` |
| README, ARCHITECTURE, workerin README | BraiSEO |

**Tärkeää:** Supabasen kirjautumisosoitteeksi tulee nyt `https://braiseo-web.fly.dev` (ei `openseo-web`).

**Lisenssi (avoin kysymys, ARCHITECTURE §15 kohta 5):** AGPL-3.0 on toistaiseksi ennallaan. Se on päätettävä ennen kuin koodi tai tuote julkaistaan.
- **AGPL:** kuka tahansa saa ajaa ja muokata BraiSEO:ta, mutta palveluna tarjotun muokatun version lähdekoodi on julkaistava. Tästä saa avoimen lähdekoodin markkinointiedun ja yhteisön.
- **Suljettu:** koodi pysyy omana liikesalaisuutena, eikä kukaan saa käyttää sitä ilman lupaa. Tällöin "open-source"-maininnat poistetaan etusivulta.

**Oma domain `seo.brai.build`** (valmisteltu, ei vielä päällä). Tee tämä vasta, kun perus-deploy toimii:
1. Fly.io → `braiseo-web` → **Certificates** → *Add certificate* → `seo.brai.build`.
2. Lisää brai.buildin DNS-palveluun Flyn näyttämät tietueet (yleensä CNAME `seo` → `braiseo-web.fly.dev`).
3. GitHub → Settings → Secrets and variables → Actions → **Variables** → `SITE_URL` = `https://seo.brai.build` → aja *Deploy web app* uudelleen.
4. Supabase → Authentication → URL Configuration: vaihda Site URL ja Redirect URL uuteen osoitteeseen.

---

## 6. Seuraavat askeleet

1. **Ensimmäinen oikea ajo** (kohdan 5 jälkeen) ja virheiden korjaus oikeaa dataa vastaan.
2. **Hälytykset:** sähköposti tai Slack valituista muutostyypeistä, esim. "putosi etusivulta" ja "kilpailija nousi top 10:een".
3. **SERP-volatiliteetti** projektitasolla, sekä muutostapahtumat raportteihin (white-label).
4. **Oma SMTP** (Resend) ja kirjautumissähköpostien brändäys.
5. **Vaihe 2:** site audit -crawler (`site_audit`-jono; `request_site_audit` RPC on jo kannassa).

---

## 7. Aloituskehote seuraavaan istuntoon

```
Jatka BraiSEO-projektia (ent. OpenSEO; repo BraiGAIP/openseo). Jos PR #1 on yhdistetty, aloita
uusi haara mainista; muuten jatka haarassa claude/phase-1-mvp.
Lue ensin docs/handoff/2026-09-28-session-report-phase-1c.md ja docs/ARCHITECTURE.md (§8).
Tee seuraavaksi: (1) tarkista ensimmäisen tuotantoajon tulokset (jobs-taulu, Fly-lokit)
ja korjaa löydökset, (2) hälytykset valituista SERP-muutoksista (sähköposti),
(3) aloita vaihe 2: site audit -crawler. Aja testit (tests/db/run.sh, workers/python:
pytest, npm run lint/typecheck/build) ja päivitä istuntoraportti.
```
