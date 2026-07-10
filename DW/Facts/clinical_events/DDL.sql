
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
