/*
Wersja docelowa: 118
audyt zmian danych firmowych

Założenia:
    - migracja podnosi wersję bazy firmowej z 117 do 118;
    - tComAuditLog znajduje się w tej samej bazie co zmieniane tabele, dzięki czemu wpis audytowy
      może zostać zapisany w tej samej transakcji co operacja biznesowa;
    - czas jest zapisywany w UTC jako datetime2(3);
    - Operation przyjmuje INSERT, UPDATE albo DELETE;
    - YearCode dopuszcza NULL, ponieważ ustawienia Bankyera nie zawsze zależą od roku;
    - istniejące rekordy otrzymują RevisionID = 1, ale nie dostają sztucznej daty ani autora utworzenia;
    - dziennik jest append-only i nie powinien być obsługiwany przez standardowy CRUD;
    - skrypt nie usuwa ani nie archiwizuje wpisów audytowych.

*/

SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @TargetDBVersion int = 118;

DECLARE @Tables table
(
    TableName sysname NOT NULL PRIMARY KEY
);

INSERT INTO @Tables (TableName)
VALUES
    (N'tBanTransTypeMapping'),
    (N'tBanTransTypeMappingDet'),
    (N'tBanAccNo2CustCode'),
    (N'tBanCommonPhrasesConv'),
    (N'tBanAccount2User');

IF EXISTS
(
    SELECT 1
    FROM @Tables t
    WHERE OBJECT_ID(N'dbo.' + t.TableName, N'U') IS NULL
)
BEGIN
    THROW 50002, N'Brak co najmniej jednej wymaganej tabeli Bankyera. Migracja nie została rozpoczęta.', 1;
END;

IF OBJECT_ID(N'dbo.tComAuditLog', N'U') IS NOT NULL
BEGIN
    THROW 50003, N'Tabela tComAuditLog już istnieje przy wersji bazy niższej niż 118. Sprawdź niepełną migrację.', 1;
END;

BEGIN TRY
    CREATE TABLE dbo.tComAuditLog
    (
        AuditLogID bigint IDENTITY(1,1) NOT NULL,
        ChangedOn datetime2(3) NOT NULL
            CONSTRAINT DF_tComAuditLog_ChangedOn DEFAULT SYSUTCDATETIME(),
        ChangedByUserID int NULL,
        ChangedBy nvarchar(15) NOT NULL,
        CompCode nvarchar(8) NOT NULL,
        YearCode int NULL,
        TableName nvarchar(128) NOT NULL,
        RecordKey nvarchar(1000) NOT NULL,
        Operation varchar(10) NOT NULL,
        BeforeData nvarchar(max) NULL,
        AfterData nvarchar(max) NULL,
        HttpMethod varchar(10) NULL,
        RequestPath nvarchar(512) NULL,
        TraceID nvarchar(64) NULL,

        CONSTRAINT PK_tComAuditLog PRIMARY KEY CLUSTERED (AuditLogID),
        CONSTRAINT CK_tComAuditLog_Operation
            CHECK (Operation IN ('INSERT', 'UPDATE', 'DELETE')),
        CONSTRAINT CK_tComAuditLog_RecordKeyJson
            CHECK (ISJSON(RecordKey) = 1),
        CONSTRAINT CK_tComAuditLog_BeforeDataJson
            CHECK (BeforeData IS NULL OR ISJSON(BeforeData) = 1),
        CONSTRAINT CK_tComAuditLog_AfterDataJson
            CHECK (AfterData IS NULL OR ISJSON(AfterData) = 1)
    );

    CREATE INDEX IX_tComAuditLog_ChangedOn
        ON dbo.tComAuditLog (ChangedOn DESC);
    CREATE INDEX IX_tComAuditLog_CompCode_ChangedOn
        ON dbo.tComAuditLog (CompCode, ChangedOn DESC);
    CREATE INDEX IX_tComAuditLog_TableName_ChangedOn
        ON dbo.tComAuditLog (TableName, ChangedOn DESC);
    CREATE INDEX IX_tComAuditLog_ChangedByUserID_ChangedOn
        ON dbo.tComAuditLog (ChangedByUserID, ChangedOn DESC)
        WHERE ChangedByUserID IS NOT NULL;
    CREATE INDEX IX_tComAuditLog_TraceID
        ON dbo.tComAuditLog (TraceID)
        WHERE TraceID IS NOT NULL;

    DECLARE @TableName sysname;
    DECLARE @Sql nvarchar(max);

    DECLARE audit_columns_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT TableName FROM @Tables ORDER BY TableName;

    OPEN audit_columns_cursor;
    FETCH NEXT FROM audit_columns_cursor INTO @TableName;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @Sql = N'';

        IF COL_LENGTH(N'dbo.' + @TableName, N'CreatedOn') IS NULL
            SET @Sql += N'ALTER TABLE dbo.' + QUOTENAME(@TableName) + N' ADD CreatedOn datetime2(3) NULL;';
        IF COL_LENGTH(N'dbo.' + @TableName, N'CreatedBy') IS NULL
            SET @Sql += N'ALTER TABLE dbo.' + QUOTENAME(@TableName) + N' ADD CreatedBy nvarchar(15) NULL;';
        IF COL_LENGTH(N'dbo.' + @TableName, N'UpdatedOn') IS NULL
            SET @Sql += N'ALTER TABLE dbo.' + QUOTENAME(@TableName) + N' ADD UpdatedOn datetime2(3) NULL;';
        IF COL_LENGTH(N'dbo.' + @TableName, N'UpdatedBy') IS NULL
            SET @Sql += N'ALTER TABLE dbo.' + QUOTENAME(@TableName) + N' ADD UpdatedBy nvarchar(15) NULL;';
        IF COL_LENGTH(N'dbo.' + @TableName, N'RevisionID') IS NULL
            SET @Sql += N'ALTER TABLE dbo.' + QUOTENAME(@TableName)
                + N' ADD RevisionID int NOT NULL CONSTRAINT '
                + QUOTENAME(N'DF_' + @TableName + N'_RevisionID') + N' DEFAULT (1) WITH VALUES;';

        IF @Sql <> N''
            EXEC sys.sp_executesql @Sql;

        FETCH NEXT FROM audit_columns_cursor INTO @TableName;
    END;

    CLOSE audit_columns_cursor;
    DEALLOCATE audit_columns_cursor;

    UPDATE dbo.tSysDBVersion
    SET VersionID = @TargetDBVersion;

    IF @@ROWCOUNT <> 1
        THROW 50004, N'Nie udało się jednoznacznie zaktualizować wersji bazy.', 1;

    PRINT N'Audyt danych firmowych został zainstalowany. Wersja bazy: 118.';
END TRY
BEGIN CATCH
    IF CURSOR_STATUS('local', 'audit_columns_cursor') >= 0
        CLOSE audit_columns_cursor;
    IF CURSOR_STATUS('local', 'audit_columns_cursor') >= -1
        DEALLOCATE audit_columns_cursor;
    THROW;
END CATCH;
