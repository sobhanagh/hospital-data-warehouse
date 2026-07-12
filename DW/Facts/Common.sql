CREATE TABLE ETL_Control (
    Table_Name VARCHAR(100) NOT NULL PRIMARY KEY,
    Last_Processed_ID INT NOT NULL DEFAULT 0,
    Last_Run_Status VARCHAR(20) NOT NULL, -- 'SUCCESS', 'FAILED'
    Last_Run_Timestamp DATETIME DEFAULT GETDATE(),
    Last_Processed_Date DATE,
    Error_Message TEXT
);
