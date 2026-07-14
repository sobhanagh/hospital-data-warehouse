CREATE OR ALTER PROCEDURE sp_Run_Pipeline
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CurrentStep VARCHAR(100);
    DECLARE @ErrorMessage NVARCHAR(MAX);

    PRINT 'STARTING DATA WAREHOUSE MASTER ETL PIPELINE';

    BEGIN TRY

        SET @CurrentStep = 'PHASE 1: Loading Staging Layer';
        PRINT CHAR(13) + '--- ' + @CurrentStep + ' ---';

        PRINT 'Loading Patients (Full)...';
        EXEC DW_Staging.Stage.sp_Load_PATIENTS;

        PRINT 'Loading ICD-9 Diagnoses Dictionary (Full)...';
        EXEC DW_Staging.Stage.sp_Load_D_ICD_DIAGNOSES;

        PRINT 'Loading Services (Full)...';
        EXEC DW_Staging.Stage.sp_Load_SERVICES;

        PRINT 'Loading ICU Items Dictionary (Full)...';
        EXEC DW_Staging.Stage.sp_Load_D_ITEMS;

        PRINT 'Loading Caregivers (Full)...';
        EXEC DW_Staging.Stage.sp_Load_CAREGIVERS;

        PRINT 'Loading ICU Stays (Full)...';
        EXEC DW_Staging.Stage.sp_Load_ICU_STAYS;

        PRINT 'Loading Lab Items Dictionary (Full)...';
        EXEC DW_Staging.Stage.sp_Load_D_LAB_ITEMS;

        PRINT 'Loading Admissions (Incremental)...';
        EXEC DW_Staging.Stage.sp_Load_ADMISSIONS;

        PRINT 'Loading Diagnoses ICD (Incremental)...';
        EXEC DW_Staging.Stage.sp_Load_DIAGNOSES_ICD;

        PRINT 'Loading ICU Input Events MV (Incremental)...';
        EXEC DW_Staging.Stage.sp_Load_INPUT_EVENTS_MV;

        PRINT 'Loading ICU Input Events CV (Incremental)...';
        EXEC DW_Staging.Stage.sp_Load_INPUT_EVENTS_CV;

        PRINT 'Loading ICU Output Events (Incremental)...';
        EXEC DW_Staging.Stage.sp_Load_OUTPUT_EVENTS;

        PRINT 'Loading ICU Procedure Events MV (Incremental)...';
        EXEC DW_Staging.Stage.sp_Load_PROCEDURE_EVENTS_MV;

        PRINT 'Loading Clinic Callout (Incremental)...';
        EXEC DW_Staging.Stage.sp_Load_CALLOUT;

        PRINT 'Loading Clinic Transfers (Incremental)...';
        EXEC DW_Staging.Stage.sp_Load_TRANSFERS;

        PRINT 'Loading Lab Events (Incremental)...';
        EXEC DW_Staging.Stage.sp_Load_LAB_EVENTS;

        SET @CurrentStep = 'PHASE 2: Loading Dimensions';
        PRINT CHAR(13) + '--- ' + @CurrentStep + ' ---';

        PRINT 'Loading Dim_Diagnosis...';
        EXEC dbo.sp_Load_Dim_Diagnosis;

        PRINT 'Loading Dim_Patient...';
        EXEC dbo.sp_Load_Dim_Patient;

        PRINT 'Loading Dim_Caregiver...';
        EXEC dbo.sp_Load_Dim_Caregiver;

        PRINT 'Loading Dim_Lab_Items...';
        EXEC dbo.sp_Load_Dim_Lab_Items;

        PRINT 'Loading Dim_Facility...';
        EXEC dbo.sp_Load_Dim_Facility;

        SET @CurrentStep = 'PHASE 3: Loading Fact & Bridge Tables';
        PRINT CHAR(13) + '--- ' + @CurrentStep + ' ---';

        PRINT 'Loading Fact_Hospital_Admissions...';
        EXEC dbo.sp_Load_Fact_Hospital_Admissions;
    
        PRINT 'Loading Bridge_Diagnosis_Group...';
        EXEC dbo.sp_Load_Bridge_Diagnosis_Group;

        PRINT 'Loading Fact_ICU_Bed_Coordination...';
        EXEC dbo.sp_Load_Fact_ICU_Bed_Coordination;

        PRINT 'Loading Fact_Lab_Event...';
        EXEC dbo.Load_Fact_Lab_Event;

        PRINT 'Loading Fact_Daily_ICU_Status...';
        EXEC dbo.Load_Fact_Daily_ICU_Status;

        PRINT 'Loading Fact_ICU_Clinical_Journey...';
        EXEC dbo.Load_Fact_ICU_Clinical_Journey;

        PRINT 'PIPELINE EXECUTED SUCCESSFULLY!';

    END TRY
    BEGIN CATCH
        SET @ErrorMessage = 'FATAL ERROR during [' + @CurrentStep + ']: ' + ERROR_MESSAGE();

        PRINT 'PIPELINE FAILED!';
        PRINT @ErrorMessage;

        THROW;
    END CATCH
END;
GO
