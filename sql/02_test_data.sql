-- Coral MSP action board: test data (SQL Server)
-- Generated from the same source as the prototype. Times are relative to when you run it.
SET NOCOUNT ON;
DECLARE @now DATETIME2(0) = SYSUTCDATETIME();

INSERT INTO dbo.client (name, is_internal) VALUES
    (N'Paramount', 0),
    (N'AMC', 0),
    (N'Netflix', 0),
    (N'NBCU', 0),
    (N'Fox', 0),
    (N'Ole', 0),
    (N'NEON', 0),
    (N'Coral Technology', 1);

INSERT INTO dbo.product (name) VALUES (N'Coral MSP');

INSERT INTO dbo.product_module (product_id, name)
SELECT (SELECT product_id FROM dbo.product WHERE name = N'Coral MSP'), v.name FROM (VALUES
    (N'Operations'),
    (N'Finance'),
    (N'TVOD'),
    (N'International'),
    (N'Reporting'),
    (N'Platform')
) v(name);

-- Releases count from when you run the script; Backlog has no ship date
INSERT INTO dbo.product_release (name, ship_date) VALUES
    (N'4.12', CAST(DATEADD(DAY, 10, @now) AS DATE)),
    (N'4.13', CAST(DATEADD(DAY, 37, @now) AS DATE)),
    (N'5.0', CAST(DATEADD(DAY, 93, @now) AS DATE)),
    (N'Backlog', NULL);

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

-- Business calendar and holidays for SLA clocks in business hours or days
INSERT INTO dbo.business_calendar (name, time_zone, day_start, day_end, open_weekdays) VALUES (N'Coral business hours (ET)', N'Eastern Standard Time', '08:00', '18:00', '12345');
DECLARE @cal INT = SCOPE_IDENTITY();
INSERT INTO dbo.business_holiday (calendar_id, holiday_date, name) VALUES
    (@cal, '2026-01-01', N'New Year''s Day'),
    (@cal, '2026-01-19', N'Martin Luther King Jr. Day'),
    (@cal, '2026-02-16', N'Washington''s Birthday'),
    (@cal, '2026-05-25', N'Memorial Day'),
    (@cal, '2026-06-19', N'Juneteenth'),
    (@cal, '2026-07-03', N'Independence Day (observed)'),
    (@cal, '2026-09-07', N'Labor Day'),
    (@cal, '2026-10-12', N'Columbus Day'),
    (@cal, '2026-11-11', N'Veterans Day'),
    (@cal, '2026-11-26', N'Thanksgiving'),
    (@cal, '2026-11-27', N'Day after Thanksgiving'),
    (@cal, '2026-12-25', N'Christmas Day'),
    (@cal, '2027-01-01', N'New Year''s Day'),
    (@cal, '2027-01-18', N'Martin Luther King Jr. Day'),
    (@cal, '2027-02-15', N'Washington''s Birthday'),
    (@cal, '2027-05-31', N'Memorial Day'),
    (@cal, '2027-06-18', N'Juneteenth (observed)'),
    (@cal, '2027-07-05', N'Independence Day (observed)'),
    (@cal, '2027-09-06', N'Labor Day'),
    (@cal, '2027-10-11', N'Columbus Day'),
    (@cal, '2027-11-11', N'Veterans Day'),
    (@cal, '2027-11-25', N'Thanksgiving'),
    (@cal, '2027-11-26', N'Day after Thanksgiving'),
    (@cal, '2027-12-24', N'Christmas Day (observed)');

-- Client SLA terms (from the SLA matrix). client NULL = the Coral standard for everyone else.
INSERT INTO dbo.client_sla (client_id, calendar_id, customer_name, deployment, terms_basis, verification, monthly_uptime, support_hours, after_hours,
                            rto, rpo, hourly_backups, daily_backups, restore_target, service_credits, special_terms, source_documents)
SELECT c.client_id, @cal, v.label, v.deployment, v.basis, v.verification, v.uptime, v.hours, v.after_hours,
       v.rto, v.rpo, v.hourly, v.daily, v.restore_target, v.credits, v.special, v.source
FROM (VALUES
    (NULL, N'Coral standard', NULL, N'Coral standard operational SLA', N'standard', NULL, N'8am–6pm ET, Mon–Fri; holidays excluded', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
    (N'NBCU', N'NBCUniversal', N'coral_hosted', N'Amended MSA Annex A (production)', N'contract', N'99.8%', N'24/7 for Sev 1–2; normal business hours for Sev 3–4', N'24/7 for Sev 1–2', N'Not specified', N'Not specified', N'Not specified', N'Not specified', N'Not specified', N'10% / 25% / 50% by uptime band; annual cap', N'Production SLA differs from UAT and hypercare (UAT: Sev 1 4 business hours, Sev 2 1 business day, Sev 3 2 business days, Sev 4 agreed schedule). Persistent failure allows termination. The credit bands overlap in the source; legal review advised.', N'NBCU Master Agreement Amendment_1.pdf; NBCU MSA'),
    (N'AMC', N'AMC Networks', N'coral_hosted', N'Executed MSA Exhibit A', N'contract', N'99.5%', N'8am–6pm ET, Mon–Fri; holidays excluded', N'Month-end extended support; other extensions subject to terms', N'8 hours', N'1 hour', N'3 months', N'1 year', N'8 hours', N'10% of one quarter of the annual subscription fee, per quarterly terms', N'Availability measured monthly, credits assessed quarterly. Security incident notice within 24 hours.', N'Coral_MSA_Final_8-24-23 For Execution.pdf'),
    (N'Ole', N'Ole', N'coral_hosted', N'MSA Exhibit A', N'unconfirmed', N'99%', N'8am–6pm ET, Mon–Fri; holidays excluded', N'By written request and mutual agreement', N'8 hours', N'1 hour', N'Retention to verify', N'1 year', N'8 hours', N'Not identified', N'Contract terms identified but execution unconfirmed: confirm the signed final copy. Fix clock starts once Coral reproduces the error.', N'Ole Coral Master Hosted Software Agreement (JS 7-15-25).docx'),
    (N'NEON', N'NEON', N'coral_hosted', N'Executed MSA Exhibit C (2026-03-09)', N'contract', N'99%', N'8am–6pm ET, Mon–Fri; holidays excluded', N'By written request and mutual agreement', N'8 hours', N'1 hour', N'3 months', N'1 year', N'8 hours', N'Not specified', N'Severity mutually agreed. 2 months of hypercare. Immediate written notice of an actual or suspected breach (MSA §5.5).', N'NEON License Agreement and SOW Coral Technology 03-09-2026.pdf pp.14–16'),
    (N'Fox', N'Fox', N'customer_hosted', N'Assumed Coral standard operational SLA', N'assumed', N'N/A', N'8am–6pm ET, Mon–Fri; holidays excluded', N'By written agreement (assumed)', N'N/A', N'N/A', N'Customer responsibility / unverified', N'Customer responsibility / unverified', N'N/A', N'None verified', N'Historical published support policy unavailable: the numbers are an operational assumption, not contract text. Prompt written notice and mitigation of security flaws or breaches (MSA Exhibit 1).', N'Foxcorp Holdings-Coral Technology Master License and Services Agreement (Fully Executed).pdf §3.5; Fox executed Order'),
    (N'Paramount', N'Paramount / CBS', N'customer_hosted', N'Assumed Coral standard operational SLA', N'assumed', N'N/A', N'8am–6pm ET, Mon–Fri; holidays excluded', N'By written agreement (assumed)', N'N/A', N'N/A', N'Customer responsibility / unverified', N'Customer responsibility / unverified', N'N/A', N'None verified', N'A separate amended work order gives low, medium and high bugs 3, 6 and 10 days of development effort. That is effort, not an elapsed-time incident SLA.', N'Coral Tech - Paramount Global Amended Work Order AMS - 3-9-2022 CLEAN.pdf; CBS MSA and work order')
) v(client, label, deployment, basis, verification, uptime, hours, after_hours, rto, rpo, hourly, daily, restore_target, credits, special, source)
LEFT JOIN dbo.client c ON c.name = v.client;

-- Response and fix targets per severity (Sev 1-4 = priority 1-4)
INSERT INTO dbo.sla_policy (client_sla_id, priority, response_value, response_unit, response_note, fix_value, fix_unit, fix_note)
SELECT cs.client_sla_id, v.p, v.rv, v.ru, v.rn, v.fv, v.fu, v.fn
FROM (VALUES
    (NULL, 1, 2, N'bh', NULL, 24, N'h', N'Commercially reasonable efforts'),
    (NULL, 2, 4, N'bh', NULL, 2, N'bd', NULL),
    (NULL, 3, 8, N'bh', NULL, 10, N'bd', NULL),
    (NULL, 4, 2, N'bd', NULL, NULL, N'next', NULL),
    (N'NBCU', 1, 1, N'h', NULL, NULL, N'best', N'Continuous work, no fixed deadline'),
    (N'NBCU', 2, 4, N'h', NULL, NULL, N'best', N'Continuous work, no fixed deadline'),
    (N'NBCU', 3, 6, N'bh', NULL, NULL, N'prompt', N'During normal business hours'),
    (N'NBCU', 4, 8, N'bh', N'Business-hours condition', 2, N'bd', N'Promptly; investigate or design within 2 business days'),
    (N'AMC', 1, 2, N'bh', NULL, 24, N'h', N'Commercially reasonable efforts'),
    (N'AMC', 2, 4, N'bh', NULL, 2, N'bd', NULL),
    (N'AMC', 3, 8, N'bh', NULL, 10, N'bd', NULL),
    (N'AMC', 4, 2, N'bd', NULL, NULL, N'next', NULL),
    (N'Ole', 1, 2, N'bh', NULL, 24, N'h', N'Commercially reasonable efforts'),
    (N'Ole', 2, 4, N'bh', NULL, 2, N'bd', NULL),
    (N'Ole', 3, 8, N'bh', NULL, 10, N'bd', NULL),
    (N'Ole', 4, 2, N'bd', NULL, NULL, N'next', NULL),
    (N'NEON', 1, 2, N'bh', NULL, 24, N'h', N'Commercially reasonable efforts'),
    (N'NEON', 2, 4, N'bh', NULL, 2, N'bd', NULL),
    (N'NEON', 3, 8, N'bh', NULL, 10, N'bd', NULL),
    (N'NEON', 4, 2, N'bd', NULL, NULL, N'next', NULL),
    (N'Fox', 1, 2, N'bh', NULL, 24, N'h', N'Target'),
    (N'Fox', 2, 4, N'bh', NULL, 2, N'bd', NULL),
    (N'Fox', 3, 8, N'bh', NULL, 10, N'bd', NULL),
    (N'Fox', 4, 2, N'bd', NULL, NULL, N'next', NULL),
    (N'Paramount', 1, 2, N'bh', NULL, 24, N'h', N'Target'),
    (N'Paramount', 2, 4, N'bh', NULL, 2, N'bd', NULL),
    (N'Paramount', 3, 8, N'bh', NULL, 10, N'bd', NULL),
    (N'Paramount', 4, 2, N'bd', NULL, NULL, N'next', NULL)
) v(client, p, rv, ru, rn, fv, fu, fn)
LEFT JOIN dbo.client c ON c.name = v.client
JOIN dbo.client_sla cs ON (cs.client_id = c.client_id) OR (v.client IS NULL AND cs.client_id IS NULL);

-- Tasks. age = minutes since created; offsets are minutes after creation.
INSERT INTO dbo.task (task_key, title, task_type, source_system, priority, stage, client_id, product_id, project_id,
                      owner_person_id, queue_team_id, module_id, release_id, created_at, first_response_at, sla_paused_since, resolved_at, due_date, external_ref, notes)
SELECT v.task_key, v.title, v.task_type, v.source_system, v.priority, v.stage, c.client_id,
       (SELECT product_id FROM dbo.product WHERE name = N'Coral MSP'), pj.project_id, p.person_id, tm.team_id, md.module_id, rl.release_id,
       DATEADD(MINUTE, -v.age, @now),
       CASE WHEN v.fr IS NOT NULL THEN DATEADD(MINUTE, v.fr - v.age, @now) END,
       CASE WHEN v.paused IS NOT NULL THEN DATEADD(MINUTE, v.paused - v.age, @now) END,
       CASE WHEN v.stage = 'done' THEN DATEADD(MINUTE, -v.age * 4 / 10, @now) END,
       CASE WHEN v.due_days IS NOT NULL THEN CAST(DATEADD(DAY, v.due_days, @now) AS DATE) END,
       v.external_ref, v.notes
FROM (VALUES
    (N'SUP-2381', N'Users can''t sign in after SSO certificate rotation', N'incident', N'portal', 1, N'triage', N'Paramount', NULL, NULL, N'Support L2', N'Platform', NULL, 45, NULL, NULL, NULL, NULL, N'All Paramount admins locked out since the 9pm certificate rotation.'),
    (N'SUP-2358', N'Intermittent 502 errors on the AMC partner portal', N'incident', N'email', 1, N'in_dev', N'AMC', NULL, N'OH', N'Development', N'Operations', NULL, 300, 10, NULL, NULL, N'Jira DEV-4421', NULL),
    (N'SUP-2384', N'Asset ingest queue stalled for live sports feeds', N'incident', N'teams', 1, N'in_progress', N'Fox', NULL, N'AK', N'Support L2', N'Operations', NULL, 90, 15, NULL, NULL, NULL, NULL),
    (N'SUP-2386', N'Playback analytics delayed by about two hours', N'incident', N'email', 2, N'triage', N'NBCU', NULL, NULL, N'Support L2', N'Reporting', NULL, 20, NULL, NULL, NULL, NULL, NULL),
    (N'SUP-2376', N'Monthly invoice export totals are off by one cent', N'bug', N'email', 2, N'in_dev', N'NBCU', N'Coral MSP 4.12 release', N'MC', N'Development', N'Finance', N'4.12', 1500, 60, NULL, NULL, N'Jira DEV-4410', NULL),
    (N'SUP-2350', N'Scheduled report emails are being sent twice', N'bug', N'email', 2, N'in_progress', N'Fox', NULL, N'SO', N'Support L2', N'Reporting', NULL, 3100, 100, NULL, NULL, NULL, NULL),
    (N'SUP-2383', N'Thumbnail generation fails for 4K uploads', N'bug', N'portal', 2, N'queued', N'Netflix', N'Netflix onboarding', NULL, N'Development', N'TVOD', NULL, 190, NULL, NULL, NULL, NULL, NULL),
    (N'SUP-2372', N'Export to Excel drops rows past 65,000', N'bug', N'email', 2, N'in_dev', N'Netflix', NULL, N'DA', N'Development', N'Reporting', N'4.12', 2000, 120, NULL, NULL, N'Jira DEV-4417', NULL),
    (N'SUP-2361', N'Usage report double counts shared seats', N'bug', N'email', 2, N'ready_for_test', N'Paramount', N'Paramount reporting rollout', N'MC', N'Development', N'Finance', NULL, 2600, 90, 2000, NULL, N'Jira DEV-4409', NULL),
    (N'SUP-2379', N'Dashboard widgets show UTC instead of local time', N'bug', N'portal', 3, N'queued', N'AMC', NULL, N'HS', N'Support L1', N'Reporting', N'4.13', 1500, 200, NULL, NULL, NULL, NULL),
    (N'SUP-2387', N'Search ignores accented characters in titles', N'bug', N'portal', 3, N'triage', N'AMC', NULL, NULL, N'Support L1', N'TVOD', NULL, 400, NULL, NULL, NULL, NULL, NULL),
    (N'REQ-311', N'Set up 40 user accounts for the new production team', N'request', N'email', 3, N'triage', N'Netflix', N'Netflix onboarding', NULL, N'Support L1', N'Operations', NULL, 120, NULL, NULL, NULL, NULL, N'Spreadsheet of names attached to the original email.'),
    (N'REQ-309', N'Enable API access for a new integration partner', N'request', N'portal', 3, N'in_progress', N'Paramount', N'Paramount reporting rollout', N'HS', N'Support L1', N'Platform', NULL, 5600, 300, NULL, NULL, NULL, NULL),
    (N'REQ-305', N'Add NBCU''s new subsidiary as a tenant', N'request', N'teams', 3, N'queued', N'NBCU', NULL, N'SO', N'Support L2', N'International', NULL, 2900, 100, NULL, NULL, NULL, NULL),
    (N'REQ-312', N'Raise API rate limit for the nightly sync', N'request', N'email', 3, N'in_progress', N'Fox', NULL, N'AK', N'Support L2', N'Platform', NULL, 1400, 90, NULL, NULL, NULL, NULL),
    (N'SUP-2369', N'How do we export the audit log for a compliance review?', N'question', N'teams', 3, N'in_progress', N'AMC', NULL, N'JR', N'Support L1', N'Operations', NULL, 2900, 60, 2800, NULL, NULL, NULL),
    (N'SUP-2366', N'Which IP ranges should Paramount allowlist?', N'question', N'email', 4, N'in_progress', N'Paramount', NULL, N'JR', N'Support L1', N'Platform', NULL, 1000, 200, NULL, NULL, NULL, NULL),
    (N'SUP-2385', N'Can we schedule exports to an SFTP folder?', N'question', N'portal', 4, N'triage', N'Fox', NULL, NULL, N'Support L1', N'Operations', NULL, 30, NULL, NULL, NULL, NULL, NULL),
    (N'SUP-2370', N'Is there a sandbox environment for testing?', N'question', N'email', 3, N'in_progress', N'Netflix', N'Netflix onboarding', N'HS', N'Support L1', N'Platform', NULL, 3000, 120, NULL, NULL, NULL, NULL),
    (N'CR-047', N'Raise default session timeout from 30 to 60 minutes', N'change', N'jira', 3, N'ready_to_publish', N'NBCU', N'Coral MSP 4.12 release', N'LP', N'QA', N'Platform', N'4.12', 4000, NULL, NULL, 10, N'Jira DEV-4398', NULL),
    (N'CR-049', N'Switch Fox SSO to the new identity provider', N'change', N'jira', 2, N'in_dev', N'Fox', N'Fox SSO migration', N'DA', N'Development', N'Platform', N'4.13', 9000, NULL, NULL, 17, N'Jira DEV-4402', NULL),
    (N'CR-051', N'Rotate storage account keys for the EU region', N'change', N'ado', 2, N'in_progress', N'Coral Technology', NULL, N'PN', N'Platform', N'Platform', NULL, 6000, NULL, NULL, 0, N'Azure DevOps #8840', NULL),
    (N'CR-052', N'Add the Paramount logo to the client portal sign-in page', N'change', N'board', 3, N'queued', N'Paramount', N'Paramount reporting rollout', N'JR', N'Support L1', N'Operations', NULL, 2000, NULL, NULL, 5, NULL, NULL),
    (N'FR-118', N'Bulk user import from CSV', N'feature', N'portal', 3, N'triage', N'Coral Technology', N'Product backlog', NULL, N'Product', N'Operations', N'Backlog', 2900, NULL, NULL, NULL, NULL, NULL),
    (N'FR-121', N'Saved filters on the content dashboard', N'feature', N'teams', 4, N'queued', N'NBCU', N'Product backlog', N'RB', N'Product', N'Reporting', N'Backlog', 4500, NULL, NULL, NULL, NULL, NULL),
    (N'FR-124', N'Single sign-on for the mobile app', N'feature', N'email', 3, N'triage', N'Coral Technology', N'Product backlog', NULL, N'Product', N'Platform', N'5.0', 7200, NULL, NULL, NULL, NULL, NULL),
    (N'FR-125', N'Webhook notifications for task updates', N'feature', N'board', 3, N'triage', N'Coral Technology', N'Product backlog', N'RB', N'Product', N'Platform', N'4.13', 600, NULL, NULL, NULL, NULL, NULL),
    (N'INT-552', N'Upgrade staging database to SQL Server 2022', N'internal', N'ado', 2, N'in_progress', N'Coral Technology', N'Coral MSP 4.12 release', N'PN', N'Platform', N'Platform', N'4.12', 5000, NULL, NULL, 6, N'Azure DevOps #8812', NULL),
    (N'INT-560', N'Write release notes for Coral MSP 4.12', N'internal', N'board', 3, N'queued', N'Coral Technology', N'Coral MSP 4.12 release', N'RB', N'Product', N'Operations', N'4.12', 1400, NULL, NULL, 9, NULL, NULL),
    (N'INT-548', N'Load test the new reporting API', N'internal', N'ado', 3, N'in_progress', N'Coral Technology', N'Paramount reporting rollout', N'LP', N'QA', N'Reporting', NULL, 8000, NULL, NULL, 13, N'Azure DevOps #8790', NULL),
    (N'INT-561', N'Publish the November on-call rota', N'internal', N'board', 3, N'in_progress', N'Coral Technology', NULL, N'SO', N'Support L2', N'Operations', NULL, 2500, NULL, NULL, 3, NULL, NULL),
    (N'INT-562', N'Remove stale feature flags', N'internal', N'board', 4, N'queued', N'Coral Technology', NULL, N'OH', N'Development', N'Platform', N'Backlog', 9000, NULL, NULL, NULL, NULL, NULL),
    (N'SUP-2340', N'Password reset emails landing in spam', N'bug', N'email', 2, N'done', N'NBCU', NULL, N'MC', N'Development', N'Platform', NULL, 6000, 60, NULL, NULL, N'Jira DEV-4390', NULL),
    (N'REQ-300', N'Provision a staging tenant for Netflix', N'request', N'portal', 3, N'done', N'Netflix', N'Netflix onboarding', N'SO', N'Support L2', N'Operations', NULL, 7000, 120, NULL, NULL, NULL, NULL),
    (N'SUP-2345', N'Where is the data retention policy documented?', N'question', N'teams', 4, N'done', N'Fox', NULL, N'HS', N'Support L1', N'Operations', NULL, 5000, 90, NULL, NULL, NULL, NULL),
    (N'CR-044', N'Require MFA for admin roles', N'change', N'jira', 2, N'done', N'AMC', NULL, N'DA', N'Development', N'Platform', NULL, 12000, NULL, NULL, NULL, N'Jira DEV-4380', NULL),
    (N'SUP-2388', N'TVOD purchases failing on the Canadian storefront', N'incident', N'portal', 1, N'triage', N'Netflix', NULL, NULL, N'Support L2', N'TVOD', NULL, 10, NULL, NULL, NULL, NULL, NULL),
    (N'SUP-2389', N'Finance export is missing the VAT column for UK entities', N'bug', N'email', 2, N'triage', N'AMC', NULL, NULL, N'Support L1', N'Finance', NULL, 60, NULL, NULL, NULL, NULL, NULL),
    (N'SUP-2331', N'Rights window dates shift by one day for APAC territories', N'bug', N'portal', 3, N'queued', N'Fox', NULL, NULL, N'Development', N'International', N'4.13', 9000, 60, NULL, NULL, NULL, NULL),
    (N'SUP-2335', N'Royalty statement totals round differently from invoices', N'bug', N'email', 4, N'queued', N'Paramount', NULL, NULL, N'Support L2', N'Finance', N'Backlog', 15000, 120, NULL, NULL, NULL, NULL),
    (N'FR-126', N'Multi-currency invoices for international clients', N'feature', N'email', 3, N'triage', N'Coral Technology', N'Product backlog', NULL, N'Product', N'Finance', N'Backlog', 20000, NULL, NULL, NULL, NULL, NULL),
    (N'FR-127', N'TVOD price tiers by territory', N'feature', N'teams', 4, N'queued', N'NBCU', N'Product backlog', N'RB', N'Product', N'TVOD', N'Backlog', 12000, NULL, NULL, NULL, NULL, NULL),
    (N'INT-563', N'Document the TVOD settlement process', N'internal', N'board', 4, N'triage', N'Coral Technology', NULL, NULL, N'Product', N'TVOD', N'Backlog', 8000, NULL, NULL, NULL, NULL, NULL),
    (N'SUP-2390', N'Rights import job stalls on large catalogs', N'incident', N'portal', 2, N'triage', N'Ole', NULL, NULL, N'Support L2', N'International', NULL, 90, NULL, NULL, NULL, NULL, NULL),
    (N'SUP-2391', N'How do we add a new territory to the price list?', N'question', N'email', 3, N'queued', N'NEON', NULL, N'HS', N'Support L1', N'TVOD', NULL, 300, 45, NULL, NULL, NULL, NULL)
) v(task_key, title, task_type, source_system, priority, stage, client, project, owner_code, queue, module, rel, age, fr, paused, due_days, external_ref, notes)
JOIN dbo.client c ON c.name = v.client
LEFT JOIN dbo.project pj ON pj.name = v.project
LEFT JOIN dbo.person p ON p.person_code = v.owner_code
LEFT JOIN dbo.team tm ON tm.name = v.queue
LEFT JOIN dbo.product_module md ON md.name = v.module
LEFT JOIN dbo.product_release rl ON rl.name = v.rel;

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
    (N'CR-044', N'Security'),
    (N'SUP-2388', N'Payments'),
    (N'SUP-2389', N'Exports'),
    (N'SUP-2331', N'Rights'),
    (N'SUP-2335', N'Royalties'),
    (N'FR-126', N'Requested by 2 clients'),
    (N'FR-127', N'Pricing'),
    (N'INT-563', N'Docs'),
    (N'SUP-2390', N'Imports'),
    (N'SUP-2391', N'Pricing')
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
    (N'CR-047', 10800, N'Passed testing, waiting for the 4.12 release'),
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
    (N'CR-044', 10800, N'Released in 4.11'),
    (N'SUP-2388', 600, N'Created from support portal'),
    (N'SUP-2389', 3600, N'Created from email'),
    (N'SUP-2331', 540000, N'Created from support portal'),
    (N'SUP-2331', 536400, N'First response sent'),
    (N'SUP-2331', 10800, N'Accepted for 4.13, needs an owner'),
    (N'SUP-2335', 900000, N'Created from email'),
    (N'SUP-2335', 892800, N'First response sent'),
    (N'SUP-2335', 10800, N'Parked in the backlog'),
    (N'FR-126', 1200000, N'Created from email'),
    (N'FR-126', 10800, N'Asked for by Fox and NBCU'),
    (N'FR-127', 720000, N'Created from Teams'),
    (N'FR-127', 718200, N'Assigned to Rosa Bianchi'),
    (N'INT-563', 480000, N'Created from the board'),
    (N'SUP-2390', 5400, N'Created from support portal'),
    (N'SUP-2391', 18000, N'Created from email'),
    (N'SUP-2391', 16200, N'Assigned to Hana Sato'),
    (N'SUP-2391', 15300, N'First response sent'),
    (N'SUP-2391', 3600, N'Sent the how-to, waiting to confirm')
) v(task_key, secs_ago, msg) JOIN dbo.task t ON t.task_key = v.task_key;
