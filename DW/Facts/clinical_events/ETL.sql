CREATE OR ALTER PROCEDURE dbo.Load_Fact_Lab_Event
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @LastProcessedID INT = 0;
    DECLARE @NewLastProcessedID INT;


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
        -- 3. Insert into Fact
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
        -- 4. Get new max processed ID (ONLY NEW DATA)
        --------------------------------------------------
        SELECT @NewLastProcessedID = MAX(ROW_ID)
        FROM DW_Staging.Stage.LAB_EVENTS
        WHERE ROW_ID > @LastProcessedID;


        --------------------------------------------------
        -- 5. Update control
        --------------------------------------------------
        UPDATE dbo.ETL_Control
        SET 
            Last_Processed_ID = ISNULL(@NewLastProcessedID, Last_Processed_ID),
            Last_Run_Status = 'SUCCESS',
            Last_Run_Timestamp = GETDATE(),
            Error_Message = NULL
        WHERE Table_Name = 'LAB_EVENTS';


    END TRY

    BEGIN CATCH

        UPDATE dbo.ETL_Control
        SET 
            Last_Run_Status = 'FAILED',
            Last_Run_Timestamp = GETDATE(),
            Error_Message = ERROR_MESSAGE()
        WHERE Table_Name = 'LAB_EVENTS';

        THROW;

    END CATCH

END;