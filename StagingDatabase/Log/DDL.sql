CREATE TABLE Stage.ETL_Log (
    Log_ID BIGINT IDENTITY(1,1) PRIMARY KEY,
    Procedure_Name VARCHAR(255) NOT NULL,
    Action_Name VARCHAR(50) NOT NULL,
    Object_Name VARCHAR(255) NOT NULL,
    Execution_DateTime DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    Affected_Row_Number INT NOT NULL DEFAULT 0
);
GO

CREATE PROCEDURE Stage.sp_Insert_ETL_Log
(
    @Procedure_Name VARCHAR(255),
    @Action_Name VARCHAR(50),
    @Object_Name VARCHAR(255),
    @Affected_Row_Number INT = 0
)
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO Stage.ETL_Log
    (
        Procedure_Name,
        Action_Name,
        Object_Name,
        Affected_Row_Number
    )
    VALUES
    (
        @Procedure_Name,
        @Action_Name,
        @Object_Name,
        @Affected_Row_Number
    );
END;
