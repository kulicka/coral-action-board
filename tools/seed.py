"""One source of test data for the action board.
Writes JSON docs for the artifact database and a SQL Server seed script."""
import json, os, sys
from datetime import datetime, timedelta, timezone

OUT = sys.argv[1]
SQL_OUT = sys.argv[2]
NOW = datetime.now(timezone.utc).replace(microsecond=0)

def iso(dt): return dt.strftime('%Y-%m-%dT%H:%M:%SZ') if dt else None

CLIENTS = ['Paramount', 'AMC', 'Netflix', 'NBCU', 'Fox', 'Coral Technology']
PROJECTS = ['Coral MSP 4.12 release', 'Netflix onboarding', 'Fox SSO migration', 'Paramount reporting rollout', 'Product backlog']
TEAMS = ['Support L1', 'Support L2', 'Development', 'Platform', 'QA', 'Product']
PEOPLE = [  # id, name, team, color
    ('JR', 'Jon Ruiz', 'Support L1', '#6fd3e6'), ('HS', 'Hana Sato', 'Support L1', '#7fa6ff'),
    ('SO', 'Sam Okafor', 'Support L2', '#e88bc8'), ('AK', 'Ava Kowalski', 'Support L2', '#f0a37a'),
    ('MC', 'Maya Chen', 'Development', '#a9c1ff'), ('DA', 'Diego Alvarez', 'Development', '#9be3b0'),
    ('OH', 'Omar Haddad', 'Development', '#d2b67c'), ('PN', 'Priya Nair', 'Platform', '#b69cff'),
    ('LP', 'Lena Park', 'QA', '#f3d27a'), ('RB', 'Rosa Bianchi', 'Product', '#c7c2ff'),
]
# Minutes, wall clock, for the prototype. fr = first response, res = resolution.
MODULES = ['Operations', 'Finance', 'TVOD', 'International', 'Reporting', 'Platform']
RELEASES = [{'name': '4.12', 'date': '2026-11-07'}, {'name': '4.13', 'date': '2026-12-04'}, {'name': '5.0', 'date': '2027-01-29'}]
SLA_DEFAULT = {'1': {'fr': 60, 'res': 240}, '2': {'fr': 240, 'res': 4320}, '3': {'fr': 480, 'res': 7200}, '4': {'fr': 480, 'res': 7200}}
SLA_OVERRIDES = {'Paramount': {'1': {'fr': 60, 'res': 180}}, 'Fox': {'1': {'fr': 60, 'res': 240}, '2': {'fr': 240, 'res': 2880}}}

# key, type, source, title, client, project, prio, owner, queue, stage, age_mins, fr_after, paused_after, due_days, link, tags, last, notes
T = [
 ('SUP-2381','incident','portal',"Users can't sign in after SSO certificate rotation",'Paramount',None,1,None,'Support L2',0,45,None,None,None,None,['SSO'],None,'All Paramount admins locked out since the 9pm certificate rotation.'),
 ('SUP-2358','incident','email','Intermittent 502 errors on the AMC partner portal','AMC',None,1,'OH','Development',3,300,10,None,None,'Jira DEV-4421',['Availability'],'Omar is on a bridge call with AMC',None),
 ('SUP-2384','incident','teams','Asset ingest queue stalled for live sports feeds','Fox',None,1,'AK','Support L2',2,90,15,None,None,None,['Ingest'],'Ava posted an update in Teams',None),
 ('SUP-2386','incident','email','Playback analytics delayed by about two hours','NBCU',None,2,None,'Support L2',0,20,None,None,None,None,['Analytics'],None,None),
 ('SUP-2376','bug','email','Monthly invoice export totals are off by one cent','NBCU','Coral MSP 4.12 release',2,'MC','Development',3,1500,60,None,None,'Jira DEV-4410',['Invoicing'],'Maya commented in Jira',None),
 ('SUP-2350','bug','email','Scheduled report emails are being sent twice','Fox',None,2,'SO','Support L2',2,3100,100,None,None,None,['Escalation risk'],None,None),
 ('SUP-2383','bug','portal','Thumbnail generation fails for 4K uploads','Netflix','Netflix onboarding',2,None,'Development',1,190,None,None,None,None,['Media'],'Escalated from Support L1',None),
 ('SUP-2372','bug','email','Export to Excel drops rows past 65,000','Netflix',None,2,'DA','Development',3,2000,120,None,None,'Jira DEV-4417',['Exports'],'Diego pushed a fix branch',None),
 ('SUP-2361','bug','email','Usage report double counts shared seats','Paramount','Paramount reporting rollout',2,'MC','Development',4,2600,90,2000,None,'Jira DEV-4409',['Reporting'],'Asked Paramount to confirm the expected figures',None),
 ('SUP-2379','bug','portal','Dashboard widgets show UTC instead of local time','AMC',None,3,'HS','Support L1',1,1500,200,None,None,None,['Reporting'],'Reproduced by Hana',None),
 ('SUP-2387','bug','portal','Search ignores accented characters in titles','AMC',None,3,None,'Support L1',0,400,None,None,None,None,['Search'],None,None),
 ('REQ-311','request','email','Set up 40 user accounts for the new production team','Netflix','Netflix onboarding',3,None,'Support L1',0,120,None,None,None,None,['Accounts'],None,'Spreadsheet of names attached to the original email.'),
 ('REQ-309','request','portal','Enable API access for a new integration partner','Paramount','Paramount reporting rollout',3,'HS','Support L1',2,5600,300,None,None,None,['API'],'Waiting on security sign-off',None),
 ('REQ-305','request','teams',"Add NBCU's new subsidiary as a tenant",'NBCU',None,3,'SO','Support L2',1,2900,100,None,None,None,['Tenants'],'Tenant form received',None),
 ('REQ-312','request','email','Raise API rate limit for the nightly sync','Fox',None,3,'AK','Support L2',2,1400,90,None,None,None,['API'],None,None),
 ('SUP-2369','question','teams','How do we export the audit log for a compliance review?','AMC',None,3,'JR','Support L1',2,2900,60,2800,None,None,['Compliance'],'Jon replied in Teams, waiting on AMC',None),
 ('SUP-2366','question','email','Which IP ranges should Paramount allowlist?','Paramount',None,4,'JR','Support L1',2,1000,200,None,None,None,['Network'],'Jon drafted a reply',None),
 ('SUP-2385','question','portal','Can we schedule exports to an SFTP folder?','Fox',None,4,None,'Support L1',0,30,None,None,None,None,['Exports'],None,None),
 ('SUP-2370','question','email','Is there a sandbox environment for testing?','Netflix','Netflix onboarding',3,'HS','Support L1',2,3000,120,None,None,None,['Environments'],None,None),
 ('CR-047','change','jira','Raise default session timeout from 30 to 60 minutes','NBCU','Coral MSP 4.12 release',3,'LP','QA',4,4000,None,None,10,'Jira DEV-4398',['Config'],'Moved to Verify in Jira',None),
 ('CR-049','change','jira','Switch Fox SSO to the new identity provider','Fox','Fox SSO migration',2,'DA','Development',3,9000,None,None,17,'Jira DEV-4402',['SSO'],'Diego updated in Jira',None),
 ('CR-051','change','ado','Rotate storage account keys for the EU region','Coral Technology',None,2,'PN','Platform',2,6000,None,None,0,'Azure DevOps #8840',['Security'],'Priya scheduled a maintenance window',None),
 ('CR-052','change','board','Add the Paramount logo to the client portal sign-in page','Paramount','Paramount reporting rollout',3,'JR','Support L1',1,2000,None,None,5,None,['Branding'],None,None),
 ('FR-118','feature','portal','Bulk user import from CSV','Coral Technology','Product backlog',3,None,'Product',0,2900,None,None,None,None,['Requested by 3 clients'],'Asked for by Netflix, Fox and AMC',None),
 ('FR-121','feature','teams','Saved filters on the content dashboard','NBCU','Product backlog',4,'RB','Product',1,4500,None,None,None,None,['Dashboards'],'Rosa added it to the Q1 shortlist',None),
 ('FR-124','feature','email','Single sign-on for the mobile app','Coral Technology','Product backlog',3,None,'Product',0,7200,None,None,None,None,['Requested by 2 clients'],'Asked for by Paramount and NBCU',None),
 ('FR-125','feature','board','Webhook notifications for task updates','Coral Technology','Product backlog',3,'RB','Product',0,600,None,None,None,None,['Integrations'],None,None),
 ('INT-552','internal','ado','Upgrade staging database to SQL Server 2022','Coral Technology','Coral MSP 4.12 release',2,'PN','Platform',2,5000,None,None,6,'Azure DevOps #8812',['Release blocker'],'Priya updated in Azure DevOps',None),
 ('INT-560','internal','board','Write release notes for Coral MSP 4.12','Coral Technology','Coral MSP 4.12 release',3,'RB','Product',1,1400,None,None,9,None,['Release'],None,None),
 ('INT-548','internal','ado','Load test the new reporting API','Coral Technology','Paramount reporting rollout',3,'LP','QA',2,8000,None,None,13,'Azure DevOps #8790',['Performance'],'Lena logged results',None),
 ('INT-561','internal','board','Publish the November on-call rota','Coral Technology',None,3,'SO','Support L2',2,2500,None,None,3,None,['On-call'],None,None),
 ('INT-562','internal','board','Remove stale feature flags','Coral Technology',None,4,'OH','Development',1,9000,None,None,None,None,['Tech debt'],None,None),
 ('SUP-2340','bug','email','Password reset emails landing in spam','NBCU',None,2,'MC','Development',5,6000,60,None,None,'Jira DEV-4390',['Email'],'Fix deployed and confirmed by NBCU',None),
 ('REQ-300','request','portal','Provision a staging tenant for Netflix','Netflix','Netflix onboarding',3,'SO','Support L2',5,7000,120,None,None,None,['Tenants'],'Tenant handed over',None),
 ('SUP-2345','question','teams','Where is the data retention policy documented?','Fox',None,4,'HS','Support L1',5,5000,90,None,None,None,['Compliance'],'Sent the policy link',None),
 ('CR-044','change','jira','Require MFA for admin roles','AMC',None,2,'DA','Development',5,12000,None,None,None,'Jira DEV-4380',['Security'],'Released in 4.11',None),
]
T += [
 ('SUP-2388','incident','portal','TVOD purchases failing on the Canadian storefront','Netflix',None,1,None,'Support L2',0,10,None,None,None,None,['Payments'],None,None),
 ('SUP-2389','bug','email','Finance export is missing the VAT column for UK entities','AMC',None,2,None,'Support L1',0,60,None,None,None,None,['Exports'],None,None),
 ('SUP-2331','bug','portal','Rights window dates shift by one day for APAC territories','Fox',None,3,None,'Development',1,9000,60,None,None,None,['Rights'],'Accepted for 4.13, needs an owner',None),
 ('SUP-2335','bug','email','Royalty statement totals round differently from invoices','Paramount',None,4,None,'Support L2',1,15000,120,None,None,None,['Royalties'],'Parked in the backlog',None),
 ('FR-126','feature','email','Multi-currency invoices for international clients','Coral Technology','Product backlog',3,None,'Product',0,20000,None,None,None,None,['Requested by 2 clients'],'Asked for by Fox and NBCU',None),
 ('FR-127','feature','teams','TVOD price tiers by territory','NBCU','Product backlog',4,'RB','Product',1,12000,None,None,None,None,['Pricing'],None,None),
 ('INT-563','internal','board','Document the TVOD settlement process','Coral Technology',None,4,None,'Product',0,8000,None,None,None,None,['Docs'],None,None),
]
# key -> (product module, release: None | 'Backlog' | release name)
MODREL = {
 'SUP-2381':('Platform',None),'SUP-2358':('Operations',None),'SUP-2384':('Operations',None),'SUP-2386':('Reporting',None),
 'SUP-2376':('Finance','4.12'),'SUP-2350':('Reporting',None),'SUP-2383':('TVOD',None),'SUP-2372':('Reporting','4.12'),
 'SUP-2361':('Finance',None),'SUP-2379':('Reporting','4.13'),'SUP-2387':('TVOD',None),'REQ-311':('Operations',None),
 'REQ-309':('Platform',None),'REQ-305':('International',None),'REQ-312':('Platform',None),'SUP-2369':('Operations',None),
 'SUP-2366':('Platform',None),'SUP-2385':('Operations',None),'SUP-2370':('Platform',None),'CR-047':('Platform','4.12'),
 'CR-049':('Platform','4.13'),'CR-051':('Platform',None),'CR-052':('Operations',None),'FR-118':('Operations','Backlog'),
 'FR-121':('Reporting','Backlog'),'FR-124':('Platform','5.0'),'FR-125':('Platform','4.13'),'INT-552':('Platform','4.12'),
 'INT-560':('Operations','4.12'),'INT-548':('Reporting',None),'INT-561':('Operations',None),'INT-562':('Platform','Backlog'),
 'SUP-2340':('Platform',None),'REQ-300':('Operations',None),'SUP-2345':('Operations',None),'CR-044':('Platform',None),
 'SUP-2388':('TVOD',None),'SUP-2389':('Finance',None),'SUP-2331':('International','4.13'),'SUP-2335':('Finance','Backlog'),
 'FR-126':('Finance','Backlog'),'FR-127':('TVOD','Backlog'),'INT-563':('TVOD','Backlog'),
}
assert set(MODREL) == {x[0] for x in T}, set(MODREL) ^ {x[0] for x in T}

SRC_LABEL = {'portal': 'support portal', 'email': 'email', 'teams': 'Teams', 'jira': 'Jira', 'ado': 'Azure DevOps', 'board': 'the board'}
NAME = {p[0]: p[1] for p in PEOPLE}

docs = []
for (key, typ, src, title, client, project, prio, owner, queue, stage, age, fr, paused, due, link, tags, last, notes) in T:
    created = NOW - timedelta(minutes=age)
    hist = [{'at': iso(created), 'text': f'Created from {SRC_LABEL[src]}'}]
    if owner:
        hist.append({'at': iso(created + timedelta(minutes=min(age * 0.1, 30))), 'text': f'Assigned to {NAME[owner]}'})
    if fr is not None:
        hist.append({'at': iso(created + timedelta(minutes=fr)), 'text': 'First response sent'})
    if paused is not None:
        hist.append({'at': iso(created + timedelta(minutes=paused)), 'text': 'Waiting on client'})
    resolved = None
    if stage == 5:
        resolved = created + timedelta(minutes=age * 0.6)
        hist.append({'at': iso(resolved), 'text': 'Moved to Done'})
    if last:
        hist.append({'at': iso(NOW - timedelta(minutes=min(age * 0.2, 180))), 'text': last})
    hist.sort(key=lambda h: h['at'])
    due_date = None
    if due is not None:
        due_date = (NOW + timedelta(days=due)).strftime('%Y-%m-%d')
    d = {
        'key': key, 'type': typ, 'source': src, 'title': title, 'client': client, 'project': project,
        'priority': prio, 'owner': owner, 'queue': queue, 'stage': stage,
        'createdAt': iso(created),
        'firstResponseAt': iso(created + timedelta(minutes=fr)) if fr is not None else None,
        'pausedSince': iso(created + timedelta(minutes=paused)) if paused is not None else None,
        'pausedMins': 0, 'resolvedAt': iso(resolved), 'due': due_date,
        'module': MODREL[key][0], 'release': MODREL[key][1],
        'link': link, 'tags': tags, 'notes': notes or '', 'history': hist, 'updatedAt': iso(NOW),
    }
    docs.append(d)

os.makedirs(OUT, exist_ok=True)
writes = []
def put(coll, doc_id, data):
    p = os.path.join(OUT, f'{coll}__{doc_id}.json')
    json.dump(data, open(p, 'w'), indent=1)
    writes.append({'op': 'set', 'collection': coll, 'doc_id': doc_id, 'file_path': p})

put('config', 'settings', {'clients': CLIENTS, 'projects': PROJECTS, 'teams': TEAMS, 'modules': MODULES, 'releases': RELEASES,
                           'sla': {'default': SLA_DEFAULT, 'overrides': SLA_OVERRIDES},
                           'seededAt': iso(NOW)})
for pid, name, team, color in PEOPLE:
    put('people', pid, {'name': name, 'team': team, 'color': color})
for d in docs:
    put('tasks', d['key'], d)
json.dump(writes, open(os.path.join(OUT, '_writes.json'), 'w'), indent=1)

# ---------- SQL Server seed, times relative to when the script runs ----------
def q(s): return 'NULL' if s is None else "N'" + str(s).replace("'", "''") + "'"
L = ['-- Coral MSP action board: test data (SQL Server)',
     '-- Generated from the same source as the prototype. Times are relative to when you run it.',
     'SET NOCOUNT ON;', 'DECLARE @now DATETIME2(0) = SYSUTCDATETIME();', '']
L.append('INSERT INTO dbo.client (name, support_tier, is_internal) VALUES')
L.append(',\n'.join(f"    ({q(c)}, 'Standard', {1 if c == 'Coral Technology' else 0})" for c in CLIENTS) + ';')
L.append('\nINSERT INTO dbo.product (name) VALUES (N\'Coral MSP\');')
L.append('\nINSERT INTO dbo.product_module (product_id, name)')
L.append("SELECT (SELECT product_id FROM dbo.product WHERE name = N'Coral MSP'), v.name FROM (VALUES")
L.append(',\n'.join(f'    ({q(m)})' for m in MODULES) + '\n) v(name);')
L.append('\n-- Releases count from when you run the script; Backlog has no ship date')
L.append('INSERT INTO dbo.product_release (name, ship_date) VALUES')
L.append(',\n'.join(f"    ({q(r['name'])}, CAST(DATEADD(DAY, {(datetime.strptime(r['date'], '%Y-%m-%d').replace(tzinfo=timezone.utc) - NOW).days + 1}, @now) AS DATE))" for r in RELEASES) + ",\n    (N'Backlog', NULL);")
L.append('\nINSERT INTO dbo.team (name) VALUES')
L.append(',\n'.join(f'    ({q(t)})' for t in TEAMS) + ';')
L.append('\nINSERT INTO dbo.project (name, client_id, product_id)')
L.append('SELECT v.name, c.client_id, (SELECT product_id FROM dbo.product WHERE name = N\'Coral MSP\')')
pc = {'Coral MSP 4.12 release': None, 'Netflix onboarding': 'Netflix', 'Fox SSO migration': 'Fox',
      'Paramount reporting rollout': 'Paramount', 'Product backlog': None}
L.append('FROM (VALUES\n' + ',\n'.join(f'    ({q(p)}, {q(c)})' for p, c in pc.items()) + '\n) v(name, client_name)')
L.append('LEFT JOIN dbo.client c ON c.name = v.client_name;')
L.append('\nINSERT INTO dbo.person (person_code, display_name, email, team_id)')
L.append('SELECT v.code, v.name, v.email, t.team_id FROM (VALUES')
L.append(',\n'.join(f"    ({q(p)}, {q(n)}, {q(n.lower().replace(' ', '.') + '@coraltechnology.example')}, {q(tm)})" for p, n, tm, _ in PEOPLE))
L.append(') v(code, name, email, team) JOIN dbo.team t ON t.name = v.team;')
L.append('\n-- Default SLA by priority (support tier Standard), then client overrides. Minutes.')
L.append('INSERT INTO dbo.sla_policy (client_id, support_tier, priority, first_response_mins, resolution_mins) VALUES')
rows = [f"    (NULL, 'Standard', {p}, {v['fr']}, {v['res']})" for p, v in SLA_DEFAULT.items()]
L.append(',\n'.join(rows) + ';')
L.append('INSERT INTO dbo.sla_policy (client_id, support_tier, priority, first_response_mins, resolution_mins)')
L.append('SELECT c.client_id, NULL, v.p, v.fr, v.res FROM (VALUES')
L.append(',\n'.join(f'    ({q(c)}, {p}, {v["fr"]}, {v["res"]})' for c, m in SLA_OVERRIDES.items() for p, v in m.items()))
L.append(') v(client, p, fr, res) JOIN dbo.client c ON c.name = v.client;')

L.append('\n-- Tasks. age = minutes since created; offsets are minutes after creation.')
L.append('INSERT INTO dbo.task (task_key, title, task_type, source_system, priority, stage, client_id, product_id, project_id,')
L.append('                      owner_person_id, queue_team_id, module_id, release_id, created_at, first_response_at, sla_paused_since, resolved_at, due_date, external_ref, notes)')
L.append('SELECT v.task_key, v.title, v.task_type, v.source_system, v.priority, v.stage, c.client_id,')
L.append("       (SELECT product_id FROM dbo.product WHERE name = N'Coral MSP'), pj.project_id, p.person_id, tm.team_id, md.module_id, rl.release_id,")
L.append('       DATEADD(MINUTE, -v.age, @now),')
L.append('       CASE WHEN v.fr IS NOT NULL THEN DATEADD(MINUTE, v.fr - v.age, @now) END,')
L.append('       CASE WHEN v.paused IS NOT NULL THEN DATEADD(MINUTE, v.paused - v.age, @now) END,')
L.append("       CASE WHEN v.stage = 'done' THEN DATEADD(MINUTE, -v.age * 4 / 10, @now) END,")
L.append('       CASE WHEN v.due_days IS NOT NULL THEN CAST(DATEADD(DAY, v.due_days, @now) AS DATE) END,')
L.append('       v.external_ref, v.notes')
L.append('FROM (VALUES')
STAGE = ['triage', 'queued', 'in_progress', 'in_dev', 'verify', 'done']
vals = []
for (key, typ, src, title, client, project, prio, owner, queue, stage, age, fr, paused, due, link, tags, last, notes) in T:
    n = lambda x: 'NULL' if x is None else str(x)
    vals.append(f"    ({q(key)}, {q(title)}, {q(typ)}, {q(src)}, {prio}, {q(STAGE[stage])}, {q(client)}, {q(project)}, {q(owner)}, {q(queue)}, "
                f"{q(MODREL[key][0])}, {q(MODREL[key][1])}, {age}, {n(fr)}, {n(paused)}, {n(due)}, {q(link)}, {q(notes)})")
L.append(',\n'.join(vals))
L.append(') v(task_key, title, task_type, source_system, priority, stage, client, project, owner_code, queue, module, rel, age, fr, paused, due_days, external_ref, notes)')
L.append('JOIN dbo.client c ON c.name = v.client')
L.append('LEFT JOIN dbo.project pj ON pj.name = v.project')
L.append('LEFT JOIN dbo.person p ON p.person_code = v.owner_code')
L.append('LEFT JOIN dbo.team tm ON tm.name = v.queue')
L.append('LEFT JOIN dbo.product_module md ON md.name = v.module')
L.append('LEFT JOIN dbo.product_release rl ON rl.name = v.rel;')

L.append('\n-- Tags and activity history')
L.append('INSERT INTO dbo.task_tag (task_id, tag)')
L.append('SELECT t.task_id, v.tag FROM (VALUES')
L.append(',\n'.join(f'    ({q(k)}, {q(tag)})' for (k, *_rest) in T for tag in _rest[14]))
L.append(') v(task_key, tag) JOIN dbo.task t ON t.task_key = v.task_key;')
L.append('\nINSERT INTO dbo.task_activity (task_id, occurred_at, message)')
L.append('SELECT t.task_id, DATEADD(SECOND, v.secs_ago * -1, @now), v.msg FROM (VALUES')
acts = []
for d in docs:
    for h in d['history']:
        ago = int((NOW - datetime.strptime(h['at'], '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc)).total_seconds())
        acts.append(f"    ({q(d['key'])}, {ago}, {q(h['text'])})")
L.append(',\n'.join(acts))
L.append(') v(task_key, secs_ago, msg) JOIN dbo.task t ON t.task_key = v.task_key;')
L.append('')
open(SQL_OUT, 'w').write('\n'.join(L))
print(len(writes), 'docs;', len(acts), 'activity rows')
