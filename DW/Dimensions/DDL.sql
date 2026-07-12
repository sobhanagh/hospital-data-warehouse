CREATE TABLE Dim_Date (
    Date_SK INT PRIMARY KEY,
    FullDate DATETIME NOT NULL,
    [Year] INT NOT NULL,
    [Quarter] INT NOT NULL,
    [Month] INT NOT NULL,
    MonthName VARCHAR(15) NOT NULL,
    [Day] INT NOT NULL,
    DayOfWeek INT NOT NULL,
    DayName VARCHAR(15) NOT NULL,
    IsWeekend BIT NOT NULL
);

CREATE TABLE Dim_Patient (
    Patient_SK INT IDENTITY NOT NULL PRIMARY KEY,
    Patient_ID INT NOT NULL,
    Gender VARCHAR(10),
    Ethnicity VARCHAR(200),
    Insurance VARCHAR(255),
    Date_Of_Birth DATETIME,
    Date_Of_Death DATETIME
);

CREATE TABLE Dim_Diagnosis (
    Diagnosis_SK INT IDENTITY NOT NULL PRIMARY KEY,
    ICD9_CODE VARCHAR(10) NOT NULL,
    Short_Title VARCHAR(50),
    Long_Title VARCHAR(255)
);

CREATE TABLE Dim_Caregiver (
    Caregiver_SK INT IDENTITY NOT NULL PRIMARY KEY,
    Caregiver_ID INT NOT NULL,
    Label VARCHAR(15),
    [Description] VARCHAR(30),
    ValidFrom DATETIME NOT NULL,
    ValidTo DATETIME NOT NULL,
    IsCurrent BIT NOT NULL
);

CREATE TABLE Dim_Clinical_Item (
    Item_SK INT IDENTITY NOT NULL PRIMARY KEY,
    ITEM_ID INT NOT NULL,
    Item_Type VARCHAR(20) NOT NULL, -- ICU or LAB
    Label VARCHAR(200),
    Abbreviation VARCHAR(100),
    Category VARCHAR(100),
    DB_Source VARCHAR(20),
    LOINC_Code VARCHAR(100),
    Fluid VARCHAR(100)
);

CREATE TABLE Dim_Facility (
    Facility_SK INT IDENTITY NOT NULL PRIMARY KEY,
    Ward_ID SMALLINT NOT NULL,
    Care_Unit VARCHAR(20) NOT NULL,
);

CREATE TABLE Dim_Lab_Items (
    LabTest_Key INT IDENTITY PRIMARY KEY,  
    Item_ID INT NOT NULL,
    Label VARCHAR(200),
    Fluid VARCHAR(100),
    Category VARCHAR(100),
    LOINC_Code VARCHAR(100),
    Extract_DateTime DATETIME,
    ValidFrom DATETIME NOT NULL,
    ValidTo DATETIME NOT NULL,
    IsCurrent BIT NOT NULL
);