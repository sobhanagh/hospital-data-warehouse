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
        -- 1. Ensure control record exists
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
        -- 2. Get last processed ID
        --------------------------------------------------
        SELECT @LastProcessedID = Last_Processed_ID
        FROM dbo.ETL_Control
        WHERE Table_Name = 'LAB_EVENTS';


        --------------------------------------------------
        -- 3. Load Fact (Incremental)
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
        -- 4. Capture rowcount IMMEDIATELY
        --------------------------------------------------
        SET @InsertedRows = @@ROWCOUNT;


        --------------------------------------------------
        -- 5. Get new max ROW_ID
        --------------------------------------------------
        SELECT @NewLastProcessedID = MAX(ROW_ID)
        FROM DW_Staging.Stage.LAB_EVENTS
        WHERE ROW_ID > @LastProcessedID;


        --------------------------------------------------
        -- 6. Update ETL_Control (SUCCESS)
        --------------------------------------------------
        UPDATE dbo.ETL_Control
        SET 
            Last_Processed_ID = ISNULL(@NewLastProcessedID, Last_Processed_ID),
            Last_Run_Status = 'SUCCESS',
            Last_Run_Timestamp = GETDATE(),
            Error_Message = NULL
        WHERE Table_Name = 'LAB_EVENTS';


        --------------------------------------------------
        -- 7. Log SUCCESS (separate concern)
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
        -- Update ETL_Control (FAILED + error message)
        --------------------------------------------------
        UPDATE dbo.ETL_Control
        SET 
            Last_Run_Status = 'FAILED',
            Last_Run_Timestamp = GETDATE(),
            Error_Message = @ErrorMessage
        WHERE Table_Name = 'LAB_EVENTS';


        --------------------------------------------------
        -- Log FAIL (no mixing with control)
        --------------------------------------------------
        EXEC dbo.sp_Insert_ETL_Log
            @Procedure_Name = 'Load_Fact_Lab_Event',
            @Action_Name = 'FAILED',
            @Object_Name = 'Fact_Lab_Event',
            @Affected_Row_Number = 0;


        --------------------------------------------------
        -- Re-throw error
        --------------------------------------------------
        THROW;

    END CATCH

END;
GO