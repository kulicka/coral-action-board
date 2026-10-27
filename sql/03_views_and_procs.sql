-- Coral MSP action board: views and procedures (SQL Server)
-- Same SLA rules as the prototype: support types (incident, bug, request, question) for
-- outside clients run a first-response clock, then a resolution clock, both measured from
-- creation and minus time spent waiting on the client. Everything else uses its due date.
-- Wall-clock minutes for now; a business-hours calendar comes later.

CREATE OR ALTER VIEW dbo.v_task_card AS
WITH base AS (
    SELECT  t.*,
            c.name AS client_name, c.is_internal, pj.name AS project_name, pr.name AS product_name,
            p.person_code AS owner_code, p.display_name AS owner_name, tm.name AS queue_name,
            sp.first_response_mins, sp.resolution_mins, sp.is_override,
            DATEDIFF(MINUTE, t.created_at, SYSUTCDATETIME())
              - t.sla_paused_mins
              - ISNULL(DATEDIFF(MINUTE, t.sla_paused_since, SYSUTCDATETIME()), 0) AS sla_elapsed_mins,
            CASE WHEN t.task_type IN ('incident','bug','request','question') AND c.is_internal = 0
                 THEN 1 ELSE 0 END AS has_support_sla
    FROM dbo.task t
    JOIN dbo.client  c  ON c.client_id = t.client_id
    LEFT JOIN dbo.project pj ON pj.project_id = t.project_id
    LEFT JOIN dbo.product pr ON pr.product_id = t.product_id
    LEFT JOIN dbo.person  p  ON p.person_id  = t.owner_person_id
    JOIN dbo.team    tm ON tm.team_id   = t.queue_team_id
    OUTER APPLY (
        SELECT TOP (1) x.first_response_mins, x.resolution_mins,
               CASE WHEN x.client_id IS NULL THEN 0 ELSE 1 END AS is_override
        FROM dbo.sla_policy x
        WHERE x.priority = t.priority
          AND (x.client_id = t.client_id OR (x.client_id IS NULL AND x.support_tier = c.support_tier))
        ORDER BY CASE WHEN x.client_id IS NULL THEN 1 ELSE 0 END
    ) sp
), clocked AS (
    SELECT b.*,
           CASE WHEN b.has_support_sla = 1 AND b.first_response_at IS NULL THEN 'First response'
                WHEN b.has_support_sla = 1 THEN 'Resolution'
                WHEN b.due_date IS NOT NULL THEN 'Due date' END AS sla_kind,
           CASE WHEN b.has_support_sla = 1 AND b.first_response_at IS NULL THEN b.first_response_mins
                WHEN b.has_support_sla = 1 THEN b.resolution_mins END AS sla_target_mins,
           DATEDIFF(MINUTE, SYSUTCDATETIME(), DATEADD(SECOND, 86399, CAST(b.due_date AS DATETIME2(0)))) AS due_left_mins
    FROM base b
)
SELECT  task_id, task_key, title, task_type, source_system, priority, stage,
        client_name, product_name, project_name, owner_code, owner_name, queue_name,
        CASE WHEN owner_person_id IS NULL THEN 1 ELSE 0 END AS is_unassigned,
        external_ref, due_date, created_at, first_response_at, resolved_at, updated_at,
        sla_kind, sla_target_mins, sla_elapsed_mins,
        CASE WHEN sla_target_mins IS NOT NULL THEN sla_target_mins - sla_elapsed_mins ELSE due_left_mins END AS sla_left_mins,
        CASE
            WHEN stage = 'done'                                   THEN 'none'
            WHEN sla_target_mins IS NOT NULL AND sla_paused_since IS NOT NULL THEN 'paused'
            WHEN sla_target_mins IS NOT NULL AND sla_elapsed_mins >= sla_target_mins        THEN 'breach'
            WHEN sla_target_mins IS NOT NULL AND sla_elapsed_mins >= sla_target_mins * 0.75 THEN 'risk'
            WHEN sla_target_mins IS NOT NULL                      THEN 'ok'
            WHEN due_date IS NOT NULL AND due_left_mins < 0       THEN 'breach'
            WHEN due_date IS NOT NULL AND due_left_mins < 1440    THEN 'risk'
            WHEN due_date IS NOT NULL                             THEN 'ok'
            ELSE 'none'
        END AS sla_state,
        CASE WHEN is_override = 1 THEN client_name + N' contract' ELSE N'standard' END AS sla_terms
FROM clocked;
GO

-- Who's on what: open load per person, with the urgent counts leadership asks about
CREATE OR ALTER VIEW dbo.v_workload AS
SELECT  p.person_code, p.display_name, tm.name AS team_name,
        COUNT(v.task_id)                                         AS open_tasks,
        SUM(CASE WHEN v.priority = 1 THEN 1 ELSE 0 END)          AS p1_tasks,
        SUM(CASE WHEN v.sla_state = 'breach' THEN 1 ELSE 0 END)  AS breached,
        SUM(CASE WHEN v.sla_state = 'risk' THEN 1 ELSE 0 END)    AS at_risk
FROM dbo.person p
JOIN dbo.team tm ON tm.team_id = p.team_id
LEFT JOIN dbo.v_task_card v ON v.owner_code = p.person_code AND v.stage <> 'done'
WHERE p.is_active = 1
GROUP BY p.person_code, p.display_name, tm.name;
GO

-- The "Needs attention" view: unassigned, at risk or breached
CREATE OR ALTER VIEW dbo.v_needs_attention AS
SELECT * FROM dbo.v_task_card
WHERE stage <> 'done' AND (is_unassigned = 1 OR sla_state IN ('risk','breach'));
GO

-- ---------- procedures behind the board's buttons ----------

CREATE OR ALTER PROCEDURE dbo.usp_log_activity @task_id INT, @actor_code VARCHAR(10), @message NVARCHAR(400)
AS
BEGIN
    SET NOCOUNT ON;
    INSERT dbo.task_activity (task_id, actor_person_id, message)
    SELECT @task_id, (SELECT person_id FROM dbo.person WHERE person_code = @actor_code), @message;
    UPDATE dbo.task SET updated_at = SYSUTCDATETIME() WHERE task_id = @task_id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_create_task
    @task_type VARCHAR(20), @title NVARCHAR(300), @client NVARCHAR(200), @priority TINYINT,
    @project NVARCHAR(200) = NULL, @owner_code VARCHAR(10) = NULL, @queue NVARCHAR(100),
    @due_date DATE = NULL, @external_ref NVARCHAR(80) = NULL, @notes NVARCHAR(4000) = NULL,
    @actor_code VARCHAR(10), @task_key VARCHAR(20) OUTPUT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @prefix VARCHAR(5) = CASE @task_type WHEN 'request' THEN 'REQ' WHEN 'feature' THEN 'FR'
                                  WHEN 'internal' THEN 'INT' WHEN 'change' THEN 'CR' ELSE 'SUP' END;
    BEGIN TRAN;
        DECLARE @next INT = 1 + ISNULL((SELECT MAX(CAST(SUBSTRING(task_key, LEN(@prefix) + 2, 10) AS INT))
                                        FROM dbo.task WITH (UPDLOCK, HOLDLOCK)
                                        WHERE task_key LIKE @prefix + '-%'), 100);
        SET @task_key = @prefix + '-' + CAST(@next AS VARCHAR(10));
        DECLARE @owner_id INT = (SELECT person_id FROM dbo.person WHERE person_code = @owner_code);
        INSERT dbo.task (task_key, title, task_type, source_system, priority, client_id, product_id, project_id,
                         owner_person_id, queue_team_id, due_date, external_ref, notes)
        SELECT @task_key, @title, @task_type, 'board', @priority, c.client_id,
               (SELECT product_id FROM dbo.product WHERE name = N'Coral MSP'),
               (SELECT project_id FROM dbo.project WHERE name = @project),
               @owner_id,
               COALESCE((SELECT team_id FROM dbo.person WHERE person_id = @owner_id), q.team_id),
               @due_date, @external_ref, @notes
        FROM dbo.client c CROSS JOIN dbo.team q
        WHERE c.name = @client AND q.name = @queue;
        IF @@ROWCOUNT = 0 THROW 50001, 'Unknown client or queue.', 1;
        DECLARE @id INT = SCOPE_IDENTITY();
        DECLARE @msg NVARCHAR(400) = N'Created on the board by ' + ISNULL((SELECT display_name FROM dbo.person WHERE person_code = @actor_code), N'someone');
        EXEC dbo.usp_log_activity @id, @actor_code, @msg;
    COMMIT;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_assign_task @task_key VARCHAR(20), @owner_code VARCHAR(10) = NULL, @actor_code VARCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @id INT = (SELECT task_id FROM dbo.task WHERE task_key = @task_key);
    IF @id IS NULL THROW 50002, 'Task not found.', 1;
    DECLARE @owner INT = (SELECT person_id FROM dbo.person WHERE person_code = @owner_code);
    -- Unassigning returns the task to the previous owner's team queue
    UPDATE t SET owner_person_id = @owner,
                 queue_team_id = COALESCE((SELECT team_id FROM dbo.person WHERE person_id = @owner),
                                          (SELECT team_id FROM dbo.person WHERE person_id = t.owner_person_id),
                                          t.queue_team_id)
    FROM dbo.task t WHERE t.task_id = @id;
    DECLARE @msg NVARCHAR(400) = CASE WHEN @owner IS NULL THEN N'Returned to the queue'
        ELSE N'Assigned to ' + (SELECT display_name FROM dbo.person WHERE person_id = @owner) END;
    EXEC dbo.usp_log_activity @id, @actor_code, @msg;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_set_stage @task_key VARCHAR(20), @stage VARCHAR(20), @actor_code VARCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @id INT = (SELECT task_id FROM dbo.task WHERE task_key = @task_key);
    IF @id IS NULL THROW 50002, 'Task not found.', 1;
    UPDATE dbo.task SET stage = @stage,
                        resolved_at = CASE WHEN @stage = 'done' THEN SYSUTCDATETIME() END
    WHERE task_id = @id;
    DECLARE @msg NVARCHAR(400) = N'Moved to ' + @stage;
    EXEC dbo.usp_log_activity @id, @actor_code, @msg;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_log_first_response @task_key VARCHAR(20), @actor_code VARCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @id INT = (SELECT task_id FROM dbo.task WHERE task_key = @task_key);
    UPDATE dbo.task SET first_response_at = SYSUTCDATETIME() WHERE task_id = @id AND first_response_at IS NULL;
    IF @@ROWCOUNT = 1 EXEC dbo.usp_log_activity @id, @actor_code, N'First response sent';
END;
GO

-- @waiting = 1 pauses the SLA clock (waiting on client); 0 resumes it and banks the paused time
CREATE OR ALTER PROCEDURE dbo.usp_set_waiting_on_client @task_key VARCHAR(20), @waiting BIT, @actor_code VARCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @id INT = (SELECT task_id FROM dbo.task WHERE task_key = @task_key);
    IF @waiting = 1
        UPDATE dbo.task SET sla_paused_since = SYSUTCDATETIME() WHERE task_id = @id AND sla_paused_since IS NULL;
    ELSE
        UPDATE dbo.task SET sla_paused_mins = sla_paused_mins + DATEDIFF(MINUTE, sla_paused_since, SYSUTCDATETIME()),
                            sla_paused_since = NULL
        WHERE task_id = @id AND sla_paused_since IS NOT NULL;
    IF @@ROWCOUNT = 1
    BEGIN
        DECLARE @msg NVARCHAR(400) = CASE WHEN @waiting = 1 THEN N'Waiting on client, SLA clock paused'
                                          ELSE N'Client replied, SLA clock running again' END;
        EXEC dbo.usp_log_activity @id, @actor_code, @msg;
    END;
END;
GO

-- Quick checks after loading the test data:
--   SELECT * FROM dbo.v_needs_attention ORDER BY sla_state, priority;
--   SELECT * FROM dbo.v_workload ORDER BY open_tasks DESC;
--   DECLARE @k VARCHAR(20); EXEC dbo.usp_create_task 'bug', N'Test task', N'Fox', 3, NULL, NULL, N'Support L1', NULL, NULL, NULL, 'JR', @k OUTPUT; SELECT @k;
