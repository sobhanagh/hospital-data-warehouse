CREATE TABLE Fact_Hospital_Admissions (
    Admission_SK INT IDENTITY PRIMARY KEY,
    Admission_ID INT NOT NULL,
    Patient_SK INT NOT NULL,
    Admit_Date_SK INT NOT NULL,
    Disch_Date_SK INT NOT NULL,
    Diagnosis_Group_SK INT NOT NULL,    
    Length_of_Stay_Days DECIMAL(10, 2) NOT NULL,
    Is_Hospital_Mortality BIT NOT NULL,
    Is_Readmission_30_Days BIT NOT NULL,
    Days_Until_Next_Admission DECIMAL(10, 2) NULL,
    Total_ICU_Stays_Count INT NOT NULL,
    Total_Ward_Transfers_Count INT NOT NULL
);

CREATE TABLE Bridge_Diagnosis_Group (
    Diagnosis_Group_SK INT NOT NULL,
    Diagnosis_SK INT NOT NULL,
    ICD9_Code VARCHAR(10) NOT NULL,
    Sequence_Number INT NOT NULL,
    Is_Primary_Diagnosis BIT NOT NULL,
    CONSTRAINT pk_Bridge_Diagnosis_Group PRIMARY KEY (Diagnosis_Group_SK, Diagnosis_SK)
);
