
-- Transactional

CREATE TABLE Fact_Lab_Event (
    Lab_Event_SK BIGINT IDENTITY PRIMARY KEY,

    Date_SK INT NOT NULL,
    Patient_SK INT NOT NULL,
    LabTest_SK INT NOT NULL,
    Admission_ID INT,
    
    Value_Num FLOAT,
    Value_Text VARCHAR(200),
    Value_Unit VARCHAR(20),
    Flag VARCHAR(20),

    CONSTRAINT FK_Lab_Date FOREIGN KEY (Date_SK) REFERENCES Dim_Date(Date_SK),
    CONSTRAINT FK_Lab_Patient FOREIGN KEY (Patient_SK) REFERENCES Dim_Patient(Patient_SK),
    CONSTRAINT FK_Lab_Item FOREIGN KEY (LabTest_SK) REFERENCES Dim_Lab_Items(LabTest_Key)
);


-- Periodic

CREATE TABLE Fact_Daily_ICU_Status (
    Snapshot_SK BIGINT IDENTITY PRIMARY KEY,

    Date_SK INT NOT NULL,
    Patient_SK INT NOT NULL,
    ICU_Stay_ID INT NOT NULL,

    Fluid_Input_ml FLOAT,
    Blood_Input_ml FLOAT,

    Urine_Output_ml FLOAT,
    Drain_Output_ml FLOAT,

    Total_Input_ml FLOAT,
    Total_Output_ml FLOAT,

    Net_Fluid_ml FLOAT, -- Total_Input_ml - Total_Output_ml

    LOS_ICU_Day INT,

    CONSTRAINT FK_Fluid_Date FOREIGN KEY (Date_SK) REFERENCES Dim_Date(Date_SK),
    CONSTRAINT FK_Fluid_Patient FOREIGN KEY (Patient_SK) REFERENCES Dim_Patient(Patient_SK)
);


-- Accumulating

CREATE TABLE Fact_ICU_Clinical_Journey (
    ICU_Stay_ID INT PRIMARY KEY,

    Patient_SK INT NOT NULL,
    Admit_Date_SK INT NOT NULL,

    -- Timeline
    ICU_Admit_Time DATETIME,
    Vent_Start_Time DATETIME,
    Vent_End_Time DATETIME,
    First_Antibiotic_Time DATETIME,
    First_Culture_Time DATETIME,
    Dialysis_Start_Time DATETIME,
    ICU_Discharge_Time DATETIME,

    -- Measure
    -- Durations 
    Time_To_Vent_Hours FLOAT, -- Vent_Start_Time - ICU_Admit_Time
    Vent_Duration_Hours FLOAT, -- Vent_End_Time - Vent_Start_Time
    Time_To_Antibiotic_Hours FLOAT, -- First_Antibiotic_Time - ICU_Admit_Time
    LOS_ICU_Hours FLOAT,

    -- Flags
    Ventilated_Flag INT,
    Sepsis_Suspected_Flag INT,
    Dialysis_Flag INT,

    -- Outcome
    Mortality_Flag INT,

    CONSTRAINT FK_Journey_Patient FOREIGN KEY (Patient_SK) REFERENCES Dim_Patient(Patient_SK),
    CONSTRAINT FK_Journey_Admit_Date FOREIGN KEY (Admit_Date_SK) REFERENCES Dim_Date(Date_SK)
);