
-- Transaction

CREATE TABLE Fact_LabTest_Result (
    Fact_ID BIGINT IDENTITY PRIMARY KEY,

    -- Foreign Keys (Dimensions)
    Patient_Key INT,
    Admission_Key INT,
    LabItem_Key INT,
    Date_Key INT,

    -- Degenerate Dimension
    Event_ID INT, -- from ROW_ID

    -- Measures
    Value_Num DOUBLE PRECISION,
    
    -- Flags
    Is_Abnormal BIT
);


-- Periodic

CREATE TABLE Fact_LabTest_DailySnapshot (
    Snapshot_ID BIGINT IDENTITY PRIMARY KEY,

    -- Foreign Keys (Dimensions)
    Patient_Key INT,
    LabItem_Key INT,
    Date_Key INT,

    -- Aggregated Measures
    Total_Tests INT,
    Avg_Value DOUBLE PRECISION,
    Min_Value DOUBLE PRECISION,
    Max_Value DOUBLE PRECISION,
    Abnormal_Count INT
);

CREATE TABLE Fact_LabTest_DailyPopulationSummary (
    Snapshot_ID BIGINT IDENTITY PRIMARY KEY,

    -- Foreign Keys (Dimensions)
    LabItem_Key INT,
    Date_Key INT,

    -- Aggregated Measures
    Total_Tests INT,              -- total number of tests performed
    Patient_Count INT,            -- distinct patients tested
    Avg_Value DOUBLE PRECISION,   -- average value across all tests
    Min_Value DOUBLE PRECISION,   -- lowest value observed
    Max_Value DOUBLE PRECISION,   -- highest value observed
    Abnormal_Count INT,           -- number of abnormal results

    Extract_DateTime DATETIME
);

-- Accumulating

CREATE TABLE Fact_LabTest_History (
    Lifecycle_ID BIGINT IDENTITY PRIMARY KEY,

    -- Foreign Keys (Dimensions)
    Patient_Key INT,
    LabItem_Key INT,

    -- Milestone Dates
    First_Test_Date_Key INT,
    Last_Test_Date_Key INT,

    -- Metrics
    Total_Tests INT,
    Days_Between_First_Last INT
);