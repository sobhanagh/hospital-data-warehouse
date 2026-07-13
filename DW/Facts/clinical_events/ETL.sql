CREATE OR ALTER PROCEDURE dbo.Load_Fact_Lab_Event
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @LastProcessedID INT = 0;
    DECLARE @NewLastProcessedID INT;
    DECLARE @InsertedRows INT = 0;
    DECLARE @ErrorMessage NVARCHAR(MAX);


    BEGIN TRY

        --------------------------------------------------
        -- Ensure control record exists
        --------------------------------------------------
        IF NOT EXISTS (
            SELECT 1 
            FROM dbo.ETL_Control 
            WHERE Table_Name = 'LAB_EVENTS'
        )
        BEGIN
            INSERT INTO dbo.ETL_Control
            (
                Table_Name,
                Last_Processed_ID,
                Last_Run_Status
            )
            VALUES
            (
                'LAB_EVENTS',
                0,
                'INITIAL'
            );
        END


        --------------------------------------------------
        -- Get last processed ID
        --------------------------------------------------
        SELECT @LastProcessedID = Last_Processed_ID
        FROM dbo.ETL_Control
        WHERE Table_Name = 'LAB_EVENTS';


        --------------------------------------------------
        -- Load Fact
        --------------------------------------------------
        INSERT INTO dbo.Fact_Lab_Event
        (
            Date_SK,
            Patient_SK,
            LabTest_SK,
            Admission_ID,
            Value_Num,
            Value_Text,
            Value_Unit,
            Flag
        )
        SELECT
            d.Date_SK,
            p.Patient_SK,
            l.LabTest_Key,
            s.ADMISSION_ID,
            s.VALUE_NUM,
            s.VALUE,
            s.VALUE_UOM,
            s.FLAG
        FROM DW_Staging.Stage.LAB_EVENTS s

        INNER JOIN dbo.Dim_Date d
            ON CAST(s.CHART_TIME AS DATE) = CAST(d.FullDate AS DATE)

        INNER JOIN dbo.Dim_Patient p
            ON s.PATIENT_ID = p.Patient_ID

        INNER JOIN dbo.Dim_Lab_Items l
            ON s.ITEM_ID = l.Item_ID

        WHERE s.ROW_ID > @LastProcessedID;


        --------------------------------------------------
        -- Capture rowcount IMMEDIATELY
        --------------------------------------------------
        SET @InsertedRows = @@ROWCOUNT;


        --------------------------------------------------
        -- Get new max ROW_ID
        --------------------------------------------------
        SELECT @NewLastProcessedID = MAX(ROW_ID)
        FROM DW_Staging.Stage.LAB_EVENTS
        WHERE ROW_ID > @LastProcessedID;


        --------------------------------------------------
        -- Update ETL_Control (SUCCESS)
        --------------------------------------------------
        UPDATE dbo.ETL_Control
        SET 
            Last_Processed_ID = ISNULL(@NewLastProcessedID, Last_Processed_ID),
            Last_Run_Status = 'SUCCESS',
            Last_Run_Timestamp = GETDATE(),
            Error_Message = NULL
        WHERE Table_Name = 'LAB_EVENTS';


        --------------------------------------------------
        -- Log SUCCESS
        --------------------------------------------------
        EXEC dbo.sp_Insert_ETL_Log
            @Procedure_Name = 'Load_Fact_Lab_Event',
            @Action_Name = 'INSERT',
            @Object_Name = 'Fact_Lab_Event',
            @Affected_Row_Number = @InsertedRows;


    END TRY


    BEGIN CATCH

        --------------------------------------------------
        -- Capture error FIRST
        --------------------------------------------------
        SET @ErrorMessage = ERROR_MESSAGE();


        --------------------------------------------------
        -- Update ETL_Control (FAILED)
        --------------------------------------------------
        UPDATE dbo.ETL_Control
        SET 
            Last_Run_Status = 'FAILED',
            Last_Run_Timestamp = GETDATE(),
            Error_Message = @ErrorMessage
        WHERE Table_Name = 'LAB_EVENTS';


        --------------------------------------------------
        -- Log FAIL 
        --------------------------------------------------
        EXEC dbo.sp_Insert_ETL_Log
            @Procedure_Name = 'Load_Fact_Lab_Event',
            @Action_Name = 'INSERT',
            @Object_Name = 'Fact_Lab_Event',
            @Affected_Row_Number = 0;

        THROW;

    END CATCH

END;
GO








CREATE TABLE dbo.Tmp_InputData
(
    SUBJECT_ID INT,
    ICU_STAY_ID INT,
    SnapshotDate DATE,
    CATEGORY NVARCHAR(100),
    Amount FLOAT
);

CREATE TABLE dbo.Tmp_OutputData
(
    SUBJECT_ID INT,
    ICU_STAY_ID INT,
    SnapshotDate DATE,
    CATEGORY NVARCHAR(100),
    Amount FLOAT
);

CREATE TABLE dbo.Tmp_Aggregated
(
    SUBJECT_ID INT,
    ICU_STAY_ID INT,
    SnapshotDate DATE,

    Fluid_Input_ml FLOAT,
    Blood_Input_ml FLOAT,
    Urine_Output_ml FLOAT,
    Drain_Output_ml FLOAT
);



CREATE OR ALTER PROCEDURE dbo.Load_Fact_Daily_ICU_Status
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @LastProcessedDate DATE;
    DECLARE @NewLastProcessedDate DATE;
    DECLARE @MaxSafeDate DATE;
    DECLARE @ReloadStartDate DATE;
    DECLARE @InsertedRows INT = 0;
    DECLARE @ErrorMessage NVARCHAR(MAX);

    BEGIN TRY

    --------------------------------------------------
    -- Ensure control record exists
    --------------------------------------------------
    IF NOT EXISTS (
        SELECT 1 
        FROM dbo.ETL_Control 
        WHERE Table_Name = 'ICU_DAILY_STATUS'
    )
    BEGIN
        INSERT INTO dbo.ETL_Control
        (Table_Name, Last_Processed_Date, Last_Run_Status)
        VALUES ('ICU_DAILY_STATUS', NULL, 'INITIAL');
    END

    --------------------------------------------------
    -- Get last processed date
    --------------------------------------------------
    SELECT @LastProcessedDate = Last_Processed_Date
    FROM dbo.ETL_Control
    WHERE Table_Name = 'ICU_DAILY_STATUS';

    --------------------------------------------------
    -- Safe date (until yesterday)
    --------------------------------------------------
    SET @MaxSafeDate = DATEADD(DAY, -1, CAST(GETDATE() AS DATE));

    --------------------------------------------------
    -- Sliding window
    --------------------------------------------------
    SET @ReloadStartDate =
        ISNULL(DATEADD(DAY, -2, @LastProcessedDate), '1900-01-01');

    --------------------------------------------------
    -- Clean temp tables
    --------------------------------------------------
    TRUNCATE TABLE dbo.Tmp_InputData;
    TRUNCATE TABLE dbo.Tmp_OutputData;
    TRUNCATE TABLE dbo.Tmp_Aggregated;

    --------------------------------------------------
    -- Load InputData
    --------------------------------------------------
    INSERT INTO dbo.Tmp_InputData
    SELECT 
        i.SUBJECT_ID,
        i.ICU_STAY_ID,
        CAST(i.CHART_TIME AS DATE),
        d.CATEGORY,
        SUM(ISNULL(i.AMOUNT,0))
    FROM DW_Staging.Stage.ICU_INPUT_EVENTS_CV i
    LEFT JOIN DW_Staging.Stage.ICU_D_ITEMS d
        ON i.ITEM_ID = d.ITEM_ID
    WHERE CAST(i.CHART_TIME AS DATE) 
          BETWEEN @ReloadStartDate AND @MaxSafeDate
    GROUP BY i.SUBJECT_ID, i.ICU_STAY_ID, CAST(i.CHART_TIME AS DATE), d.CATEGORY;

    INSERT INTO dbo.Tmp_InputData
    SELECT 
        m.SUBJECT_ID,
        m.ICU_STAY_ID,
        CAST(m.START_TIME AS DATE),
        d.CATEGORY,
        SUM(ISNULL(m.TOTAL_AMOUNT,0))
    FROM DW_Staging.Stage.ICU_INPUT_EVENTS_MV m
    LEFT JOIN DW_Staging.Stage.ICU_D_ITEMS d
        ON m.ITEM_ID = d.ITEM_ID
    WHERE CAST(m.START_TIME AS DATE) 
          BETWEEN @ReloadStartDate AND @MaxSafeDate
    GROUP BY m.SUBJECT_ID, m.ICU_STAY_ID, CAST(m.START_TIME AS DATE), d.CATEGORY;

    --------------------------------------------------
    -- Load OutputData
    --------------------------------------------------
    INSERT INTO dbo.Tmp_OutputData
    SELECT 
        o.SUBJECT_ID,
        o.ICU_STAY_ID,
        CAST(o.CHART_TIME AS DATE),
        d.CATEGORY,
        SUM(ISNULL(o.VALUE,0))
    FROM DW_Staging.Stage.ICU_OUTPUT_EVENTS o
    LEFT JOIN DW_Staging.Stage.ICU_D_ITEMS d
        ON o.ITEM_ID = d.ITEM_ID
    WHERE CAST(o.CHART_TIME AS DATE) 
          BETWEEN @ReloadStartDate AND @MaxSafeDate
    GROUP BY o.SUBJECT_ID, o.ICU_STAY_ID, CAST(o.CHART_TIME AS DATE), d.CATEGORY;

    --------------------------------------------------
    -- Build Aggregated
    --------------------------------------------------
    INSERT INTO dbo.Tmp_Aggregated
    SELECT 
        COALESCE(i.SUBJECT_ID, o.SUBJECT_ID),
        COALESCE(i.ICU_STAY_ID, o.ICU_STAY_ID),
        COALESCE(i.SnapshotDate, o.SnapshotDate),

        SUM(CASE WHEN i.CATEGORY LIKE '%Intake%' THEN i.Amount ELSE 0 END),
        SUM(CASE WHEN i.CATEGORY LIKE '%Blood%' THEN i.Amount ELSE 0 END),

        SUM(CASE WHEN o.CATEGORY LIKE '%Urine%' THEN o.Amount ELSE 0 END),
        SUM(CASE WHEN o.CATEGORY LIKE '%Drain%' THEN o.Amount ELSE 0 END)

    FROM dbo.Tmp_InputData i
    FULL OUTER JOIN dbo.Tmp_OutputData o
        ON i.SUBJECT_ID = o.SUBJECT_ID
        AND i.ICU_STAY_ID = o.ICU_STAY_ID
        AND i.SnapshotDate = o.SnapshotDate
    GROUP BY 
        COALESCE(i.SUBJECT_ID, o.SUBJECT_ID),
        COALESCE(i.ICU_STAY_ID, o.ICU_STAY_ID),
        COALESCE(i.SnapshotDate, o.SnapshotDate);

    --------------------------------------------------
    -- Delete old data (window)
    --------------------------------------------------
    DELETE FROM dbo.Fact_Daily_ICU_Status
    WHERE Date_SK IN (
        SELECT Date_SK
        FROM dbo.Dim_Date
        WHERE FullDate BETWEEN @ReloadStartDate AND @MaxSafeDate
    );

    --------------------------------------------------
    -- Insert into fact
    --------------------------------------------------
    INSERT INTO dbo.Fact_Daily_ICU_Status
    SELECT
        d.Date_SK,
        p.Patient_SK,
        a.ICU_STAY_ID,

        a.Fluid_Input_ml,
        a.Blood_Input_ml,
        a.Urine_Output_ml,
        a.Drain_Output_ml,

        (a.Fluid_Input_ml + a.Blood_Input_ml),
        (a.Urine_Output_ml + a.Drain_Output_ml),

        (a.Fluid_Input_ml + a.Blood_Input_ml) 
        - (a.Urine_Output_ml + a.Drain_Output_ml),

        CASE 
            WHEN a.SnapshotDate < s.IN_TIME THEN NULL
            WHEN a.SnapshotDate > s.OUT_TIME THEN NULL
            ELSE DATEDIFF(DAY, s.IN_TIME, a.SnapshotDate)
        END

    FROM dbo.Tmp_Aggregated a
    INNER JOIN dbo.Dim_Date d
        ON a.SnapshotDate = d.FullDate
    INNER JOIN dbo.Dim_Patient p
        ON a.SUBJECT_ID = p.Patient_ID
    INNER JOIN DW_Staging.Stage.ICU_STAYS s
        ON a.ICU_STAY_ID = s.ICU_STAY_ID;

    SET @InsertedRows = @@ROWCOUNT;

    --------------------------------------------------
    -- Get REAL last processed date (from FACT)
    --------------------------------------------------
    SELECT @NewLastProcessedDate = MAX(d.FullDate)
    FROM dbo.Fact_Daily_ICU_Status f
    JOIN dbo.Dim_Date d
        ON f.Date_SK = d.Date_SK
    WHERE d.FullDate BETWEEN @ReloadStartDate AND @MaxSafeDate;

    -- If no data inserted
    IF @NewLastProcessedDate IS NULL
        SET @NewLastProcessedDate = @LastProcessedDate;

    --------------------------------------------------
    -- Update ETL Control
    --------------------------------------------------
    UPDATE dbo.ETL_Control
    SET 
        Last_Processed_Date = @NewLastProcessedDate,
        Last_Run_Status = 'SUCCESS',
        Last_Run_Timestamp = GETDATE(),
        Error_Message = NULL
    WHERE Table_Name = 'ICU_DAILY_STATUS';

    --------------------------------------------------
    -- Log
    --------------------------------------------------
    EXEC dbo.sp_Insert_ETL_Log
        @Procedure_Name = 'Load_Fact_Daily_ICU_Status',
        @Action_Name = 'INSERT',
        @Object_Name = 'Fact_Daily_ICU_Status',
        @Affected_Row_Number = @InsertedRows;

    END TRY

    BEGIN CATCH

        SET @ErrorMessage = ERROR_MESSAGE();

        UPDATE dbo.ETL_Control
        SET 
            Last_Run_Status = 'FAILED',
            Last_Run_Timestamp = GETDATE(),
            Error_Message = @ErrorMessage
        WHERE Table_Name = 'ICU_DAILY_STATUS';

        --------------------------------------------------
        -- Log FAIL 
        --------------------------------------------------
        EXEC dbo.sp_Insert_ETL_Log
            @Procedure_Name = 'Load_Fact_Lab_Event',
            @Action_Name = 'INSERT',
            @Object_Name = 'Fact_Lab_Event',
            @Affected_Row_Number = 0;

        THROW;

    END CATCH

END;
GO






CREATE TABLE dbo.Tmp_ICU_Journey (
    ICU_Stay_ID INT PRIMARY KEY,

    Patient_SK INT NOT NULL,
    Admit_Date_SK INT NOT NULL,

    -- Timeline
    ICU_Admit_Time DATETIME,
    Vent_Start_Time DATETIME,
    Vent_End_Time DATETIME,
    First_Antibiotic_Time DATETIME,
    Dialysis_Start_Time DATETIME,
    ICU_Discharge_Time DATETIME,

    -- Measures
    Time_To_Vent_Hours FLOAT,
    Vent_Duration_Hours FLOAT,
    Time_To_Antibiotic_Hours FLOAT,
    LOS_ICU_Hours FLOAT,

    -- Flags
    Ventilated_Flag INT,
    Sepsis_Suspected_Flag INT,
    Dialysis_Flag INT,

    -- Outcome
    Mortality_Flag INT
);

CREATE OR ALTER PROCEDURE dbo.Load_Fact_ICU_Clinical_Journey
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @LastRun DATETIME;
    DECLARE @NewLastRun DATETIME = GETDATE();

    DECLARE @InsertedRows INT = 0;
    DECLARE @UpdatedRows INT = 0;
    DECLARE @TotalRows INT = 0;

    --------------------------------------------------
    -- 0. Ensure ETL Control Record Exists
    --------------------------------------------------
    IF NOT EXISTS (
        SELECT 1 
        FROM dbo.ETL_Control 
        WHERE Table_Name = 'Fact_ICU_Clinical_Journey'
    )
    BEGIN
        INSERT INTO dbo.ETL_Control
        (
            Table_Name,
            Last_Processed_ID,
            Last_Run_Status,
            Last_Modified_Timestamp
        )
        VALUES
        (
            'Fact_ICU_Clinical_Journey',
            0,
            'INITIAL',
            '1900-01-01'
        );
    END

    --------------------------------------------------
    -- 1. Get Last Run
    --------------------------------------------------
    SELECT @LastRun = Last_Modified_Timestamp
    FROM dbo.ETL_Control
    WHERE Table_Name = 'Fact_ICU_Clinical_Journey';

    IF @LastRun IS NULL
        SET @LastRun = '1900-01-01';

    BEGIN TRY

        --------------------------------------------------
        -- 2. TRUNCATE temp table
        --------------------------------------------------
        TRUNCATE TABLE dbo.Tmp_ICU_Journey;

        --------------------------------------------------
        -- 3. Build dataset 
        --------------------------------------------------
        INSERT INTO dbo.Tmp_ICU_Journey
        SELECT 
            b.ICU_STAY_ID,
            p.Patient_SK,
            d.Date_SK,

            b.IN_TIME,
            v.Vent_Start_Time,
            v.Vent_End_Time,
            ab.First_Antibiotic_Time,
            dly.Dialysis_Start_Time,
            b.OUT_TIME,

            DATEDIFF(HOUR, b.IN_TIME, v.Vent_Start_Time),
            DATEDIFF(HOUR, v.Vent_Start_Time, v.Vent_End_Time),
            DATEDIFF(HOUR, b.IN_TIME, ab.First_Antibiotic_Time),
            DATEDIFF(HOUR, b.IN_TIME, b.OUT_TIME),

            CASE WHEN v.ICU_STAY_ID IS NOT NULL THEN 1 ELSE 0 END,
            CASE WHEN ab.ICU_STAY_ID IS NOT NULL THEN 1 ELSE 0 END,
            CASE WHEN dly.ICU_STAY_ID IS NOT NULL THEN 1 ELSE 0 END,

            b.HOSPITAL_EXPIRE_FLAG

        FROM (
            SELECT 
                s.ICU_STAY_ID,
                s.SUBJECT_ID,
                s.HADM_ID,
                s.IN_TIME,
                s.OUT_TIME,
                a.HOSPITAL_EXPIRE_FLAG
            FROM DW_Staging.Stage.ICU_STAYS s
            JOIN DW_Staging.Stage.Clinic_ADMISSIONS a
                ON s.HADM_ID = a.HADM_ID
            WHERE s.IN_TIME >= @LastRun
               OR s.OUT_TIME >= @LastRun
        ) b

        JOIN Dim_Patient p
            ON p.Patient_ID = b.SUBJECT_ID

        JOIN Dim_Date d
            ON d.FullDate = CAST(b.IN_TIME AS DATE)

        --------------------------------------------------
        -- VENT
        --------------------------------------------------
        LEFT JOIN (
            SELECT 
                pe.ICU_STAY_ID,
                MIN(pe.START_TIME) AS Vent_Start_Time,
                MAX(pe.END_TIME) AS Vent_End_Time
            FROM DW_Staging.Stage.ICU_PROCEDURE_EVENTS_MV pe
            JOIN DW_Staging.Stage.ICU_D_ITEMS di
                ON pe.ITEM_ID = di.ITEM_ID
            WHERE di.CATEGORY LIKE '%Respiratory%'
            GROUP BY pe.ICU_STAY_ID
        ) v ON b.ICU_STAY_ID = v.ICU_STAY_ID

        --------------------------------------------------
        -- Antibiotic 
        --------------------------------------------------
        LEFT JOIN (
            SELECT 
                ie.ICU_STAY_ID,
                MIN(ie.START_TIME) AS First_Antibiotic_Time
            FROM DW_Staging.Stage.ICU_INPUT_EVENTS_MV ie
            JOIN DW_Staging.Stage.ICU_D_ITEMS di
                ON ie.ITEM_ID = di.ITEM_ID
            WHERE di.LABEL LIKE '%antibiotic%'
            GROUP BY ie.ICU_STAY_ID
        ) ab ON b.ICU_STAY_ID = ab.ICU_STAY_ID

        --------------------------------------------------
        -- Dialysis
        --------------------------------------------------
        LEFT JOIN (
            SELECT 
                pe.ICU_STAY_ID,
                MIN(pe.START_TIME) AS Dialysis_Start_Time
            FROM DW_Staging.Stage.ICU_PROCEDURE_EVENTS_MV pe
            JOIN DW_Staging.Stage.ICU_D_ITEMS di
                ON pe.ITEM_ID = di.ITEM_ID
            WHERE di.LABEL LIKE '%dialysis%'
            GROUP BY pe.ICU_STAY_ID
        ) dly ON b.ICU_STAY_ID = dly.ICU_STAY_ID;

        --------------------------------------------------
        -- 4. UPDATE
        --------------------------------------------------
        UPDATE f
        SET
            f.Vent_Start_Time = t.Vent_Start_Time,
            f.Vent_End_Time = t.Vent_End_Time,
            f.First_Antibiotic_Time = t.First_Antibiotic_Time,
            f.Dialysis_Start_Time = t.Dialysis_Start_Time,
            f.ICU_Discharge_Time = t.ICU_Discharge_Time,

            f.Time_To_Vent_Hours = t.Time_To_Vent_Hours,
            f.Vent_Duration_Hours = t.Vent_Duration_Hours,
            f.Time_To_Antibiotic_Hours = t.Time_To_Antibiotic_Hours,
            f.LOS_ICU_Hours = t.LOS_ICU_Hours,

            f.Ventilated_Flag = t.Ventilated_Flag,
            f.Sepsis_Suspected_Flag = t.Sepsis_Suspected_Flag,
            f.Dialysis_Flag = t.Dialysis_Flag,
            f.Mortality_Flag = t.Mortality_Flag

        FROM Fact_ICU_Clinical_Journey f
        JOIN dbo.Tmp_ICU_Journey t
            ON f.ICU_Stay_ID = t.ICU_Stay_ID;

        SET @UpdatedRows = @@ROWCOUNT;

        --------------------------------------------------
        -- 5. INSERT
        --------------------------------------------------
        INSERT INTO Fact_ICU_Clinical_Journey (
            ICU_Stay_ID,
            Patient_SK,
            Admit_Date_SK,
            ICU_Admit_Time,
            Vent_Start_Time,
            Vent_End_Time,
            First_Antibiotic_Time,
            Dialysis_Start_Time,
            ICU_Discharge_Time,
            Time_To_Vent_Hours,
            Vent_Duration_Hours,
            Time_To_Antibiotic_Hours,
            LOS_ICU_Hours,
            Ventilated_Flag,
            Sepsis_Suspected_Flag,
            Dialysis_Flag,
            Mortality_Flag
        )
        SELECT *
        FROM dbo.Tmp_ICU_Journey t
        WHERE NOT EXISTS (
            SELECT 1
            FROM Fact_ICU_Clinical_Journey f
            WHERE f.ICU_Stay_ID = t.ICU_Stay_ID
        );

        SET @InsertedRows = @@ROWCOUNT;
        SET @TotalRows = @InsertedRows + @UpdatedRows;

        --------------------------------------------------
        -- 6. UPDATE ETL CONTROL
        --------------------------------------------------
        UPDATE dbo.ETL_Control
        SET 
            Last_Run_Status = 'SUCCESS',
            Last_Run_Timestamp = @NewLastRun,
            Last_Modified_Timestamp = @NewLastRun,
            Error_Message = NULL
        WHERE Table_Name = 'Fact_ICU_Clinical_Journey';

        EXEC dbo.sp_Insert_ETL_Log
            @Procedure_Name = 'Load_Fact_ICU_Clinical_Journey',
            @Action_Name = 'INSERT',
            @Object_Name = 'Fact_ICU_Clinical_Journey',
            @Affected_Row_Number = @TotalRows;

    END TRY
    BEGIN CATCH

        UPDATE dbo.ETL_Control
        SET 
            Last_Run_Status = 'FAILED',
            Error_Message = ERROR_MESSAGE(),
            Last_Run_Timestamp = GETDATE()
        WHERE Table_Name = 'Fact_ICU_Clinical_Journey';

        EXEC dbo.sp_Insert_ETL_Log
            @Procedure_Name = 'Load_Fact_ICU_Clinical_Journey',
            @Action_Name = 'INSERT',
            @Object_Name = 'Fact_ICU_Clinical_Journey',
            @Affected_Row_Number = @InsertedRows;

    END CATCH
END;