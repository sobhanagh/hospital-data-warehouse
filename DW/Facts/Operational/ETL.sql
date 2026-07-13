CREATE PROCEDURE sp_Load_Bridge_Diagnosis_Group
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TableName VARCHAR(100) = 'Bridge_Diagnosis_Group';
    DECLARE @LastProcessedID INT;
    DECLARE @CurrentMaxID INT;

    SELECT @LastProcessedID = Last_Processed_ID 
    FROM ETL_Control 
    WHERE Table_Name = @TableName;

    IF @LastProcessedID IS NULL 
        SET @LastProcessedID = 0;

    SELECT @CurrentMaxID = MAX(ROW_ID) FROM DW_Staging.Stage.Clinic_DIAGNOSES_ICD;

    IF @CurrentMaxID IS NULL OR @CurrentMaxID <= @LastProcessedID
        RETURN;

    BEGIN TRY
        BEGIN TRANSACTION;

        WITH Source AS (
            SELECT 
                d.HADM_ID AS Diagnosis_Group_SK,
                dim.Diagnosis_SK AS Diagnosis_SK,
                d.ICD9_CODE,
                d.SEQ_NUM AS Sequence_Number,
                CASE WHEN d.SEQ_NUM = 1 THEN 1 ELSE 0 END AS Is_Primary_Diagnosis,
                ROW_NUMBER() OVER (
                    PARTITION BY d.HADM_ID, d.ICD9_CODE 
                    ORDER BY d.ROW_ID DESC
                ) AS RowRank
            FROM DW_Staging.Stage.Clinic_DIAGNOSES_ICD d
            JOIN Dim_Diagnosis dim ON d.ICD9_CODE = dim.ICD9_CODE
            WHERE d.ROW_ID > @LastProcessedID 
              AND d.HADM_ID IS NOT NULL
        ),
        CleanSource AS (
            SELECT * FROM Source WHERE RowRank = 1
        )
        INSERT INTO Bridge_Diagnosis_Group (
            Diagnosis_Group_SK,
            Diagnosis_SK,
            ICD9_Code,
            Sequence_Number,
            Is_Primary_Diagnosis
        )
        SELECT 
            s.Diagnosis_Group_SK,
            s.Diagnosis_SK,
            s.ICD9_CODE,
            s.Sequence_Number,
            s.Is_Primary_Diagnosis
        FROM CleanSource s
        WHERE NOT EXISTS (
            SELECT 1 
            FROM Bridge_Diagnosis_Group b 
            WHERE b.Diagnosis_Group_SK = s.Diagnosis_Group_SK 
                AND b.Diagnosis_SK = s.Diagnosis_SK
        );

        UPDATE ETL_Control 
        SET 
            Last_Processed_ID = @CurrentMaxID, 
            Last_Run_Status = 'SUCCESS',
            Last_Run_Timestamp = GETDATE()
        WHERE Table_Name = @TableName;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        DECLARE @ErrMsg VARCHAR(4000) = ERROR_MESSAGE();

        UPDATE ETL_Control 
        SET 
            Last_Run_Status = 'FAILED',
            Last_Run_Timestamp = GETDATE(),
            Error_Message = @ErrMsg
        WHERE Table_Name = @TableName;

        THROW;
    END CATCH;
END;
GO

CREATE PROCEDURE sp_Load_Fact_Hospital_Admissions
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TableName VARCHAR(100) = 'Fact_Hospital_Admissions';
    DECLARE @LastProcessedID INT;
    DECLARE @CurrentMaxID INT;

    SELECT @LastProcessedID = Last_Processed_ID 
    FROM ETL_Control 
    WHERE Table_Name = @TableName;

    IF @LastProcessedID IS NULL 
        SET @LastProcessedID = 0;

    SELECT @CurrentMaxID = MAX(ROW_ID) FROM DW_Staging.Stage.Clinic_ADMISSIONS;

    IF @CurrentMaxID IS NULL OR @CurrentMaxID <= @LastProcessedID
        RETURN;

    BEGIN TRY
        BEGIN TRANSACTION;

        CREATE TABLE #AffectedPatients (
            SUBJECT_ID INT PRIMARY KEY
        );

        INSERT INTO #AffectedPatients (SUBJECT_ID)
        SELECT DISTINCT SUBJECT_ID 
        FROM DW_Staging.Stage.Clinic_ADMISSIONS
        WHERE ROW_ID > @LastProcessedID 
          AND ROW_ID <= @CurrentMaxID;

        WITH AdmissionReadmission AS (
            SELECT 
                a.HADM_ID,
                a.SUBJECT_ID,
                a.ADMIT_TIME,
                a.DISCH_TIME,
                a.HOSPITAL_EXPIRE_FLAG,
                LEAD(a.ADMIT_TIME, 1) OVER (PARTITION BY a.SUBJECT_ID ORDER BY a.ADMIT_TIME ASC) AS Next_Admit_Time
            FROM DW_Staging.Stage.Clinic_ADMISSIONS a
            JOIN #AffectedPatients ap
                ON a.SUBJECT_ID = ap.SUBJECT_ID
        ),
        ResourceCounts AS (
            SELECT 
                t.HADM_ID,
                COUNT(DISTINCT t.ICU_STAY_ID) AS Total_ICU_Stays,
                COUNT(*) AS Total_Transfers
            FROM DW_Staging.Stage.Clinic_TRANSFERS t
            WHERE t.HADM_ID IN (SELECT HADM_ID FROM AdmissionReadmission)
            GROUP BY t.HADM_ID
        ),
        SourceData AS (
            SELECT 
                a.HADM_ID,
                ISNULL(p.Patient_SK, -1) AS Patient_SK,
                CAST(FORMAT(a.ADMIT_TIME, 'yyyyMMdd') AS INT) AS Admit_Date_SK,
                CAST(FORMAT(a.DISCH_TIME, 'yyyyMMdd') AS INT) AS Disch_Date_SK,
                a.HADM_ID AS Diagnosis_Group_SK,
                
                CAST(DATEDIFF(minute, a.ADMIT_TIME, a.DISCH_TIME) / 1440.0 AS DECIMAL(10,2)) AS Length_of_Stay_Days,
                CASE WHEN a.HOSPITAL_EXPIRE_FLAG = 1 THEN 1 ELSE 0 END AS Is_Hospital_Mortality,
                
                CASE 
                    WHEN a.Next_Admit_Time IS NOT NULL AND DATEDIFF(day, a.DISCH_TIME, a.Next_Admit_Time) <= 30 THEN 1 
                    ELSE 0 
                END AS Is_Readmission_30_Days,
                
                CASE 
                    WHEN a.Next_Admit_Time IS NOT NULL THEN CAST(DATEDIFF(hour, a.DISCH_TIME, a.Next_Admit_Time) / 24.0 AS DECIMAL(10,2))
                    ELSE NULL 
                END AS Days_Until_Next_Admission,
                
                ISNULL(rc.Total_ICU_Stays, 0) AS Total_ICU_Stays_Count,
                ISNULL(rc.Total_Transfers, 0) AS Total_Ward_Transfers_Count

            FROM AdmissionReadmission a
            JOIN Dim_Patient p
                ON a.SUBJECT_ID = p.Patient_ID
            LEFT JOIN ResourceCounts rc
                ON a.HADM_ID = rc.HADM_ID
            WHERE a.Next_Admit_Time >= a.DISCH_TIME
        )

        MERGE Fact_Hospital_Admissions AS Target
        USING SourceData AS Source
        ON Target.Admision_ID = Source.HADM_ID

        WHEN MATCHED AND (
            Target.Patient_SK <> Source.Patient_SK OR
            Target.Disch_Date_SK <> Source.Disch_Date_SK OR
            Target.Length_of_Stay_Days <> Source.Length_of_Stay_Days OR
            Target.Is_Hospital_Mortality <> Source.Is_Hospital_Mortality OR
            Target.Is_Readmission_30_Days <> Source.Is_Readmission_30_Days OR
            ISNULL(Target.Days_Until_Next_Admission, -1) <> ISNULL(Source.Days_Until_Next_Admission, -1) OR
            Target.Total_ICU_Stays_Count <> Source.Total_ICU_Stays_Count OR
            Target.Total_Ward_Transfers_Count <> Source.Total_Ward_Transfers_Count
        ) THEN 
            UPDATE SET 
                Target.Patient_SK = Source.Patient_SK,
                Target.Disch_Date_SK = Source.Disch_Date_SK,
                Target.Length_of_Stay_Days = Source.Length_of_Stay_Days,
                Target.Is_Hospital_Mortality = Source.Is_Hospital_Mortality,
                Target.Is_Readmission_30_Days = Source.Is_Readmission_30_Days,
                Target.Days_Until_Next_Admission = Source.Days_Until_Next_Admission,
                Target.Total_ICU_Stays_Count = Source.Total_ICU_Stays_Count,
                Target.Total_Ward_Transfers_Count = Source.Total_Ward_Transfers_Count

        WHEN NOT MATCHED BY TARGET THEN
            INSERT (
                Admission_ID, Patient_SK, Admit_Date_SK, Disch_Date_SK, Diagnosis_Group_SK,
                Length_of_Stay_Days, Is_Hospital_Mortality, Is_Readmission_30_Days,
                Days_Until_Next_Admission, Total_ICU_Stays_Count, Total_Ward_Transfers_Count
            )
            VALUES (
                Source.HADM_ID, Source.Patient_SK, Source.Admit_Date_SK, Source.Disch_Date_SK, Source.Diagnosis_Group_SK,
                Source.Length_of_Stay_Days, Source.Is_Hospital_Mortality, Source.Is_Readmission_30_Days,
                Source.Days_Until_Next_Admission, Source.Total_ICU_Stays_Count, Source.Total_Ward_Transfers_Count
            );

        DROP TABLE #AffectedPatients;

        UPDATE ETL_Control 
        SET 
            Last_Processed_ID = @CurrentMaxID, 
            Last_Run_Status = 'SUCCESS',
            Last_Run_Timestamp = GETDATE()
        WHERE Table_Name = @TableName;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        DECLARE @ErrMsg TEXT = ERROR_MESSAGE();

        UPDATE ETL_Control 
        SET 
            Last_Run_Status = 'FAILED',
            Last_Run_Timestamp = GETDATE(),
            Error_Message = @ErrMsg
        WHERE Table_Name = @TableName;

        THROW;
    END CATCH;
END;
GO

CREATE PROCEDURE sp_Load_Fact_ICU_Bed_Coordination
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TableName VARCHAR(100) = 'Fact_ICU_Bed_Coordination';
    DECLARE @LastProcessedID INT;
    DECLARE @CurrentMaxID INT;

    SELECT @LastProcessedID = Last_Processed_ID 
    FROM ETL_Control 
    WHERE Table_Name = @TableName;

    IF @LastProcessedID IS NULL 
        SET @LastProcessedID = 0;

    SELECT @CurrentMaxID = MAX(ROW_ID) FROM DW_Staging.Stage.Clinic_CALLOUT;

    IF @CurrentMaxID IS NULL OR @CurrentMaxID <= @LastProcessedID
        RETURN;

    BEGIN TRY
        BEGIN TRANSACTION;

        WITH SourceDelta AS (
            SELECT 
                c.ROW_ID AS Callout_ID,
                ISNULL(p.Patient_SK, -1) AS Patient_SK,
                c.HADM_ID,
                CAST(FORMAT(c.CREATE_TIME, 'yyyyMMdd') AS INT) AS Create_Date_SK,                
                ISNULL(f_sub.Facility_SK, -1) AS Submit_Ward_SK,
                ISNULL(f_call.Facility_SK, -1) AS Callout_Ward_SK,
                c.CALLOUT_SERVICE AS Callout_Service,
                c.CALLOUT_STATUS AS Callout_Status,
                c.CALLOUT_OUTCOME AS Callout_Outcome,                
                CASE 
                    WHEN c.ACKNOWLEDGE_TIME IS NOT NULL 
                    THEN DATEDIFF(minute, c.CREATE_TIME, c.ACKNOWLEDGE_TIME) 
                    ELSE NULL 
                END AS Admin_Acknowledge_Delay_Minutes,
                CASE 
                    WHEN c.OUTCOME_TIME IS NOT NULL 
                    THEN CAST(DATEDIFF(minute, c.CREATE_TIME, c.OUTCOME_TIME) / 60.0 AS DECIMAL(10,2)) 
                    ELSE NULL 
                END AS Bed_Placement_Delay_Hours,                
                CASE WHEN c.ACKNOWLEDGE_STATUS = 'Unacknowledged' THEN 1 ELSE 0 END AS Is_Unacknowledged_Flag,
                CASE 
                    WHEN c.OUTCOME_TIME IS NOT NULL AND (DATEDIFF(minute, c.CREATE_TIME, c.OUTCOME_TIME) / 60.0) > 6.0 
                    THEN 1 ELSE 0 
                END AS Is_Severe_Bed_Block_Flag
            FROM DW_Staging.Stage.Clinic_CALLOUT c
            LEFT JOIN Dim_Patient p
                ON c.SUBJECT_ID = p.Patient_ID
            LEFT JOIN Dim_Facility f_sub
                ON c.SUBMIT_WARD_ID = f_sub.Ward_ID
            LEFT JOIN Dim_Facility f_call
                ON c.CALLOUT_WARD_ID = f_call.Ward_ID
            WHERE c.ROW_ID > @LastProcessedID 
        )
        MERGE Fact_ICU_Bed_Coordination AS Target
        USING SourceDelta AS Source
        ON Target.Callout_SK = Source.Callout_ID

        WHEN MATCHED AND (
            Target.Callout_Status <> Source.Callout_Status OR
            Target.Callout_Outcome <> Source.Callout_Outcome OR
            ISNULL(Target.Admin_Acknowledge_Delay_Minutes, -1) <> ISNULL(Source.Admin_Acknowledge_Delay_Minutes, -1) OR
            ISNULL(Target.Bed_Placement_Delay_Hours, -1) <> ISNULL(Source.Bed_Placement_Delay_Hours, -1) OR
            Target.Is_Unacknowledged_Flag <> Source.Is_Unacknowledged_Flag OR
            Target.Is_Severe_Bed_Block_Flag <> Source.Is_Severe_Bed_Block_Flag
        ) THEN 
            UPDATE SET 
                Target.Patient_SK = Source.Patient_SK,
                Target.Callout_Status = Source.Callout_Status,
                Target.Callout_Outcome = Source.Callout_Outcome,
                Target.Admin_Acknowledge_Delay_Minutes = Source.Admin_Acknowledge_Delay_Minutes,
                Target.Bed_Placement_Delay_Hours = Source.Bed_Placement_Delay_Hours,
                Target.Is_Unacknowledged_Flag = Source.Is_Unacknowledged_Flag,
                Target.Is_Severe_Bed_Block_Flag = Source.Is_Severe_Bed_Block_Flag

        WHEN NOT MATCHED BY TARGET THEN
            INSERT (
                Callout_SK, Patient_SK, HADM_ID, Create_Date_SK, 
                Submit_Ward_SK, Callout_Ward_SK, 
                Callout_Service, Callout_Status, Callout_Outcome, 
                Admin_Acknowledge_Delay_Minutes, Bed_Placement_Delay_Hours, 
                Is_Unacknowledged_Flag, Is_Severe_Bed_Block_Flag
            )
            VALUES (
                Source.Callout_ID, Source.Patient_SK, Source.HADM_ID, Source.Create_Date_SK, 
                Source.Submit_Ward_SK, Source.Callout_Ward_SK, 
                Source.Callout_Service, Source.Callout_Status, Source.Callout_Outcome, 
                Source.Admin_Acknowledge_Delay_Minutes, Source.Bed_Placement_Delay_Hours,
                Source.Is_Unacknowledged_Flag, Source.Is_Severe_Bed_Block_Flag
            );

        UPDATE ETL_Control 
        SET 
            Last_Processed_ID = @CurrentMaxID, 
            Last_Run_Status = 'SUCCESS',
            Last_Run_Timestamp = GETDATE()
        WHERE Table_Name = @TableName;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        DECLARE @ErrMsg VARCHAR(4000) = ERROR_MESSAGE();

        UPDATE ETL_Control 
        SET 
            Last_Run_Status = 'FAILED',
            Last_Run_Timestamp = GETDATE(),
            Error_Message = @ErrMsg
        WHERE Table_Name = @TableName;

        THROW;
    END CATCH;
END;
GO
