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

## Deploy to Fly.io

The container is a Node 22 server with no dependencies. It stores the board in SQLite on a Fly volume and loads the test data the first time it starts.

1. In `fly.toml`, set `app` to a free name and `primary_region` to the region your other apps use.
2. Run these once:

   ```sh
   fly apps create <app-name>
   fly volumes create board_data --size 1 --region <region> -a <app-name>
   fly secrets set BOARD_PASSWORD='<shared password>' -a <app-name>
   fly deploy
   ```
3. Open `https://<app-name>.fly.dev` and sign in as `coral` with that password. Set `BOARD_USER` as a secret to change the user name.

Later deploys are just `fly deploy`. The data stays on the volume.

Notes:
- Run **one machine only**, because SQLite lives on a single volume. Don't `fly scale count 2`. The machine stops when idle and starts again on the next request.
- To start with an empty board instead of test data, `fly secrets set SEED=off` before the first deploy. To reload the test data, delete `/data/board.db` (`fly ssh console`) and restart.
- Back up with `fly ssh sftp get /data/board.db`. Fly also snapshots volumes daily.
- Sign-in is one shared password (HTTP basic auth). Use the "Working as" picker to choose who you act as. Per-person sign-in (for example Microsoft Entra ID) comes later.
- `/healthz` is open for Fly's health check. Everything else needs the password.
- Configuration: `PORT` (8080), `DB_PATH` (`/data/board.db`), `BOARD_USER` (`coral`), `BOARD_PASSWORD` (no password if unset), `SEED` (`off` to skip test data).

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
- Workflow: Triage, Queued (accepted and waiting to be picked up), In progress, In development, Verify, Done.
- Every task can carry a **product module** (Operations, Finance, TVOD, International, Reporting, Platform) and a **release**: a scheduled release such as 4.13, or Backlog for work that isn't due on any particular day.
- SLA: support items (incident, bug, request, question) for outside clients run a first-response clock, then a resolution clock. The clock pauses while a task is waiting on the client. A client can override the default terms. All other items count down to their due date. Once a support item has had its first response, scheduling it into a release or the backlog replaces the resolution clock, so it tracks the release ship date instead.

## Planned

- Integrations: Jira, Azure DevOps, Microsoft Teams, email intake.
- Time tracking: a timer starts when someone takes a task, and Stop posts the time to the time tracker.
- Real sign-in in place of the "Working as" picker.
- A business-hours calendar for SLA clocks.
