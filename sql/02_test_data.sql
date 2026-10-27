-- Coral MSP action board: test data (SQL Server)
-- Generated from the same source as the prototype. Times are relative to when you run it.
SET NOCOUNT ON;
DECLARE @now DATETIME2(0) = SYSUTCDATETIME();

INSERT INTO dbo.client (name, support_tier, is_internal) VALUES
    (N'Paramount', 'Standard', 0),
    (N'AMC', 'Standard', 0),
    (N'Netflix', 'Standard', 0),
    (N'NBCU', 'Standard', 0),
    (N'Fox', 'Standard', 0),
    (N'Coral Technology', 'Standard', 1);

INSERT INTO dbo.product (name) VALUES (N'Coral MSP');

INSERT INTO dbo.team (name) VALUES
    (N'Support L1'),
    (N'Support L2'),
    (N'Development'),
    (N'Platform'),
    (N'QA'),
    (N'Product');

INSERT INTO dbo.project (name, client_id, product_id)
SELECT v.name, c.client_id, (SELECT product_id FROM dbo.product WHERE name = N'Coral MSP')
FROM (VALUES
    (N'Coral MSP 4.12 release', NULL),
    (N'Netflix onboarding', N'Netflix'),
    (N'Fox SSO migration', N'Fox'),
    (N'Paramount reporting rollout', N'Paramount'),
    (N'Product backlog', NULL)
) v(name, client_name)
LEFT JOIN dbo.client c ON c.name = v.client_name;

INSERT INTO dbo.person (person_code, display_name, email, team_id)
SELECT v.code, v.name, v.email, t.team_id FROM (VALUES
    (N'JR', N'Jon Ruiz', N'jon.ruiz@coraltechnology.example', N'Support L1'),
    (N'HS', N'Hana Sato', N'hana.sato@coraltechnology.example', N'Support L1'),
    (N'SO', N'Sam Okafor', N'sam.okafor@coraltechnology.example', N'Support L2'),
    (N'AK', N'Ava Kowalski', N'ava.kowalski@coraltechnology.example', N'Support L2'),
    (N'MC', N'Maya Chen', N'maya.chen@coraltechnology.example', N'Development'),
    (N'DA', N'Diego Alvarez', N'diego.alvarez@coraltechnology.example', N'Development'),
    (N'OH', N'Omar Haddad', N'omar.haddad@coraltechnology.example', N'Development'),
    (N'PN', N'Priya Nair', N'priya.nair@coraltechnology.example', N'Platform'),
    (N'LP', N'Lena Park', N'lena.park@coraltechnology.example', N'QA'),
    (N'RB', N'Rosa Bianchi', N'rosa.bianchi@coraltechnology.example', N'Product')
) v(code, name, email, team) JOIN dbo.team t ON t.name = v.team;

-- Default SLA by priority (support tier Standard), then client overrides. Minutes.
INSERT INTO dbo.sla_policy (client_id, support_tier, priority, first_response_mins, resolution_mins) VALUES
    (NULL, 'Standard', 1, 60, 240),
    (NULL, 'Standard', 2, 240, 4320),
    (NULL, 'Standard', 3, 480, 7200),
    (NULL, 'Standard', 4, 480, 7200);
INSERT INTO dbo.sla_policy (client_id, support_tier, priority, first_response_mins, resolution_mins)
SELECT c.client_id, NULL, v.p, v.fr, v.res FROM (VALUES
    (N'Paramount', 1, 60, 180),
    (N'Fox', 1, 60, 240),
    (N'Fox', 2, 240, 2880)
) v(client, p, fr, res) JOIN dbo.client c ON c.name = v.client;

-- Tasks. age = minutes since created; offsets are minutes after creation.
INSERT INTO dbo.task (task_key, title, task_type, source_system, priority, stage, client_id, product_id, project_id,
                      owner_person_id, queue_team_id, created_at, first_response_at, sla_paused_since, resolved_at, due_date, external_ref, notes)
SELECT v.task_key, v.title, v.task_type, v.source_system, v.priority, v.stage, c.client_id,
       (SELECT product_id FROM dbo.product WHERE name = N'Coral MSP'), pj.project_id, p.person_id, tm.team_id,
       DATEADD(MINUTE, -v.age, @now),
       CASE WHEN v.fr IS NOT NULL THEN DATEADD(MINUTE, v.fr - v.age, @now) END,
       CASE WHEN v.paused IS NOT NULL THEN DATEADD(MINUTE, v.paused - v.age, @now) END,
       CASE WHEN v.stage = 'done' THEN DATEADD(MINUTE, -v.age * 4 / 10, @now) END,
       CASE WHEN v.due_days IS NOT NULL THEN CAST(DATEADD(DAY, v.due_days, @now) AS DATE) END,
       v.external_ref, v.notes
FROM (VALUES
    (N'SUP-2381', N'Users can''t sign in after SSO certificate rotation', N'incident', N'portal', 1, N'triage', N'Paramount', NULL, NULL, N'Support L2', 45, NULL, NULL, NULL, NULL, N'All Paramount admins locked out since the 9pm certificate rotation.'),
    (N'SUP-2358', N'Intermittent 502 errors on the AMC partner portal', N'incident', N'email', 1, N'in_dev', N'AMC', NULL, N'OH', N'Development', 300, 10, NULL, NULL, N'Jira DEV-4421', NULL),
    (N'SUP-2384', N'Asset ingest queue stalled for live sports feeds', N'incident', N'teams', 1, N'in_progress', N'Fox', NULL, N'AK', N'Support L2', 90, 15, NULL, NULL, NULL, NULL),
    (N'SUP-2386', N'Playback analytics delayed by about two hours', N'incident', N'email', 2, N'triage', N'NBCU', NULL, NULL, N'Support L2', 20, NULL, NULL, NULL, NULL, NULL),
    (N'SUP-2376', N'Monthly invoice export totals are off by one cent', N'bug', N'email', 2, N'in_dev', N'NBCU', N'Coral MSP 4.12 release', N'MC', N'Development', 1500, 60, NULL, NULL, N'Jira DEV-4410', NULL),
    (N'SUP-2350', N'Scheduled report emails are being sent twice', N'bug', N'email', 2, N'in_progress', N'Fox', NULL, N'SO', N'Support L2', 3100, 100, NULL, NULL, NULL, NULL),
    (N'SUP-2383', N'Thumbnail generation fails for 4K uploads', N'bug', N'portal', 2, N'ready', N'Netflix', N'Netflix onboarding', NULL, N'Development', 190, NULL, NULL, NULL, NULL, NULL),
    (N'SUP-2372', N'Export to Excel drops rows past 65,000', N'bug', N'email', 2, N'in_dev', N'Netflix', NULL, N'DA', N'Development', 2000, 120, NULL, NULL, N'Jira DEV-4417', NULL),
    (N'SUP-2361', N'Usage report double counts shared seats', N'bug', N'email', 2, N'verify', N'Paramount', N'Paramount reporting rollout', N'MC', N'Development', 2600, 90, 2000, NULL, N'Jira DEV-4409', NULL),
    (N'SUP-2379', N'Dashboard widgets show UTC instead of local time', N'bug', N'portal', 3, N'ready', N'AMC', NULL, N'HS', N'Support L1', 1500, 200, NULL, NULL, NULL, NULL),
    (N'SUP-2387', N'Search ignores accented characters in titles', N'bug', N'portal', 3, N'triage', N'AMC', NULL, NULL, N'Support L1', 400, NULL, NULL, NULL, NULL, NULL),
    (N'REQ-311', N'Set up 40 user accounts for the new production team', N'request', N'email', 3, N'triage', N'Netflix', N'Netflix onboarding', NULL, N'Support L1', 120, NULL, NULL, NULL, NULL, N'Spreadsheet of names attached to the original email.'),
    (N'REQ-309', N'Enable API access for a new integration partner', N'request', N'portal', 3, N'in_progress', N'Paramount', N'Paramount reporting rollout', N'HS', N'Support L1', 5600, 300, NULL, NULL, NULL, NULL),
    (N'REQ-305', N'Add NBCU''s new subsidiary as a tenant', N'request', N'teams', 3, N'ready', N'NBCU', NULL, N'SO', N'Support L2', 2900, 100, NULL, NULL, NULL, NULL),
    (N'REQ-312', N'Raise API rate limit for the nightly sync', N'request', N'email', 3, N'in_progress', N'Fox', NULL, N'AK', N'Support L2', 1400, 90, NULL, NULL, NULL, NULL),
    (N'SUP-2369', N'How do we export the audit log for a compliance review?', N'question', N'teams', 3, N'in_progress', N'AMC', NULL, N'JR', N'Support L1', 2900, 60, 2800, NULL, NULL, NULL),
    (N'SUP-2366', N'Which IP ranges should Paramount allowlist?', N'question', N'email', 4, N'in_progress', N'Paramount', NULL, N'JR', N'Support L1', 1000, 200, NULL, NULL, NULL, NULL),
    (N'SUP-2385', N'Can we schedule exports to an SFTP folder?', N'question', N'portal', 4, N'triage', N'Fox', NULL, NULL, N'Support L1', 30, NULL, NULL, NULL, NULL, NULL),
    (N'SUP-2370', N'Is there a sandbox environment for testing?', N'question', N'email', 3, N'in_progress', N'Netflix', N'Netflix onboarding', N'HS', N'Support L1', 3000, 120, NULL, NULL, NULL, NULL),
    (N'CR-047', N'Raise default session timeout from 30 to 60 minutes', N'change', N'jira', 3, N'verify', N'NBCU', N'Coral MSP 4.12 release', N'LP', N'QA', 4000, NULL, NULL, 10, N'Jira DEV-4398', NULL),
    (N'CR-049', N'Switch Fox SSO to the new identity provider', N'change', N'jira', 2, N'in_dev', N'Fox', N'Fox SSO migration', N'DA', N'Development', 9000, NULL, NULL, 17, N'Jira DEV-4402', NULL),
    (N'CR-051', N'Rotate storage account keys for the EU region', N'change', N'ado', 2, N'in_progress', N'Coral Technology', NULL, N'PN', N'Platform', 6000, NULL, NULL, 0, N'Azure DevOps #8840', NULL),
    (N'CR-052', N'Add the Paramount logo to the client portal sign-in page', N'change', N'board', 3, N'ready', N'Paramount', N'Paramount reporting rollout', N'JR', N'Support L1', 2000, NULL, NULL, 5, NULL, NULL),
    (N'FR-118', N'Bulk user import from CSV', N'feature', N'portal', 3, N'triage', N'Coral Technology', N'Product backlog', NULL, N'Product', 2900, NULL, NULL, NULL, NULL, NULL),
    (N'FR-121', N'Saved filters on the content dashboard', N'feature', N'teams', 4, N'ready', N'NBCU', N'Product backlog', N'RB', N'Product', 4500, NULL, NULL, NULL, NULL, NULL),
    (N'FR-124', N'Single sign-on for the mobile app', N'feature', N'email', 3, N'triage', N'Coral Technology', N'Product backlog', NULL, N'Product', 7200, NULL, NULL, NULL, NULL, NULL),
    (N'FR-125', N'Webhook notifications for task updates', N'feature', N'board', 3, N'triage', N'Coral Technology', N'Product backlog', N'RB', N'Product', 600, NULL, NULL, NULL, NULL, NULL),
    (N'INT-552', N'Upgrade staging database to SQL Server 2022', N'internal', N'ado', 2, N'in_progress', N'Coral Technology', N'Coral MSP 4.12 release', N'PN', N'Platform', 5000, NULL, NULL, 6, N'Azure DevOps #8812', NULL),
    (N'INT-560', N'Write release notes for Coral MSP 4.12', N'internal', N'board', 3, N'ready', N'Coral Technology', N'Coral MSP 4.12 release', N'RB', N'Product', 1400, NULL, NULL, 9, NULL, NULL),
    (N'INT-548', N'Load test the new reporting API', N'internal', N'ado', 3, N'in_progress', N'Coral Technology', N'Paramount reporting rollout', N'LP', N'QA', 8000, NULL, NULL, 13, N'Azure DevOps #8790', NULL),
    (N'INT-561', N'Publish the November on-call rota', N'internal', N'board', 3, N'in_progress', N'Coral Technology', NULL, N'SO', N'Support L2', 2500, NULL, NULL, 3, NULL, NULL),
    (N'INT-562', N'Remove stale feature flags', N'internal', N'board', 4, N'ready', N'Coral Technology', NULL, N'OH', N'Development', 9000, NULL, NULL, NULL, NULL, NULL),
    (N'SUP-2340', N'Password reset emails landing in spam', N'bug', N'email', 2, N'done', N'NBCU', NULL, N'MC', N'Development', 6000, 60, NULL, NULL, N'Jira DEV-4390', NULL),
    (N'REQ-300', N'Provision a staging tenant for Netflix', N'request', N'portal', 3, N'done', N'Netflix', N'Netflix onboarding', N'SO', N'Support L2', 7000, 120, NULL, NULL, NULL, NULL),
    (N'SUP-2345', N'Where is the data retention policy documented?', N'question', N'teams', 4, N'done', N'Fox', NULL, N'HS', N'Support L1', 5000, 90, NULL, NULL, NULL, NULL),
    (N'CR-044', N'Require MFA for admin roles', N'change', N'jira', 2, N'done', N'AMC', NULL, N'DA', N'Development', 12000, NULL, NULL, NULL, N'Jira DEV-4380', NULL)
) v(task_key, title, task_type, source_system, priority, stage, client, project, owner_code, queue, age, fr, paused, due_days, external_ref, notes)
JOIN dbo.client c ON c.name = v.client
LEFT JOIN dbo.project pj ON pj.name = v.project
LEFT JOIN dbo.person p ON p.person_code = v.owner_code
LEFT JOIN dbo.team tm ON tm.name = v.queue;

-- Tags and activity history
INSERT INTO dbo.task_tag (task_id, tag)
SELECT t.task_id, v.tag FROM (VALUES
    (N'SUP-2381', N'SSO'),
    (N'SUP-2358', N'Availability'),
    (N'SUP-2384', N'Ingest'),
    (N'SUP-2386', N'Analytics'),
    (N'SUP-2376', N'Invoicing'),
    (N'SUP-2350', N'Escalation risk'),
    (N'SUP-2383', N'Media'),
    (N'SUP-2372', N'Exports'),
    (N'SUP-2361', N'Reporting'),
    (N'SUP-2379', N'Reporting'),
    (N'SUP-2387', N'Search'),
    (N'REQ-311', N'Accounts'),
    (N'REQ-309', N'API'),
    (N'REQ-305', N'Tenants'),
    (N'REQ-312', N'API'),
    (N'SUP-2369', N'Compliance'),
    (N'SUP-2366', N'Network'),
    (N'SUP-2385', N'Exports'),
    (N'SUP-2370', N'Environments'),
    (N'CR-047', N'Config'),
    (N'CR-049', N'SSO'),
    (N'CR-051', N'Security'),
    (N'CR-052', N'Branding'),
    (N'FR-118', N'Requested by 3 clients'),
    (N'FR-121', N'Dashboards'),
    (N'FR-124', N'Requested by 2 clients'),
    (N'FR-125', N'Integrations'),
    (N'INT-552', N'Release blocker'),
    (N'INT-560', N'Release'),
    (N'INT-548', N'Performance'),
    (N'INT-561', N'On-call'),
    (N'INT-562', N'Tech debt'),
    (N'SUP-2340', N'Email'),
    (N'REQ-300', N'Tenants'),
    (N'SUP-2345', N'Compliance'),
    (N'CR-044', N'Security')
) v(task_key, tag) JOIN dbo.task t ON t.task_key = v.task_key;

INSERT INTO dbo.task_activity (task_id, occurred_at, message)
SELECT t.task_id, DATEADD(SECOND, v.secs_ago * -1, @now), v.msg FROM (VALUES
    (N'SUP-2381', 2700, N'Created from support portal'),
    (N'SUP-2358', 18000, N'Created from email'),
    (N'SUP-2358', 17400, N'First response sent'),
    (N'SUP-2358', 16200, N'Assigned to Omar Haddad'),
    (N'SUP-2358', 3600, N'Omar is on a bridge call with AMC'),
    (N'SUP-2384', 5400, N'Created from Teams'),
    (N'SUP-2384', 4860, N'Assigned to Ava Kowalski'),
    (N'SUP-2384', 4500, N'First response sent'),
    (N'SUP-2384', 1080, N'Ava posted an update in Teams'),
    (N'SUP-2386', 1200, N'Created from email'),
    (N'SUP-2376', 90000, N'Created from email'),
    (N'SUP-2376', 88200, N'Assigned to Maya Chen'),
    (N'SUP-2376', 86400, N'First response sent'),
    (N'SUP-2376', 10800, N'Maya commented in Jira'),
    (N'SUP-2350', 186000, N'Created from email'),
    (N'SUP-2350', 184200, N'Assigned to Sam Okafor'),
    (N'SUP-2350', 180000, N'First response sent'),
    (N'SUP-2383', 11400, N'Created from support portal'),
    (N'SUP-2383', 2280, N'Escalated from Support L1'),
    (N'SUP-2372', 120000, N'Created from email'),
    (N'SUP-2372', 118200, N'Assigned to Diego Alvarez'),
    (N'SUP-2372', 112800, N'First response sent'),
    (N'SUP-2372', 10800, N'Diego pushed a fix branch'),
    (N'SUP-2361', 156000, N'Created from email'),
    (N'SUP-2361', 154200, N'Assigned to Maya Chen'),
    (N'SUP-2361', 150600, N'First response sent'),
    (N'SUP-2361', 36000, N'Waiting on client'),
    (N'SUP-2361', 10800, N'Asked Paramount to confirm the expected figures'),
    (N'SUP-2379', 90000, N'Created from support portal'),
    (N'SUP-2379', 88200, N'Assigned to Hana Sato'),
    (N'SUP-2379', 78000, N'First response sent'),
    (N'SUP-2379', 10800, N'Reproduced by Hana'),
    (N'SUP-2387', 24000, N'Created from support portal'),
    (N'REQ-311', 7200, N'Created from email'),
    (N'REQ-309', 336000, N'Created from support portal'),
    (N'REQ-309', 334200, N'Assigned to Hana Sato'),
    (N'REQ-309', 318000, N'First response sent'),
    (N'REQ-309', 10800, N'Waiting on security sign-off'),
    (N'REQ-305', 174000, N'Created from Teams'),
    (N'REQ-305', 172200, N'Assigned to Sam Okafor'),
    (N'REQ-305', 168000, N'First response sent'),
    (N'REQ-305', 10800, N'Tenant form received'),
    (N'REQ-312', 84000, N'Created from email'),
    (N'REQ-312', 82200, N'Assigned to Ava Kowalski'),
    (N'REQ-312', 78600, N'First response sent'),
    (N'SUP-2369', 174000, N'Created from Teams'),
    (N'SUP-2369', 172200, N'Assigned to Jon Ruiz'),
    (N'SUP-2369', 170400, N'First response sent'),
    (N'SUP-2369', 10800, N'Jon replied in Teams, waiting on AMC'),
    (N'SUP-2369', 6000, N'Waiting on client'),
    (N'SUP-2366', 60000, N'Created from email'),
    (N'SUP-2366', 58200, N'Assigned to Jon Ruiz'),
    (N'SUP-2366', 48000, N'First response sent'),
    (N'SUP-2366', 10800, N'Jon drafted a reply'),
    (N'SUP-2385', 1800, N'Created from support portal'),
    (N'SUP-2370', 180000, N'Created from email'),
    (N'SUP-2370', 178200, N'Assigned to Hana Sato'),
    (N'SUP-2370', 172800, N'First response sent'),
    (N'CR-047', 240000, N'Created from Jira'),
    (N'CR-047', 238200, N'Assigned to Lena Park'),
    (N'CR-047', 10800, N'Moved to Verify in Jira'),
    (N'CR-049', 540000, N'Created from Jira'),
    (N'CR-049', 538200, N'Assigned to Diego Alvarez'),
    (N'CR-049', 10800, N'Diego updated in Jira'),
    (N'CR-051', 360000, N'Created from Azure DevOps'),
    (N'CR-051', 358200, N'Assigned to Priya Nair'),
    (N'CR-051', 10800, N'Priya scheduled a maintenance window'),
    (N'CR-052', 120000, N'Created from the board'),
    (N'CR-052', 118200, N'Assigned to Jon Ruiz'),
    (N'FR-118', 174000, N'Created from support portal'),
    (N'FR-118', 10800, N'Asked for by Netflix, Fox and AMC'),
    (N'FR-121', 270000, N'Created from Teams'),
    (N'FR-121', 268200, N'Assigned to Rosa Bianchi'),
    (N'FR-121', 10800, N'Rosa added it to the Q1 shortlist'),
    (N'FR-124', 432000, N'Created from email'),
    (N'FR-124', 10800, N'Asked for by Paramount and NBCU'),
    (N'FR-125', 36000, N'Created from the board'),
    (N'FR-125', 34200, N'Assigned to Rosa Bianchi'),
    (N'INT-552', 300000, N'Created from Azure DevOps'),
    (N'INT-552', 298200, N'Assigned to Priya Nair'),
    (N'INT-552', 10800, N'Priya updated in Azure DevOps'),
    (N'INT-560', 84000, N'Created from the board'),
    (N'INT-560', 82200, N'Assigned to Rosa Bianchi'),
    (N'INT-548', 480000, N'Created from Azure DevOps'),
    (N'INT-548', 478200, N'Assigned to Lena Park'),
    (N'INT-548', 10800, N'Lena logged results'),
    (N'INT-561', 150000, N'Created from the board'),
    (N'INT-561', 148200, N'Assigned to Sam Okafor'),
    (N'INT-562', 540000, N'Created from the board'),
    (N'INT-562', 538200, N'Assigned to Omar Haddad'),
    (N'SUP-2340', 360000, N'Created from email'),
    (N'SUP-2340', 358200, N'Assigned to Maya Chen'),
    (N'SUP-2340', 356400, N'First response sent'),
    (N'SUP-2340', 144000, N'Moved to Done'),
    (N'SUP-2340', 10800, N'Fix deployed and confirmed by NBCU'),
    (N'REQ-300', 420000, N'Created from support portal'),
    (N'REQ-300', 418200, N'Assigned to Sam Okafor'),
    (N'REQ-300', 412800, N'First response sent'),
    (N'REQ-300', 168000, N'Moved to Done'),
    (N'REQ-300', 10800, N'Tenant handed over'),
    (N'SUP-2345', 300000, N'Created from Teams'),
    (N'SUP-2345', 298200, N'Assigned to Hana Sato'),
    (N'SUP-2345', 294600, N'First response sent'),
    (N'SUP-2345', 120000, N'Moved to Done'),
    (N'SUP-2345', 10800, N'Sent the policy link'),
    (N'CR-044', 720000, N'Created from Jira'),
    (N'CR-044', 718200, N'Assigned to Diego Alvarez'),
    (N'CR-044', 288000, N'Moved to Done'),
    (N'CR-044', 10800, N'Released in 4.11')
) v(task_key, secs_ago, msg) JOIN dbo.task t ON t.task_key = v.task_key;
