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
| `tools/seed.py` | Generates the prototype's test data and `sql/02_test_data.sql` from one source. |

## Running the prototype

`app/index.html` stores its data in a claude.ai Artifact database through `window.claude.use("db")`. The live copy is hosted as a claude.ai Artifact. If you open the file anywhere else, it shows a "database isn't available" state. Connecting it to the SQL Server model in `sql/` (through an API layer) is the next step toward a standalone deployment.

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
- Workflow: Triage, Ready, In progress, In development, Verify, Done.
- SLA: support items (incident, bug, request, question) for outside clients run a first-response clock, then a resolution clock. The clock pauses while a task is waiting on the client. A client can override the default terms. All other items count down to their due date.

## Planned

- Integrations: Jira, Azure DevOps, Microsoft Teams, email intake.
- Time tracking: a timer starts when someone takes a task, and Stop posts the time to the time tracker.
- Real sign-in in place of the "Working as" picker.
- A business-hours calendar for SLA clocks.
