-- Coral MSP action board: schema (SQL Server 2019+ / Azure SQL)
-- Run order: 01_schema.sql, 02_test_data.sql, 03_views_and_procs.sql
-- Mirrors the prototype's data model. One client per task (multi-client work goes
-- under 'Coral Technology'), exactly one accountable owner, SLA terms per client with a
-- Coral standard for everyone else, and a business-hours calendar for the SLA clocks.

IF SCHEMA_ID('dbo') IS NULL EXEC('CREATE SCHEMA dbo');
GO

CREATE TABLE dbo.client (
    client_id     INT IDENTITY(1,1) CONSTRAINT pk_client PRIMARY KEY,
    name          NVARCHAR(200) NOT NULL CONSTRAINT uq_client_name UNIQUE,
    is_internal   BIT           NOT NULL CONSTRAINT df_client_internal DEFAULT (0)  -- 1 = Coral Technology
);

CREATE TABLE dbo.product (
    product_id    INT IDENTITY(1,1) CONSTRAINT pk_product PRIMARY KEY,
    name          NVARCHAR(200) NOT NULL CONSTRAINT uq_product_name UNIQUE
);

-- Product areas shown on the card: Operations, Finance, TVOD, International ...
CREATE TABLE dbo.product_module (
    module_id     INT IDENTITY(1,1) CONSTRAINT pk_product_module PRIMARY KEY,
    product_id    INT NOT NULL CONSTRAINT fk_module_product REFERENCES dbo.product(product_id),
    name          NVARCHAR(100) NOT NULL,
    CONSTRAINT uq_module_name UNIQUE (product_id, name)
);

-- Releases work can be scheduled into. 'Backlog' is a row with no ship date.
CREATE TABLE dbo.product_release (
    release_id    INT IDENTITY(1,1) CONSTRAINT pk_product_release PRIMARY KEY,
    name          NVARCHAR(40) NOT NULL CONSTRAINT uq_release_name UNIQUE,
    ship_date     DATE NULL
);

CREATE TABLE dbo.project (
    project_id    INT IDENTITY(1,1) CONSTRAINT pk_project PRIMARY KEY,
    name          NVARCHAR(200) NOT NULL CONSTRAINT uq_project_name UNIQUE,
    client_id     INT NULL CONSTRAINT fk_project_client REFERENCES dbo.client(client_id),
    product_id    INT NULL CONSTRAINT fk_project_product REFERENCES dbo.product(product_id)
);

CREATE TABLE dbo.team (
    team_id       INT IDENTITY(1,1) CONSTRAINT pk_team PRIMARY KEY,
    name          NVARCHAR(100) NOT NULL CONSTRAINT uq_team_name UNIQUE
);

CREATE TABLE dbo.person (
    person_id     INT IDENTITY(1,1) CONSTRAINT pk_person PRIMARY KEY,
    person_code   VARCHAR(10)   NOT NULL CONSTRAINT uq_person_code UNIQUE,   -- initials shown on cards
    display_name  NVARCHAR(200) NOT NULL,
    email         NVARCHAR(320) NOT NULL CONSTRAINT uq_person_email UNIQUE,
    team_id       INT NOT NULL CONSTRAINT fk_person_team REFERENCES dbo.team(team_id),
    is_active     BIT NOT NULL CONSTRAINT df_person_active DEFAULT (1)
);

-- Business calendar for SLA clocks counted in business hours or days
CREATE TABLE dbo.business_calendar (
    calendar_id    INT IDENTITY(1,1) CONSTRAINT pk_business_calendar PRIMARY KEY,
    name           NVARCHAR(100) NOT NULL CONSTRAINT uq_calendar_name UNIQUE,
    time_zone      VARCHAR(64)   NOT NULL,      -- Windows zone name for AT TIME ZONE, e.g. 'Eastern Standard Time'
    day_start      TIME(0)       NOT NULL,      -- local time
    day_end        TIME(0)       NOT NULL,
    open_weekdays  VARCHAR(7)    NOT NULL,      -- 1 = Monday ... 7 = Sunday, e.g. '12345'
    CONSTRAINT ck_calendar_hours CHECK (day_end > day_start)
);

CREATE TABLE dbo.business_holiday (
    calendar_id    INT NOT NULL CONSTRAINT fk_holiday_calendar REFERENCES dbo.business_calendar(calendar_id),
    holiday_date   DATE NOT NULL,
    name           NVARCHAR(100) NOT NULL,
    CONSTRAINT pk_business_holiday PRIMARY KEY (calendar_id, holiday_date)
);

-- Contract SLA terms per client. The one row with client_id NULL is the Coral standard,
-- used by every client without its own row.
CREATE TABLE dbo.client_sla (
    client_sla_id     INT IDENTITY(1,1) CONSTRAINT pk_client_sla PRIMARY KEY,
    client_id         INT NULL CONSTRAINT fk_client_sla_client REFERENCES dbo.client(client_id),
    calendar_id       INT NOT NULL CONSTRAINT fk_client_sla_calendar REFERENCES dbo.business_calendar(calendar_id),
    customer_name     NVARCHAR(200)  NULL,      -- name on the contract, e.g. NBCUniversal
    deployment        VARCHAR(20)    NULL CONSTRAINT ck_client_sla_deploy CHECK (deployment IN ('coral_hosted','customer_hosted')),
    terms_basis       NVARCHAR(400)  NULL,
    verification      VARCHAR(20)    NOT NULL CONSTRAINT ck_client_sla_verif CHECK (verification IN ('contract','assumed','unconfirmed','standard')),
    monthly_uptime    NVARCHAR(40)   NULL,
    support_hours     NVARCHAR(200)  NULL,
    after_hours       NVARCHAR(400)  NULL,
    rto               NVARCHAR(100)  NULL,
    rpo               NVARCHAR(100)  NULL,
    hourly_backups    NVARCHAR(200)  NULL,
    daily_backups     NVARCHAR(200)  NULL,
    restore_target    NVARCHAR(100)  NULL,
    service_credits   NVARCHAR(400)  NULL,
    special_terms     NVARCHAR(2000) NULL,
    source_documents  NVARCHAR(1000) NULL,
    updated_at        DATETIME2(0)   NOT NULL CONSTRAINT df_client_sla_updated DEFAULT (SYSUTCDATETIME())
);
CREATE UNIQUE INDEX ux_client_sla_client   ON dbo.client_sla (client_id)    WHERE client_id IS NOT NULL;
CREATE UNIQUE INDEX ux_client_sla_standard ON dbo.client_sla (verification) WHERE client_id IS NULL;

-- Response and fix targets per severity (Sev 1-4 = task priority 1-4).
-- Units: bh business hours, bd business days, h hours around the clock, d calendar days.
-- A fix can also be best (best efforts), prompt or next (next available update): no clock.
CREATE TABLE dbo.sla_policy (
    client_sla_id   INT NOT NULL CONSTRAINT fk_sla_terms REFERENCES dbo.client_sla(client_sla_id),
    priority        TINYINT NOT NULL CONSTRAINT ck_sla_priority CHECK (priority BETWEEN 1 AND 4),
    response_value  DECIMAL(6,1) NOT NULL CONSTRAINT ck_sla_resp_value CHECK (response_value > 0),
    response_unit   VARCHAR(6)   NOT NULL CONSTRAINT ck_sla_resp_unit CHECK (response_unit IN ('bh','bd','h','d')),
    response_note   NVARCHAR(200) NULL,
    fix_value       DECIMAL(6,1) NULL,
    fix_unit        VARCHAR(6)   NOT NULL CONSTRAINT ck_sla_fix_unit CHECK (fix_unit IN ('bh','bd','h','d','best','prompt','next')),
    fix_note        NVARCHAR(200) NULL,
    CONSTRAINT pk_sla_policy PRIMARY KEY (client_sla_id, priority),
    CONSTRAINT ck_sla_fix_value CHECK ((fix_unit IN ('best','prompt','next') AND fix_value IS NULL) OR fix_value > 0)
);

CREATE TABLE dbo.task (
    task_id            INT IDENTITY(1,1) CONSTRAINT pk_task PRIMARY KEY,
    task_key           VARCHAR(20)   NOT NULL CONSTRAINT uq_task_key UNIQUE,   -- SUP-2381, REQ-311, CR-047 ...
    title              NVARCHAR(300) NOT NULL,
    task_type          VARCHAR(20)   NOT NULL CONSTRAINT ck_task_type CHECK (task_type IN
                       ('incident','bug','feature','request','question','internal','change')),
    source_system      VARCHAR(20)   NOT NULL CONSTRAINT ck_task_source CHECK (source_system IN
                       ('portal','email','teams','jira','ado','board')),
    priority           TINYINT       NOT NULL CONSTRAINT ck_task_priority CHECK (priority BETWEEN 1 AND 4),
    stage              VARCHAR(20)   NOT NULL CONSTRAINT df_task_stage DEFAULT ('triage')
                       CONSTRAINT ck_task_stage CHECK (stage IN ('triage','queued','in_progress','in_dev','ready_for_test','ready_to_publish','done')),
    client_id          INT NOT NULL CONSTRAINT fk_task_client  REFERENCES dbo.client(client_id),
    product_id         INT NULL     CONSTRAINT fk_task_product REFERENCES dbo.product(product_id),
    project_id         INT NULL     CONSTRAINT fk_task_project REFERENCES dbo.project(project_id),
    owner_person_id    INT NULL     CONSTRAINT fk_task_owner   REFERENCES dbo.person(person_id),  -- NULL = unassigned
    queue_team_id      INT NOT NULL CONSTRAINT fk_task_queue   REFERENCES dbo.team(team_id),      -- queue it waits in
    module_id          INT NULL     CONSTRAINT fk_task_module  REFERENCES dbo.product_module(module_id),
    release_id         INT NULL     CONSTRAINT fk_task_release REFERENCES dbo.product_release(release_id), -- scheduled release or Backlog
    created_at         DATETIME2(0) NOT NULL CONSTRAINT df_task_created DEFAULT (SYSUTCDATETIME()),
    first_response_at  DATETIME2(0) NULL,
    sla_paused_since   DATETIME2(0) NULL,          -- set while waiting on the client
    sla_paused_mins    INT NOT NULL CONSTRAINT df_task_paused DEFAULT (0),  -- total paused time so far
    sla_paused_business_mins INT NOT NULL CONSTRAINT df_task_paused_biz DEFAULT (0),  -- the same, counted in business minutes
    resolved_at        DATETIME2(0) NULL,
    due_date           DATE NULL,
    external_ref       NVARCHAR(80) NULL,          -- 'Jira DEV-4410', 'Azure DevOps #8812'
    notes              NVARCHAR(4000) NULL,
    updated_at         DATETIME2(0) NOT NULL CONSTRAINT df_task_updated DEFAULT (SYSUTCDATETIME())
);
CREATE INDEX ix_task_open_stage ON dbo.task (stage, priority) INCLUDE (owner_person_id, client_id) WHERE stage <> 'done';
CREATE INDEX ix_task_owner      ON dbo.task (owner_person_id) WHERE stage <> 'done';

CREATE TABLE dbo.task_tag (
    task_id  INT NOT NULL CONSTRAINT fk_tag_task REFERENCES dbo.task(task_id) ON DELETE CASCADE,
    tag      NVARCHAR(60) NOT NULL,
    CONSTRAINT pk_task_tag PRIMARY KEY (task_id, tag)
);

-- History shown on the card ("Assigned to Maya Chen by Jon Ruiz · 5m ago")
CREATE TABLE dbo.task_activity (
    activity_id  BIGINT IDENTITY(1,1) CONSTRAINT pk_task_activity PRIMARY KEY,
    task_id      INT NOT NULL CONSTRAINT fk_activity_task REFERENCES dbo.task(task_id) ON DELETE CASCADE,
    occurred_at  DATETIME2(0) NOT NULL CONSTRAINT df_activity_at DEFAULT (SYSUTCDATETIME()),
    actor_person_id INT NULL CONSTRAINT fk_activity_actor REFERENCES dbo.person(person_id),
    message      NVARCHAR(400) NOT NULL
);
CREATE INDEX ix_activity_task ON dbo.task_activity (task_id, occurred_at DESC);

-- Saved views shared by everyone (filters stored as JSON, as the prototype does)
CREATE TABLE dbo.saved_view (
    saved_view_id  INT IDENTITY(1,1) CONSTRAINT pk_saved_view PRIMARY KEY,
    name           NVARCHAR(40) NOT NULL,
    group_by       VARCHAR(20)  NOT NULL,
    layout         VARCHAR(10)  NOT NULL CONSTRAINT ck_view_layout CHECK (layout IN ('detail','short','ledger')),
    sort_by        VARCHAR(20)  NOT NULL,
    filters_json   NVARCHAR(MAX) NULL CONSTRAINT ck_view_filters CHECK (filters_json IS NULL OR ISJSON(filters_json) = 1),
    created_by     INT NULL CONSTRAINT fk_view_person REFERENCES dbo.person(person_id),
    created_at     DATETIME2(0) NOT NULL CONSTRAINT df_view_created DEFAULT (SYSUTCDATETIME())
);

-- LATER: time tracking (timer starts when someone takes a task, Stop posts to the time tracker)
-- CREATE TABLE dbo.time_entry (...);
GO
