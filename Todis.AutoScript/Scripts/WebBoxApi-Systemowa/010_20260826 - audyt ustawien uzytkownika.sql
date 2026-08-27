/*
Wersja docelowa: 10
Założenia:
    - skrypt jest przeznaczony wyłącznie dla bazy systemowej;
    - migracja podnosi wersję bazy systemowej z 9 do 10;
    - rozszerzamy dbo.tSysUserProfileItems o pola CreatedOn, CreatedBy, UpdatedOn, UpdatedBy i RevisionID;
    - istniejące rekordy otrzymują RevisionID = 1;
    - istniejącym rekordom nie przypisujemy sztucznego autora ani daty utworzenia lub aktualizacji,
      ponieważ takich informacji nie da się wiarygodnie odtworzyć;
    - nowe operacje API będą zapisywać pełną historię zmian w istniejącej dbo.tSysAuditLog;
    - nie tworzymy kolejnej tabeli audytowej;
    - transakcją oraz kontrolą wersji zarządza Todis AutoScript;

Co zmienia skrypt:
    - CreatedOn datetime2(3) NULL - data utworzenia w UTC dla nowych zapisów;
    - CreatedBy nvarchar(15) NULL - alias użytkownika tworzącego rekord;
    - UpdatedOn datetime2(3) NULL - data ostatniej aktualizacji w UTC;
    - UpdatedBy nvarchar(15) NULL - alias użytkownika aktualizującego rekord;
    - RevisionID int NOT NULL - numer rewizji używany do ochrony przed nadpisaniem nowszej zmiany.

Rollback całego zestawu obsługuje Todis AutoScript. Skrypt nie usuwa ani nie zmienia istniejących ustawień użytkowników.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @TargetDBVersion int = 10;

IF OBJECT_ID(N'dbo.tSysUserProfileItems', N'U') IS NULL
BEGIN
    THROW 50004, N'Brak tabeli dbo.tSysUserProfileItems. Migracja nie została rozpoczęta.', 1;
END;

-- Korzystamy z dziennika utworzonego w wersji 9. Brak tabeli oznacza niespójny schemat wejściowy.
IF OBJECT_ID(N'dbo.tSysAuditLog', N'U') IS NULL
BEGIN
    THROW 50005, N'Brak tabeli dbo.tSysAuditLog wymaganej do audytu ustawień użytkownika.', 1;
END;

DECLARE @InvalidBaseColumns nvarchar(max);

-- Endpoint korzysta z klucza złożonego i Value_, więc przed zmianą sprawdzamy także bazowy układ tabeli.
;WITH ExpectedBaseColumns AS
(
    SELECT *
    FROM (VALUES
        (N'UserID',        N'int',      CONVERT(smallint, 4),   CONVERT(bit, 0)),
        (N'ProfileItemID', N'int',      CONVERT(smallint, 4),   CONVERT(bit, 0)),
        (N'CompanyID',     N'int',      CONVERT(smallint, 4),   CONVERT(bit, 0)),
        (N'YearCode',      N'int',      CONVERT(smallint, 4),   CONVERT(bit, 0)),
        (N'Value_',        N'nvarchar', CONVERT(smallint, 512), CONVERT(bit, 0))
    ) v (ColumnName, TypeName, MaxLength, IsNullable)
)
SELECT @InvalidBaseColumns = STRING_AGG(e.ColumnName, N', ')
FROM ExpectedBaseColumns e
LEFT JOIN sys.columns c
    ON c.object_id = OBJECT_ID(N'dbo.tSysUserProfileItems')
   AND c.name = e.ColumnName
LEFT JOIN sys.types t
    ON t.user_type_id = c.user_type_id
WHERE c.column_id IS NULL
   OR t.name <> e.TypeName
   OR c.max_length <> e.MaxLength
   OR c.is_nullable <> e.IsNullable;

IF @InvalidBaseColumns IS NOT NULL
BEGIN
    DECLARE @InvalidBaseColumnsMessage nvarchar(2048) =
        N'Brak lub niezgodny typ kolumn bazowych: ' + @InvalidBaseColumns + N'. Migracja nie została rozpoczęta.';
    THROW 50006, @InvalidBaseColumnsMessage, 1;
END;

DECLARE @PrimaryKeyColumns nvarchar(1000);

SELECT @PrimaryKeyColumns = STRING_AGG(CONVERT(nvarchar(max), c.name), N',')
    WITHIN GROUP (ORDER BY ic.key_ordinal)
FROM sys.indexes i
JOIN sys.index_columns ic
    ON ic.object_id = i.object_id
   AND ic.index_id = i.index_id
JOIN sys.columns c
    ON c.object_id = ic.object_id
   AND c.column_id = ic.column_id
WHERE i.object_id = OBJECT_ID(N'dbo.tSysUserProfileItems')
  AND i.is_primary_key = 1;

IF @PrimaryKeyColumns IS NULL
   OR @PrimaryKeyColumns <> N'UserID,ProfileItemID,CompanyID,YearCode'
BEGIN
    THROW 50007, N'Niezgodny klucz główny dbo.tSysUserProfileItems. Oczekiwano UserID, ProfileItemID, CompanyID, YearCode.', 1;
END;

DECLARE @ExpectedColumns table
(
    ColumnName sysname NOT NULL PRIMARY KEY,
    TypeName sysname NOT NULL,
    MaxLength smallint NULL,
    Scale tinyint NULL,
    IsNullable bit NOT NULL
);

INSERT INTO @ExpectedColumns (ColumnName, TypeName, MaxLength, Scale, IsNullable)
VALUES
    (N'CreatedOn',  N'datetime2', NULL, 3,    1),
    (N'CreatedBy',  N'nvarchar',  30,   NULL, 1),
    (N'UpdatedOn',  N'datetime2', NULL, 3,    1),
    (N'UpdatedBy',  N'nvarchar',  30,   NULL, 1),
    (N'RevisionID', N'int',       NULL, NULL, 0);

DECLARE @InvalidColumns nvarchar(max);

-- Istniejących kolumn nie poprawiamy po cichu. Niezgodny typ mógłby oznaczać ręczną lub niepełną zmianę.
SELECT @InvalidColumns = STRING_AGG(e.ColumnName, N', ')
FROM @ExpectedColumns e
JOIN sys.columns c
    ON c.object_id = OBJECT_ID(N'dbo.tSysUserProfileItems')
   AND c.name = e.ColumnName
JOIN sys.types t
    ON t.user_type_id = c.user_type_id
WHERE t.name <> e.TypeName
   OR c.is_nullable <> e.IsNullable
   OR (e.MaxLength IS NOT NULL AND c.max_length <> e.MaxLength)
   OR (e.Scale IS NOT NULL AND c.scale <> e.Scale);

IF @InvalidColumns IS NOT NULL
BEGIN
    DECLARE @InvalidColumnsMessage nvarchar(2048) =
        N'Niezgodny typ lub nullowalność kolumn: ' + @InvalidColumns + N'. Migracja nie została rozpoczęta.';
    THROW 50008, @InvalidColumnsMessage, 1;
END;

DECLARE @MissingColumns nvarchar(max);

SELECT @MissingColumns = STRING_AGG(e.ColumnName, N', ')
FROM @ExpectedColumns e
WHERE COL_LENGTH(N'dbo.tSysUserProfileItems', e.ColumnName) IS NULL;

-- Wersja 10 bez kompletu kolumn oznacza niespójność, której nie maskujemy komunikatem o sukcesie.
BEGIN TRY
    -- Nullable bez WITH VALUES pozostawia NULL w starych rekordach. Nowe rekordy dostaną czas UTC.
    IF COL_LENGTH(N'dbo.tSysUserProfileItems', N'CreatedOn') IS NULL
    BEGIN
        ALTER TABLE dbo.tSysUserProfileItems
        ADD CreatedOn datetime2(3) NULL
            CONSTRAINT DF_tSysUserProfileItems_CreatedOn DEFAULT SYSUTCDATETIME();
    END;

    IF COL_LENGTH(N'dbo.tSysUserProfileItems', N'CreatedBy') IS NULL
    BEGIN
        ALTER TABLE dbo.tSysUserProfileItems
        ADD CreatedBy nvarchar(15) NULL;
    END;

    IF COL_LENGTH(N'dbo.tSysUserProfileItems', N'UpdatedOn') IS NULL
    BEGIN
        ALTER TABLE dbo.tSysUserProfileItems
        ADD UpdatedOn datetime2(3) NULL;
    END;

    IF COL_LENGTH(N'dbo.tSysUserProfileItems', N'UpdatedBy') IS NULL
    BEGIN
        ALTER TABLE dbo.tSysUserProfileItems
        ADD UpdatedBy nvarchar(15) NULL;
    END;

    -- WITH VALUES ustawia 1 dla istniejących rekordów i pozostawia ten sam domyślny start dla nowych.
    IF COL_LENGTH(N'dbo.tSysUserProfileItems', N'RevisionID') IS NULL
    BEGIN
        ALTER TABLE dbo.tSysUserProfileItems
        ADD RevisionID int NOT NULL
            CONSTRAINT DF_tSysUserProfileItems_RevisionID DEFAULT (1) WITH VALUES;
    END;

    -- Wersję zmieniamy dopiero po dodaniu całego schematu.
    UPDATE dbo.tSysDBVersion
    SET VersionID = @TargetDBVersion;

    IF @@ROWCOUNT <> 1
    BEGIN
        THROW 50010, N'Nie udało się jednoznacznie zaktualizować wersji bazy.', 1;
    END;

    PRINT N'Dodano audyt ustawień użytkownika. Wersja bazy: 10.';
END TRY
BEGIN CATCH
    THROW;
END CATCH;
