-- INCREMENTAL LOAD: Clinic ADMISSIONS (Filtering by ADMIT_TIME)
CREATE PROCEDURE Stage.sp_Load_ADMISSIONS
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Affected_Row_Number INT = 0;
    DECLARE @LastAdmitTime DATETIME;

    SELECT @LastAdmitTime = ISNULL(MAX(ADMIT_TIME), '2001-01-01') 
    FROM Stage.Clinic_ADMISSIONS;

    INSERT INTO Stage.Clinic_ADMISSIONS (
        ROW_ID, SUBJECT_ID, HADM_ID, ADMIT_TIME, DISCH_TIME, 
        ADMISSION_TYPE, ADMISSION_LOCATION, DISCHARGE_LOCATION, INSURANCE, 
        ETHNICITY, DIAGNOSIS, HOSPITAL_EXPIRE_FLAG
    )
    SELECT 
        ROW_ID, SUBJECT_ID, HADM_ID, ADMIT_TIME, DISCH_TIME, 
        ADMISSION_TYPE, ADMISSION_LOCATION, DISCHARGE_LOCATION, INSURANCE, 
        ETHNICITY, DIAGNOSIS, HOSPITAL_EXPIRE_FLAG
    FROM Hospital.Clinic.ADMISSIONS
    WHERE ADMIT_TIME > @LastAdmitTime;

    SET @Affected_Row_Number = @@ROWCOUNT;

    EXEC Stage.sp_Insert_ETL_Log
        @Procedure_Name = 'Stage.sp_Load_ADMISSIONS',
        @Action_Name = 'INCREMENTAL LOAD',
        @Object_Name = 'Stage.Clinic_ADMISSIONS',
        @Affected_Row_Number = @Affected_Row_Number;
END;
GO

-- INCREMENTAL LOAD: Clinic DIAGNOSES_ICD (Filtering by ROW_ID)
CREATE PROCEDURE Stage.sp_Load_DIAGNOSES_ICD
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Affected_Row_Number INT = 0;
    DECLARE @MaxDiagRowID INT;

    SELECT @MaxDiagRowID = ISNULL(MAX(ROW_ID), 0) 
    FROM Stage.Clinic_DIAGNOSES_ICD;

    INSERT INTO Stage.Clinic_DIAGNOSES_ICD (
        ROW_ID, SUBJECT_ID, HADM_ID, SEQ_NUM, ICD9_CODE
    )
    SELECT 
        ROW_ID, SUBJECT_ID, HADM_ID, SEQ_NUM, ICD9_CODE
    FROM Hospital.Clinic.DIAGNOSES_ICD
    WHERE ROW_ID > @MaxDiagRowID;

    UPDATE Stage.Clinic_DIAGNOSES_ICD
    SET ICD9_CODE = REPLACE(ICD9_CODE, CHAR(13), '')
    WHERE ROW_ID > @MaxDiagRowID
        AND RIGHT(ICD9_CODE, 1) = CHAR(13);

    SET @Affected_Row_Number = @@ROWCOUNT;

    EXEC Stage.sp_Insert_ETL_Log
        @Procedure_Name = 'Stage.sp_Load_DIAGNOSES_ICD',
        @Action_Name = 'INCREMENTAL LOAD',
        @Object_Name = 'Stage.Clinic_DIAGNOSES_ICD',
        @Affected_Row_Number = @Affected_Row_Number;
END;
GO

-- INCREMENTAL LOAD: ICU INPUT_EVENTS_MV (Filtering by START_TIME)
CREATE PROCEDURE Stage.sp_Load_INPUT_EVENTS_MV
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Affected_Row_Number INT = 0;
    DECLARE @LastInputStartTime DATETIME;

    SELECT @LastInputStartTime = ISNULL(MAX(START_TIME), '2001-01-01') 
    FROM Stage.ICU_INPUT_EVENTS_MV;

    INSERT INTO Stage.ICU_INPUT_EVENTS_MV (
        ROW_ID, SUBJECT_ID, HADM_ID, ICU_STAY_ID, START_TIME, END_TIME, 
        ITEM_ID, AMOUNT, AMOUNT_UOM, RATE, RATE_UOM, CG_ID, PATIENT_WEIGHT, 
        TOTAL_AMOUNT, TOTAL_AMOUNT_UOM
    )
    SELECT 
        ROW_ID, SUBJECT_ID, HADM_ID, ICU_STAY_ID, START_TIME, END_TIME, 
        ITEM_ID, AMOUNT, AMOUNT_UOM, RATE, RATE_UOM, CG_ID, PATIENT_WEIGHT,
        TOTAL_AMOUNT, TOTAL_AMOUNT_UOM
    FROM Hospital.ICU.INPUT_EVENTS_MV
    WHERE START_TIME > @LastInputStartTime;

    SET @Affected_Row_Number = @@ROWCOUNT;

    EXEC Stage.sp_Insert_ETL_Log
        @Procedure_Name = 'Stage.sp_Load_INPUT_EVENTS_MV',
        @Action_Name = 'INCREMENTAL LOAD',
        @Object_Name = 'Stage.ICU_INPUT_EVENTS_MV',
        @Affected_Row_Number = @Affected_Row_Number;
END;
GO

-- INCREMENTAL LOAD: Clinic CALLOUT (Filtering by CREATE_TIME)
CREATE PROCEDURE Stage.sp_Load_CALLOUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Affected_Row_Number INT = 0;
    DECLARE @LastCalloutTime DATETIME;
    SELECT @LastCalloutTime = ISNULL(MAX(CREATE_TIME), '2001-01-01') FROM Stage.Clinic_CALLOUT;

    INSERT INTO Stage.Clinic_CALLOUT (
        ROW_ID, SUBJECT_ID, HADM_ID, SUBMIT_WARD_ID, SUBMIT_CARE_UNIT, 
        CURR_WARD_ID, CURR_CARE_UNIT, CALLOUT_WARD_ID, CALLOUT_SERVICE, 
        CALLOUT_STATUS, CALLOUT_OUTCOME, DISCHARGE_WARD_ID, ACKNOWLEDGE_STATUS, 
        CREATE_TIME, UPDATE_TIME, ACKNOWLEDGE_TIME, OUTCOME_TIME, 
        FIRST_RESERVATION_TIME, CURRENT_RESERVATION_TIME
    )
    SELECT 
        ROW_ID, SUBJECT_ID, HADM_ID, SUBMIT_WARD_ID, SUBMIT_CARE_UNIT, 
        CURR_WARD_ID, CURR_CARE_UNIT, CALLOUT_WARD_ID, CALLOUT_SERVICE, 
        CALLOUT_STATUS, CALLOUT_OUTCOME, DISCHARGE_WARD_ID, ACKNOWLEDGE_STATUS, 
        CREATE_TIME, UPDATE_TIME, ACKNOWLEDGE_TIME, OUTCOME_TIME, 
        FIRST_RESERVATION_TIME, CURRENT_RESERVATION_TIME
    FROM Hospital.Clinic.CALLOUT
    WHERE CREATE_TIME > @LastCalloutTime;

    SET @Affected_Row_Number = @@ROWCOUNT;

    EXEC Stage.sp_Insert_ETL_Log
        @Procedure_Name = 'Stage.sp_Load_CALLOUT',
        @Action_Name = 'INCREMENTAL LOAD',
        @Object_Name = 'Stage.Clinic_CALLOUT',
        @Affected_Row_Number = @Affected_Row_Number;
END;
GO

-- INCREMENTAL LOAD: Clinic TRANSFERS (Filtering by ROW_ID)
CREATE PROCEDURE Stage.sp_Load_TRANSFERS
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Affected_Row_Number INT = 0;
    DECLARE @MaxTransferRowID INT;
    SELECT @MaxTransferRowID = ISNULL(MAX(ROW_ID), 0) FROM Stage.Clinic_TRANSFERS;

    INSERT INTO Stage.Clinic_TRANSFERS (
        ROW_ID, SUBJECT_ID, HADM_ID, ICU_STAY_ID, DB_SOURCE, EVENT_TYPE, 
        PREV_CAREUNIT, CURR_CAREUNIT, PREV_WARD_ID, CURR_WARD_ID, 
        IN_TIME, OUT_TIME, LOS
    )
    SELECT 
        ROW_ID, SUBJECT_ID, HADM_ID, ICU_STAY_ID, DB_SOURCE, EVENT_TYPE, 
        PREV_CAREUNIT, CURR_CAREUNIT, PREV_WARD_ID, CURR_WARD_ID, 
        IN_TIME, OUT_TIME, LOS
    FROM Hospital.Clinic.TRANSFERS
    WHERE ROW_ID > @MaxTransferRowID;

    SET @Affected_Row_Number = @@ROWCOUNT;

    EXEC Stage.sp_Insert_ETL_Log
        @Procedure_Name = 'Stage.sp_Load_TRANSFERS',
        @Action_Name = 'INCREMENTAL LOAD',
        @Object_Name = 'Stage.Clinic_TRANSFERS',
        @Affected_Row_Number = @Affected_Row_Number;
END;
GO

-- INCREMENTAL LOAD: ICU INPUT_EVENTS_CV (Filtering by CHART_TIME)
CREATE PROCEDURE Stage.sp_Load_INPUT_EVENTS_CV
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Affected_Row_Number INT = 0;
    DECLARE @LastInputCVTime DATETIME;
    SELECT @LastInputCVTime = ISNULL(MAX(CHART_TIME), '2001-01-01') FROM Stage.ICU_INPUT_EVENTS_CV;

    INSERT INTO Stage.ICU_INPUT_EVENTS_CV (
        ROW_ID, SUBJECT_ID, HADM_ID, ICU_STAY_ID, CHART_TIME, ITEM_ID, 
        AMOUNT, AMOUNT_UOM, RATE, RATE_UOM, CG_ID
    )
    SELECT 
        ROW_ID, SUBJECT_ID, HADM_ID, ICU_STAY_ID, CHART_TIME, ITEM_ID, 
        AMOUNT, AMOUNT_UOM, RATE, RATE_UOM, CG_ID
    FROM Hospital.ICU.INPUT_EVENTS_CV
    WHERE CHART_TIME > @LastInputCVTime;

    SET @Affected_Row_Number = @@ROWCOUNT;

    EXEC Stage.sp_Insert_ETL_Log
        @Procedure_Name = 'Stage.sp_Load_INPUT_EVENTS_CV',
        @Action_Name = 'INCREMENTAL LOAD',
        @Object_Name = 'Stage.ICU_INPUT_EVENTS_CV',
        @Affected_Row_Number = @Affected_Row_Number;
END;
GO

-- INCREMENTAL LOAD: ICU OUTPUT_EVENTS (Filtering by CHART_TIME)
CREATE PROCEDURE Stage.sp_Load_OUTPUT_EVENTS
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Affected_Row_Number INT = 0;
    DECLARE @LastOutputTime DATETIME;
    SELECT @LastOutputTime = ISNULL(MAX(CHART_TIME), '2001-01-01') FROM Stage.ICU_OUTPUT_EVENTS;

    INSERT INTO Stage.ICU_OUTPUT_EVENTS (
        ROW_ID, SUBJECT_ID, HADM_ID, ICU_STAY_ID, CHART_TIME, ITEM_ID, 
        [VALUE], VALUE_UOM, CG_ID
    )
    SELECT 
        ROW_ID, SUBJECT_ID, HADM_ID, ICU_STAY_ID, CHART_TIME, ITEM_ID, 
        [VALUE], VALUE_UOM, CG_ID
    FROM Hospital.ICU.OUTPUT_EVENTS
    WHERE CHART_TIME > @LastOutputTime;

    SET @Affected_Row_Number = @@ROWCOUNT;

    EXEC Stage.sp_Insert_ETL_Log
        @Procedure_Name = 'Stage.sp_Load_OUTPUT_EVENTS',
        @Action_Name = 'INCREMENTAL LOAD',
        @Object_Name = 'Stage.ICU_OUTPUT_EVENTS',
        @Affected_Row_Number = @Affected_Row_Number;
END;
GO

-- INCREMENTAL LOAD: ICU PROCEDURE_EVENTS_MV (Filtering by START_TIME)
CREATE PROCEDURE Stage.sp_Load_PROCEDURE_EVENTS_MV
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Affected_Row_Number INT = 0;
    DECLARE @LastProcMVTime DATETIME;
    SELECT @LastProcMVTime = ISNULL(MAX(START_TIME), '2001-01-01') FROM Stage.ICU_PROCEDURE_EVENTS_MV;

    INSERT INTO Stage.ICU_PROCEDURE_EVENTS_MV (
        ROW_ID, SUBJECT_ID, HADM_ID, ICU_STAY_ID, START_TIME, END_TIME, 
        ITEM_ID, [VALUE], VALUE_UOM, [LOCATION], LOCATION_CATEGORY, CG_ID
    )
    SELECT 
        ROW_ID, SUBJECT_ID, HADM_ID, ICU_STAY_ID, START_TIME, END_TIME, 
        ITEM_ID, [VALUE], VALUE_UOM, [LOCATION], LOCATION_CATEGORY, CG_ID
    FROM Hospital.ICU.PROCEDURE_EVENTS_MV
    WHERE START_TIME > @LastProcMVTime;

    SET @Affected_Row_Number = @@ROWCOUNT;

    EXEC Stage.sp_Insert_ETL_Log
        @Procedure_Name = 'Stage.sp_Load_PROCEDURE_EVENTS_MV',
        @Action_Name = 'INCREMENTAL LOAD',
        @Object_Name = 'Stage.ICU_PROCEDURE_EVENTS_MV',
        @Affected_Row_Number = @Affected_Row_Number;
END;
GO

-- INCREMENTAL LOAD: LAB_EVENTS (Filtering by CHART_TIME)
CREATE PROCEDURE Stage.sp_Load_LAB_EVENTS
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Affected_Row_Number INT = 0;
    DECLARE @LastLabTime DATETIME;
    SELECT @LastLabTime = ISNULL(MAX(CHART_TIME), '2001-01-01') FROM Stage.LAB_EVENTS;

    INSERT INTO Stage.LAB_EVENTS (
        ROW_ID, PATIENT_ID, ADMISSION_ID, ITEM_ID, CHART_TIME, 
        [VALUE], VALUE_NUM, VALUE_UOM, FLAG
    )
    SELECT 
        ROW_ID, PATIENT_ID, ADMISSION_ID, ITEM_ID, CHART_TIME, 
        [VALUE], VALUE_NUM, VALUE_UOM, FLAG
    FROM Laboratory.Lab.LAB_EVENTS
    WHERE CHART_TIME > @LastLabTime;

    SET @Affected_Row_Number = @@ROWCOUNT;

    EXEC Stage.sp_Insert_ETL_Log
        @Procedure_Name = 'Stage.sp_Load_LAB_EVENTS',
        @Action_Name = 'INCREMENTAL LOAD',
        @Object_Name = 'Stage.LAB_EVENTS',
        @Affected_Row_Number = @Affected_Row_Number;
END;
GO

-- Full Load Patients
CREATE PROCEDURE Stage.sp_Load_PATIENTS
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Affected_Row_Number INT = 0;

    TRUNCATE TABLE Stage.Clinic_PATIENTS;
    INSERT INTO Stage.Clinic_PATIENTS (
        ROW_ID, SUBJECT_ID, GENDER, DOB, DOD, EXPIRE_FLAG
    )
    SELECT 
        ROW_ID, SUBJECT_ID, GENDER, DOB, DOD, EXPIRE_FLAG
    FROM Hospital.Clinic.PATIENTS;

    SET @Affected_Row_Number = @@ROWCOUNT;

    EXEC Stage.sp_Insert_ETL_Log
        @Procedure_Name = 'Stage.sp_Load_PATIENTS',
        @Action_Name = 'FULL LOAD',
        @Object_Name = 'Stage.Clinic_PATIENTS',
        @Affected_Row_Number = @Affected_Row_Number;
END;
GO

-- Full Load ICD-9 Diagnoses Dictionary
CREATE PROCEDURE Stage.sp_Load_D_ICD_DIAGNOSES
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Affected_Row_Number INT = 0;

    TRUNCATE TABLE Stage.Clinic_D_ICD_DIAGNOSES;
    INSERT INTO Stage.Clinic_D_ICD_DIAGNOSES (
        ROW_ID, ICD9_CODE, SHORT_TITLE, LONG_TITLE
    )
    SELECT 
        ROW_ID, ICD9_CODE, SHORT_TITLE, LONG_TITLE
    FROM Hospital.Clinic.D_ICD_DIAGNOSES;

    SET @Affected_Row_Number = @@ROWCOUNT;

    EXEC Stage.sp_Insert_ETL_Log
        @Procedure_Name = 'Stage.sp_Load_D_ICD_DIAGNOSES',
        @Action_Name = 'FULL LOAD',
        @Object_Name = 'Stage.Clinic_D_ICD_DIAGNOSES',
        @Affected_Row_Number = @Affected_Row_Number;
END;
GO

-- Full Load Services
CREATE PROCEDURE Stage.sp_Load_SERVICES
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Affected_Row_Number INT = 0;

    TRUNCATE TABLE Stage.Clinic_SERVICES;
    INSERT INTO Stage.Clinic_SERVICES (
        ROW_ID, SUBJECT_ID, HADM_ID, TRANSFER_TIME, PREV_SERVICE, CURR_SERVICE
    )
    SELECT 
        ROW_ID, SUBJECT_ID, HADM_ID, TRANSFER_TIME, PREV_SERVICE, CURR_SERVICE
    FROM Hospital.Clinic.SERVICES;

    SET @Affected_Row_Number = @@ROWCOUNT;

    EXEC Stage.sp_Insert_ETL_Log
        @Procedure_Name = 'Stage.sp_Load_SERVICES',
        @Action_Name = 'FULL LOAD',
        @Object_Name = 'Stage.Clinic_SERVICES',
        @Affected_Row_Number = @Affected_Row_Number;
END;
GO

-- Full Load ICU Items Dictionary
CREATE PROCEDURE Stage.sp_Load_D_ITEMS
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Affected_Row_Number INT = 0;

    TRUNCATE TABLE Stage.ICU_D_ITEMS;
    INSERT INTO Stage.ICU_D_ITEMS (
        ROW_ID, ITEM_ID, LABEL, ABBREVIATION, DB_SOURCE, 
        CATEGORY, UNIT_NAME, PARAM_TYPE 
    )
    SELECT 
        ROW_ID, ITEM_ID, LABEL, ABBREVIATION, DB_SOURCE, 
        CATEGORY, UNIT_NAME, PARAM_TYPE
    FROM Hospital.ICU.D_ITEMS;

    SET @Affected_Row_Number = @@ROWCOUNT;

    EXEC Stage.sp_Insert_ETL_Log
        @Procedure_Name = 'Stage.sp_Load_D_ITEMS',
        @Action_Name = 'FULL LOAD',
        @Object_Name = 'Stage.ICU_D_ITEMS',
        @Affected_Row_Number = @Affected_Row_Number;
END;
GO

-- Full Load Caregivers
CREATE PROCEDURE Stage.sp_Load_CAREGIVERS
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Affected_Row_Number INT = 0;

    TRUNCATE TABLE Stage.ICU_CAREGIVERS;
    INSERT INTO Stage.ICU_CAREGIVERS (
        ROW_ID, CG_ID, LABEL, [DESCRIPTION]
    )
    SELECT 
        ROW_ID, CG_ID, LABEL, [DESCRIPTION]
    FROM Hospital.ICU.CAREGIVERS;

    SET @Affected_Row_Number = @@ROWCOUNT;

    EXEC Stage.sp_Insert_ETL_Log
        @Procedure_Name = 'Stage.sp_Load_CAREGIVERS',
        @Action_Name = 'FULL LOAD',
        @Object_Name = 'Stage.ICU_CAREGIVERS',
        @Affected_Row_Number = @Affected_Row_Number;
END;
GO

-- Full Load: ICU Stays
CREATE PROCEDURE Stage.sp_Load_ICU_STAYS
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Affected_Row_Number INT = 0;

    TRUNCATE TABLE Stage.ICU_STAYS;
    INSERT INTO Stage.ICU_STAYS (
        ROW_ID, SUBJECT_ID, HADM_ID, ICU_STAY_ID, DB_SOURCE, 
        FIRST_CARE_UNIT, LAST_CARE_UNIT, FIRST_WARD_ID, LAST_WARD_ID, 
        IN_TIME, OUT_TIME, LOS
    )
    SELECT 
        ROW_ID, SUBJECT_ID, HADM_ID, ICU_STAY_ID, DB_SOURCE, 
        FIRST_CARE_UNIT, LAST_CARE_UNIT, FIRST_WARD_ID, LAST_WARD_ID, 
        IN_TIME, OUT_TIME, LOS
    FROM Hospital.ICU.ICU_STAYS;

    SET @Affected_Row_Number = @@ROWCOUNT;

    EXEC Stage.sp_Insert_ETL_Log
        @Procedure_Name = 'Stage.sp_Load_ICU_STAYS',
        @Action_Name = 'FULL LOAD',
        @Object_Name = 'Stage.ICU_STAYS',
        @Affected_Row_Number = @Affected_Row_Number;
END;
GO

-- Full Load: Lab Items
CREATE PROCEDURE Stage.sp_Load_D_LAB_ITEMS
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Affected_Row_Number INT = 0;

    TRUNCATE TABLE Stage.D_LAB_ITEMS;
    INSERT INTO Stage.D_LAB_ITEMS (
        ROW_ID, ITEM_ID, LABEL, FLUID, CATEGORY, LOINC_CODE
    )
    SELECT
        ROW_ID, ITEM_ID, LABEL, FLUID, CATEGORY,
        ISNULL(LOINC_CODE, 'Unknown') AS LOINC_CODE
    FROM Laboratory.Lab.D_LAB_ITEMS;

    SET @Affected_Row_Number = @@ROWCOUNT;

    EXEC Stage.sp_Insert_ETL_Log
        @Procedure_Name = 'Stage.sp_Load_D_LAB_ITEMS',
        @Action_Name = 'FULL LOAD',
        @Object_Name = 'Stage.D_LAB_ITEMS',
        @Affected_Row_Number = @Affected_Row_Number;
END;
GO
