CREATE PROCEDURE sp_Initialize_Dimensions
AS
BEGIN
    SET NOCOUNT ON;

    SET IDENTITY_INSERT Dim_Patient ON;
    INSERT INTO Dim_Patient (Patient_SK, Patient_ID, Gender, Date_Of_Birth, Ethnicity, Date_Of_Death, Insurance)
    VALUES (-1, -1, 'Unk', NULL, 'Unknown', NULL, 'Unknown');
    SET IDENTITY_INSERT Dim_Patient OFF;

    SET IDENTITY_INSERT Dim_Diagnosis ON;
    INSERT INTO Dim_Diagnosis (Diagnosis_SK, ICD9_CODE, Short_Title, Long_Title)
    VALUES (-1, 'Unk', 'Unknown', 'Unknown Diagnosis Code');
    SET IDENTITY_INSERT Dim_Diagnosis OFF;

    SET IDENTITY_INSERT Dim_Caregiver ON;
    INSERT INTO Dim_Caregiver (Caregiver_SK, Caregiver_ID, Label, [Description], ValidFrom, ValidTo, IsCurrent)
    VALUES (-1, -1, 'Unknown', 'Unknown Caregiver', '1900-01-01', '9999-12-31', 1);
    SET IDENTITY_INSERT Dim_Caregiver OFF;

    SET IDENTITY_INSERT Dim_Clinical_Item ON;
    INSERT INTO Dim_Clinical_Item (Item_SK, ITEM_ID, Item_Type, Label, Abbreviation, Category, DB_Source, LOINC_Code, Fluid)
    VALUES (-1, -1, 'Unknown', 'Unknown Item', 'Unk', 'Unknown', 'Unknown', NULL, NULL);
    SET IDENTITY_INSERT Dim_Clinical_Item OFF;

    SET IDENTITY_INSERT Dim_Facility ON;
    INSERT INTO Dim_Facility (Facility_SK, Ward_ID, Care_Unit, ValidFrom, ValidTo, IsCurrent)
    VALUES (-1, -1, 'Unknown', '1900-01-01', '9999-12-31', 1);
    SET IDENTITY_INSERT Dim_Facility OFF;

    SET IDENTITY_INSERT Dim_Lab_Items ON;
    INSERT INTO Dim_Lab_Items (LabTest_Key, Item_ID, Label, Fluid, Category, LOINC_Code, ValidFrom, ValidTo, IsCurrent)
    VALUES (-1, -1, 'Unknown', 'Unknown', 'Unknown', 'Unknown', '1900-01-01', '9999-12-31', 1);
    SET IDENTITY_INSERT Dim_Lab_Items OFF;

    DECLARE @StartDate DATETIME = '2001-01-01';
    DECLARE @EndDate DATETIME = '2013-12-31';

    WHILE @StartDate <= @EndDate
    BEGIN
        INSERT INTO Dim_Date
        SELECT 
            CAST(FORMAT(@StartDate, 'yyyyMMdd') AS INT) AS Date_SK,
            @StartDate,
            YEAR(@StartDate),
            DATEPART(qq, @StartDate),
            MONTH(@StartDate),
            DATENAME(mm, @StartDate),
            DAY(@StartDate),
            DATEPART(dw, @StartDate),
            DATENAME(dw, @StartDate),
            CASE WHEN DATEPART(dw, @StartDate) IN (1, 7) THEN 1 ELSE 0 END;

        SET @StartDate = DATEADD(dd, 1, @StartDate);
    END;

END;
GO

CREATE PROCEDURE sp_Load_Dim_Diagnosis
AS
BEGIN
    SET NOCOUNT ON;

    MERGE Dim_Diagnosis AS Target
    USING (
        SELECT DISTINCT
            ICD9_CODE, 
            SHORT_TITLE, 
            LONG_TITLE
        FROM DW_Staging.Stage.Clinic_D_ICD_DIAGNOSES
    ) AS Source
    ON Target.ICD9_CODE = Source.ICD9_CODE

    WHEN MATCHED AND (
        ISNULL(Target.Short_Title, '') <> ISNULL(Source.SHORT_TITLE, '') OR
        ISNULL(Target.Long_Title, '') <> ISNULL(Source.LONG_TITLE, '')
    ) THEN 
        UPDATE SET 
            Target.Short_Title = Source.SHORT_TITLE,
            Target.Long_Title = Source.LONG_TITLE

    WHEN NOT MATCHED BY TARGET THEN 
        INSERT (ICD9_CODE, Short_Title, Long_Title)
        VALUES (Source.ICD9_CODE, Source.SHORT_TITLE, Source.LONG_TITLE);

END;
GO

CREATE PROCEDURE sp_Load_Dim_Patient
AS
BEGIN
    SET NOCOUNT ON;

    WITH SourceData AS (
        SELECT 
            p.SUBJECT_ID,
            p.GENDER,
            p.DOB,
            p.DOD,
            latest_adm.INSURANCE,
            latest_adm.ETHNICITY
        FROM DW_Staging.Stage.Clinic_PATIENTS p
        OUTER APPLY (
            SELECT TOP 1 adm.INSURANCE, adm.ETHNICITY 
            FROM DW_Staging.Stage.Clinic_ADMISSIONS adm 
            WHERE adm.SUBJECT_ID = p.SUBJECT_ID 
            ORDER BY adm.ADMIT_TIME DESC
        ) latest_adm
    )
    MERGE Dim_Patient AS Target
    USING SourceData AS Source
    ON Target.Patient_ID = Source.SUBJECT_ID 

    WHEN MATCHED AND (
        ISNULL(Target.Gender, '') <> ISNULL(Source.GENDER, '') OR
        ISNULL(Target.Date_Of_Birth, '1900-01-01') <> ISNULL(Source.DOB, '1900-01-01') OR
        ISNULL(Target.Insurance, '') <> ISNULL(Source.INSURANCE, '') OR
        ISNULL(Target.Date_Of_Death, '1900-01-01') <> ISNULL(Source.DOD, '1900-01-01') OR
        ISNULL(Target.Ethnicity, '') <> ISNULL(Source.ETHNICITY, '')
    ) THEN 
        UPDATE SET 
            Target.Gender = Source.GENDER,
            Target.Date_Of_Birth = Source.DOB,
            Target.Insurance = Source.INSURANCE,
            Target.Date_Of_Death = Source.DOD,
            Target.Ethnicity = Source.ETHNICITY

    WHEN NOT MATCHED BY TARGET THEN
        INSERT (Patient_ID, Gender, Date_Of_Birth, Insurance, Date_Of_Death, Ethnicity)
        VALUES (Source.SUBJECT_ID, CASE Source.GENDER WHEN 'M' THEN 'Male' WHEN 'F' THEN 'Female' ELSE 'Unk' END, Source.DOB, Source.INSURANCE, Source.DOD, Source.ETHNICITY);

END;
GO

CREATE PROCEDURE sp_Load_Dim_Caregiver
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ProcessDate DATETIME = GETDATE();

    DECLARE @Type2Changes TABLE (
        Action_Type VARCHAR(20),
        CG_ID INT,
        Label VARCHAR(15),
        Description VARCHAR(30)
    );

    MERGE Dim_Caregiver AS Target
    USING DW_Staging.Stage.ICU_CAREGIVERS AS Source
    ON Target.Caregiver_ID = Source.CG_ID 

    WHEN MATCHED AND Target.IsCurrent = 1 AND (
        ISNULL(Target.Label, '') <> ISNULL(Source.LABEL, '') OR
        ISNULL(Target.Description, '') <> ISNULL(Source.[DESCRIPTION], '')
    ) THEN 
        UPDATE SET 
            Target.IsCurrent = 0,
            Target.ValidTo = @ProcessDate

    WHEN NOT MATCHED BY TARGET THEN
        INSERT (Caregiver_ID, Label, Description, ValidFrom, ValidTo, IsCurrent)
        VALUES (Source.CG_ID, Source.LABEL, Source.[DESCRIPTION], @ProcessDate, '9999-12-31', 1)

    OUTPUT 
        $action AS Action_Type, 
        Source.CG_ID, 
        Source.LABEL, 
        Source.[DESCRIPTION]
    INTO @Type2Changes;

    INSERT INTO Dim_Caregiver (Caregiver_ID, Label, Description, ValidFrom, ValidTo, IsCurrent)
    SELECT 
        CG_ID, Label, Description, @ProcessDate, '9999-12-31', 1
    FROM @Type2Changes
    WHERE Action_Type = 'UPDATE'; 

END;
GO

CREATE PROCEDURE sp_Load_Dim_Lab_Items
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ProcessDate DATETIME = GETDATE();

    -- Temp table to track changes (for SCD Type 2)
    DECLARE @Changes TABLE (
        Action_Type VARCHAR(20),
        Item_ID INT,
        Label VARCHAR(200),
        Fluid VARCHAR(100),
        Category VARCHAR(100),
        LOINC_Code VARCHAR(100)
    );

    MERGE Dim_Lab_Items AS Target
    USING (
        SELECT DISTINCT
            ITEM_ID,
            LABEL,
            FLUID,
            CATEGORY,
            LOINC_CODE
        FROM DW_Staging.Stage.D_LAB_ITEMS
    ) AS Source
    ON Target.Item_ID = Source.ITEM_ID
       AND Target.IsCurrent = 1

    -- SCD Type 2 change detection
    WHEN MATCHED AND (
        ISNULL(Target.Label, '') <> ISNULL(Source.LABEL, '') OR
        ISNULL(Target.Fluid, '') <> ISNULL(Source.FLUID, '') OR
        ISNULL(Target.Category, '') <> ISNULL(Source.CATEGORY, '') OR
        ISNULL(Target.LOINC_Code, '') <> ISNULL(Source.LOINC_CODE, '')
    )
    THEN 
        UPDATE SET 
            Target.IsCurrent = 0,
            Target.ValidTo = @ProcessDate

    -- New records
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (
            Item_ID, Label, Fluid, Category, LOINC_Code,
            ValidFrom, ValidTo, IsCurrent
        )
        VALUES (
            Source.ITEM_ID,
            Source.LABEL,
            Source.FLUID,
            Source.CATEGORY,
            Source.LOINC_CODE,
            @ProcessDate,
            '9999-12-31',
            1
        )

    OUTPUT 
        $action,
        Source.ITEM_ID,
        Source.LABEL,
        Source.FLUID,
        Source.CATEGORY,
        Source.LOINC_CODE,
    INTO @Changes;

    -- Insert new version for updated rows
    INSERT INTO Dim_Lab_Items (
        Item_ID, Label, Fluid, Category, LOINC_Code,
        ValidFrom, ValidTo, IsCurrent
    )
    SELECT
        Item_ID,
        Label,
        Fluid,
        Category,
        LOINC_Code,
        @ProcessDate,
        '9999-12-31',
        1
    FROM @Changes
    WHERE Action_Type = 'UPDATE';

END;
GO