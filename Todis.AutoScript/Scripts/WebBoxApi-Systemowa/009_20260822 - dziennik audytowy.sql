/*
Wersja docelowa: 9
2026-08-22 - dziennik audytowy zmian danych systemowych
Odpowiedzi projektowe:

1. Dlaczego powstaje osobna tabela zamiast użycia tSysLog, tSysLogApp albo tSysLogSvc?
   Istniejące tabele przechowują techniczne komunikaty tekstowe. tSysAuditLog ma stabilną strukturę
   opisującą rekord, operację oraz wartości przed i po zmianie.

2. Dlaczego zapisujemy jednocześnie ChangedByUserID i ChangedBy?
   UserID pozwala powiązać wpis z kontem, a alias zachowuje czytelną migawkę autora nawet po zmianie
   jego danych. Celowo nie ma klucza obcego do tSysUsers, aby historia nie zależała od życia konta.

3. Dlaczego klucz rekordu oraz dane przed i po operacji są JSON-em?
   Audyt obejmie tabele z kluczami prostymi i złożonymi. JSON zachowuje nazwy pól bez tworzenia
   osobnej tabeli historii dla każdego rodzaju danych.

4. Czy tSysAuditLog może być obsługiwana przez standardowy CRUD SystemData?
   Nie. Dziennik jest append-only: API może tylko dopisywać wpisy, a odczyt administracyjny powstanie
   później jako osobny, zabezpieczony endpoint.

5. Czy skrypt usuwa stare wpisy?
   Nie. Polityka retencji i ewentualna archiwizacja wymagają osobnej decyzji biznesowej.

Założenia migracji:
    - migracja podnosi wersję bazy systemowej z 8 do 9;
    - wszystkie zmiany wykonują się w jednej transakcji;
    - czas jest zapisywany w UTC jako datetime2(3);
    - Operation przyjmuje INSERT, UPDATE albo DELETE;
    - RecordKey, BeforeData i AfterData zawierają poprawny JSON;
    - migracja tworzy wyłącznie strukturę tabeli; API nie zapisuje jeszcze wpisów audytu.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @TargetDBVersion int = 9;

IF OBJECT_ID(N'dbo.tSysAuditLog', N'U') IS NOT NULL
BEGIN
    THROW 50002, N'Tabela tSysAuditLog już istnieje przy wersji bazy niższej niż 9. Sprawdź niepełną migrację.', 1;
END;

BEGIN TRY
    CREATE TABLE dbo.tSysAuditLog
    (
        AuditLogID bigint IDENTITY(1,1) NOT NULL,
        ChangedOn datetime2(3) NOT NULL
            CONSTRAINT DF_tSysAuditLog_ChangedOn DEFAULT SYSUTCDATETIME(),
        ChangedByUserID int NULL,
        ChangedBy nvarchar(15) NOT NULL,
        TableName nvarchar(128) NOT NULL,
        RecordKey nvarchar(1000) NOT NULL,
        Operation varchar(10) NOT NULL,
        BeforeData nvarchar(max) NULL,
        AfterData nvarchar(max) NULL,
        HttpMethod varchar(10) NULL,
        RequestPath nvarchar(512) NULL,
        TraceID nvarchar(64) NULL,

        CONSTRAINT PK_tSysAuditLog PRIMARY KEY CLUSTERED (AuditLogID),
        CONSTRAINT CK_tSysAuditLog_Operation
            CHECK (Operation IN ('INSERT', 'UPDATE', 'DELETE')),
        CONSTRAINT CK_tSysAuditLog_RecordKeyJson
            CHECK (ISJSON(RecordKey) = 1),
        CONSTRAINT CK_tSysAuditLog_BeforeDataJson
            CHECK (BeforeData IS NULL OR ISJSON(BeforeData) = 1),
        CONSTRAINT CK_tSysAuditLog_AfterDataJson
            CHECK (AfterData IS NULL OR ISJSON(AfterData) = 1)
    );

    -- Najczęstsze odczyty zaczynają się od czasu, tabeli albo autora zmiany.
    CREATE INDEX IX_tSysAuditLog_ChangedOn
        ON dbo.tSysAuditLog (ChangedOn DESC);

    CREATE INDEX IX_tSysAuditLog_TableName_ChangedOn
        ON dbo.tSysAuditLog (TableName, ChangedOn DESC)
        INCLUDE (Operation, ChangedByUserID, ChangedBy);

    CREATE INDEX IX_tSysAuditLog_ChangedByUserID_ChangedOn
        ON dbo.tSysAuditLog (ChangedByUserID, ChangedOn DESC)
        INCLUDE (TableName, Operation, ChangedBy);

    UPDATE dbo.tSysDBVersion
    SET VersionID = @TargetDBVersion;

    IF @@ROWCOUNT <> 1
    BEGIN
        THROW 50003, N'Nie udało się jednoznacznie zaktualizować wersji bazy.', 1;
    END;

    PRINT N'Utworzono tSysAuditLog. Wersja bazy: 9.';
END TRY
BEGIN CATCH
    THROW;
END CATCH;
