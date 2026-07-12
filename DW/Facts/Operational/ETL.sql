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
