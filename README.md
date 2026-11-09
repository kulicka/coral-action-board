# Coral MSP Action Board

One board for tracking action items across Coral MSP's clients, projects and teams. Work comes in from support, from clients and from internal teams. The board shows who owns each item, what's unassigned, and which items are close to missing their SLA.

## What's here

| Path | What it is |
| --- | --- |
| `app/index.html` | The working prototype: a single-page board with live SLA clocks, role views, saved views, and create, edit, assign and stage actions. |
| `design/card-studies.html` | Card design study with three layouts: Detail, Short and Ledger. |
| `design/board-mockup.html` | Clickable board mockup with in-memory sample data. |
| `sql/01_schema.sql` | SQL Server schema: clients, projects, teams, people, SLA policies, tasks, tags, activity and saved views. |
| `sql/02_test_data.sql` | Test data matching the prototype, timed relative to when you run it. |
| `sql/03_views_and_procs.sql` | `v_task_card` (the SLA state for each task), `v_workload`, `v_needs_attention`, and a procedure for each board action. |
| `tools/seed.py` | Generates the prototype's test data, `server/seed/` and `sql/02_test_data.sql` from one source. |
| `server/` | Small Node server for hosting the board outside claude.ai (Fly.io or any Docker host). |
| `Dockerfile`, `fly.toml` | Container and Fly.io config. |

## Running the prototype

`app/index.html` stores its data in a claude.ai Artifact database through `window.claude.use("db")`. The live copy is hosted as a claude.ai Artifact. To run the same page on your own host, use the server in `server/` (see below). It serves `app/index.html` unchanged and supplies the same database calls.

### Run locally

Needs Node 22 or later. No `npm install` is needed.

```sh
BOARD_PASSWORD=secret node --experimental-sqlite server/server.js
# open http://localhost:8080 and sign in as coral / secret
```

The server refuses to start without some form of sign-in. For a quick look with no sign-in at all, set `ALLOW_NO_AUTH=1`.

## Sign-in and security

The board can hold personal or client information, so every page and API call needs sign-in. Only `/healthz` is open.

**Google sign-in (recommended).** Set `GOOGLE_CLIENT_ID` and the board uses Google sign-in, limited to the accounts you allow:

- `ALLOWED_EMAILS`: comma-separated Google accounts, for example `someone@gmail.com`.
- `ALLOWED_DOMAINS`: comma-separated Google Workspace domains, for example `coral.team`. This matches only Workspace accounts of that domain (Google's `hd` claim), not any Google account that uses an address there.

Set up the Google client once per deployment:

1. In Google Cloud Console, open **APIs & Services → OAuth consent screen**. Choose **External** (or **Internal** for a Workspace-only board), fill in the app name and your email, and add yourself as a test user. Testing mode is fine for a few people.
2. Open **Credentials → Create credentials → OAuth client ID**, type **Web application**. Add the authorized redirect URI `https://<app-name>.fly.dev/auth/callback`.
3. Set the secrets (never commit them):

   ```sh
   fly secrets set -a <app-name> \
     GOOGLE_CLIENT_ID='<client id>' \
     GOOGLE_CLIENT_SECRET='<client secret>' \
     SESSION_SECRET="$(openssl rand -hex 32)" \
     ALLOWED_EMAILS='<your account>@gmail.com'
   ```

   `PUBLIC_URL` (the board's https address) must also be set, as an env value in the fly config or as a secret.

Sessions last `SESSION_HOURS` (12 by default) in a signed, HttpOnly cookie. Removing an account from the allow list locks it out on the next restart. Changing `SESSION_SECRET` signs everyone out.

**Shared password (legacy).** Without `GOOGLE_CLIENT_ID`, `BOARD_PASSWORD` turns on one shared password (HTTP basic auth, user `BOARD_USER`, default `coral`).

**What else the server does:**

- Strict security headers: a Content-Security-Policy that only runs the board's own scripts (per-request nonce), HSTS, `X-Frame-Options: DENY`, `nosniff`, `Referrer-Policy: same-origin`, `noindex`.
- Writes from the browser must come from the board's own origin and be JSON, which blocks cross-site request forgery.
- 30 failed sign-ins from one IP in 10 minutes blocks that IP for the rest of the 10 minutes.
- Secrets come only from environment variables. Nothing personal belongs in this repo: seed files and SQL here are test data only.

## Adding tasks from another system (ingest token)

Set `BOARD_INGEST_TOKEN` (32+ characters, `openssl rand -hex 32`) to let a script or scheduled job add tasks without signing in to Google. The token can only `PUT` or `PATCH` `/api/tasks/<id>`. It can't read, list, delete, or touch other collections.

```sh
# create (If-None-Match: * returns 412 if the task already exists, so a repeat run won't overwrite edits)
curl -X PUT https://<app-name>.fly.dev/api/tasks/PER-18c2f0a1 \
  -H "Authorization: Bearer $BOARD_INGEST_TOKEN" -H 'Content-Type: application/json' -H 'If-None-Match: *' \
  -d '{"key":"PER-18c2f0a1","type":"request","source":"email","title":"Pay the electric bill","client":"Bills",
       "project":null,"priority":2,"owner":null,"queue":"Personal","stage":0,"createdAt":"2026-11-09T14:00:00Z",
       "due":"2026-11-20","tags":["bill"],"notes":"","history":[{"at":"2026-11-09T14:00:00Z","text":"Created from email"}]}'

# update some fields (merged into the existing task)
curl -X PATCH https://<app-name>.fly.dev/api/tasks/PER-18c2f0a1 \
  -H "Authorization: Bearer $BOARD_INGEST_TOKEN" -H 'Content-Type: application/json' -d '{"due":"2026-11-21"}'
```

Tasks written with the token are checked before they're saved: `key` must equal the id and look like `ABC-123`; required fields are `key`, `type`, `title`, `client`, `priority` (1–4), `queue`, `stage` (0–6) and `createdAt`; times are UTC ISO 8601 (`2026-11-09T14:00:00Z`), `due` is `YYYY-MM-DD`, and unknown fields are refused. A bad task gets a 400 that names the fields.

## Deploy to Fly.io

The container is a Node 22 server with no dependencies. It stores the board in SQLite on a Fly volume.

1. In `fly.toml`, set `app` to a free name and `primary_region` to the region your other apps use.
2. Run these once:

   ```sh
   fly apps create <app-name>
   fly volumes create board_data --size 1 --region <region> -a <app-name>
   # then the Google secrets above, plus PUBLIC_URL
   fly deploy
   ```
3. Open `https://<app-name>.fly.dev` and sign in with an allowed Google account.

Later deploys are just `fly deploy`. The data stays on the volume.

### A separate personal board

`fly.personal.toml` runs a second, private copy of the board with its own app, volume and secrets. It starts empty (`SEED=personal`: a few personal categories as clients, one "Personal" queue, no Coral test data).

```sh
fly apps create kulicka-personal-board
fly volumes create personal_board_data --size 1 --region iad -a kulicka-personal-board
fly secrets set -a kulicka-personal-board GOOGLE_CLIENT_ID=... GOOGLE_CLIENT_SECRET=... \
  SESSION_SECRET="$(openssl rand -hex 32)" ALLOWED_EMAILS='<personal account>@gmail.com' \
  BOARD_INGEST_TOKEN="$(openssl rand -hex 32)"
fly deploy -c fly.personal.toml
```

Give it its own Google OAuth client (or add `https://kulicka-personal-board.fly.dev/auth/callback` as a second redirect URI on the same client).

Notes:
- Run **one machine only**, because SQLite lives on a single volume. Don't `fly scale count 2`. The machine stops when idle and starts again on the next request.
- `SEED`: unset loads the Coral test data the first time the board starts, `personal` starts an empty personal board, `off` loads nothing. To reload, delete `/data/board.db` (`fly ssh console`) and restart.
- Back up with `fly ssh sftp get /data/board.db`. Fly also snapshots volumes daily.
- The "Working as" picker still chooses who you act as; it isn't tied to the Google account yet.
- Configuration: `PORT` (8080), `DB_PATH` (`/data/board.db`), `PUBLIC_URL`, `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `SESSION_SECRET`, `SESSION_HOURS` (12), `ALLOWED_EMAILS`, `ALLOWED_DOMAINS`, `BOARD_INGEST_TOKEN`, `BOARD_USER` / `BOARD_PASSWORD` (legacy), `SEED`, `ALLOW_NO_AUTH` (local only).

## Setting up the database

Run the scripts in order on SQL Server 2019+ or Azure SQL:

```sql
:r sql/01_schema.sql
:r sql/02_test_data.sql
:r sql/03_views_and_procs.sql
SELECT * FROM dbo.v_needs_attention ORDER BY sla_state, priority;
```

## Rules the model follows

- Each task has one client. Work that affects several clients is logged under **Coral Technology**.
- Each task has exactly one accountable owner. Unassigned tasks wait in a team queue.
- Workflow: Triage, Queued (accepted and waiting to be picked up), In progress, In development, Ready for testing, Ready to publish, Done.
- Every task can carry a **product module** (Operations, Finance, TVOD, International, Reporting, Platform) and a **release**: a scheduled release such as 4.13, or Backlog for work that isn't due on any particular day.
- SLA: support items (incident, bug, request, question) for outside clients run a response clock, then a fix clock. Targets come from each client's SLA terms by severity (Sev 1–4 = P1–P4), managed on the **Client SLAs** page. Clients without their own terms use the Coral standard. Targets in business hours or days count 8am–6pm ET, Monday to Friday, minus US federal holidays and the day after Thanksgiving. Targets marked 24/7 count around the clock. A fix can also be best efforts, promptly or next available update, which have no clock. The clock pauses while a task is waiting on the client. All other items count down to their due date. Once a support item has had its first response, scheduling it into a release or the backlog replaces the fix clock, so it tracks the release ship date instead.
- The SLA terms were loaded from `Coral_MSP_Complete_SLA_Matrix.xlsx` (2026-10-28). Each client's terms are marked Contractual, Assumed (Fox, Paramount) or Not confirmed (Ole), as in the matrix.

## Planned

- Integrations: Jira, Azure DevOps, Microsoft Teams. (Email intake can use the ingest token.)
- Time tracking: a timer starts when someone takes a task, and Stop posts the time to the time tracker.
- Real sign-in in place of the "Working as" picker.
- A business-hours calendar for SLA clocks.
