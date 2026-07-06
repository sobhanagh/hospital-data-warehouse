-- Define data set directory variable here
DECLARE @DataDir NVARCHAR(255) = '';

DECLARE @Clinic_Tables TABLE (ID INT IDENTITY(1,1), TableName NVARCHAR(100));
DECLARE @ICU_Tables TABLE (ID INT IDENTITY(1,1), TableName NVARCHAR(100));

INSERT INTO @Clinic_Tables (TableName) VALUES
('ADMISSIONS'), ('CALLOUT'), ('CPT_EVENTS'),
('DIAGNOSES_ICD'), ('DRG_CODES'), ('D_CPT'), ('D_ICD_DIAGNOSES'),
('D_ICD_PROCEDURES'), ('MICROBIOLOGY_EVENTS'), ('PATIENTS'),
('PRESCRIPTIONS'), ('PROCEDURES_ICD'), ('SERVICES'),
('TRANSFERS');

INSERT INTO @ICU_Tables (TableName) VALUES
('CAREGIVERS'), ('DATETIME_EVENTS'), ('D_ITEMS'),
('ICU_STAYS'), ('INPUT_EVENTS_CV'), ('INPUT_EVENTS_MV'),
('OUTPUT_EVENTS'), ('PROCEDURE_EVENTS_MV');

DECLARE @LoopID INT = 1;
DECLARE @MaxID INT = (SELECT MAX(ID) FROM @Clinic_Tables);
DECLARE @CurrentTable NVARCHAR(100);
DECLARE @DynamicSQL NVARCHAR(MAX);

WHILE @LoopID <= @MaxID
BEGIN
    SELECT @CurrentTable = TableName FROM @Clinic_Tables WHERE ID = @LoopID;
    
    SET @DynamicSQL = N'
        PRINT ''Loading table: ' + @CurrentTable + N'...''
        BULK INSERT ' + 'Clinic.' + @CurrentTable + N'
        FROM ''' + @DataDir + @CurrentTable + N'.csv''
        WITH (
            FORMAT = ''CSV'',
            FIRSTROW = 2,
            FIELDTERMINATOR = '','',
            ROWTERMINATOR = ''0x0a'',
            KEEPNULLS
        );';
        
    EXEC sp_executesql @DynamicSQL;
    
    SET @LoopID = @LoopID + 1;
END

SET @LoopID = 1;
SET @MaxID = (SELECT MAX(ID) FROM @ICU_Tables);

WHILE @LoopID <= @MaxID
BEGIN
    SELECT @CurrentTable = TableName FROM @ICU_Tables WHERE ID = @LoopID;
    
    SET @DynamicSQL = N'
        PRINT ''Loading table: ' + @CurrentTable + N'...''
        BULK INSERT ' + 'ICU.' + @CurrentTable + N'
        FROM ''' + @DataDir + @CurrentTable + N'.csv''
        WITH (
            FORMAT = ''CSV'',
            FIRSTROW = 2,
            FIELDTERMINATOR = '','',
            ROWTERMINATOR = ''0x0a'',
            KEEPNULLS
        );';
        
    EXEC sp_executesql @DynamicSQL;
    
    SET @LoopID = @LoopID + 1;
END

PRINT 'All data loaded successfully!';
