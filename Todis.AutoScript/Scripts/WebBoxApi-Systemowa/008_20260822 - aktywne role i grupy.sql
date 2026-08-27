/*
Wersja docelowa: 8
2026-08-22 - aktywne role i grupy
Założenia:
    - migracja podnosi wersję bazy systemowej z 7 do 8;
    - role i grupy nie będą fizycznie usuwane, tylko dezaktywowane;
    - IsActive = 1 oznacza rekord dostępny w bieżącej konfiguracji uprawnień;
    - IsActive = 0 zachowuje rekord i jego powiązania historyczne, ale wyklucza go z wyliczania dostępu;
    - istniejące role i grupy pozostają aktywne;
    - role systemowe nadal pozostają aktywne, a ich ochronę przed dezaktywacją zapewni API;
    - CreatedOn, CreatedBy, UpdatedOn, UpdatedBy i RevisionID pozostają bez zmian;
    - pełna historia operacji zostanie później zapisana w tSysAuditLog.

Skrypt jest przeznaczony wyłącznie dla bazy systemowej.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @TargetDBVersion int = 8;

IF OBJECT_ID(N'dbo.tSysGroups', N'U') IS NULL OR OBJECT_ID(N'dbo.tSysRoles', N'U') IS NULL
BEGIN
    THROW 50002, N'Brak tabel tSysGroups lub tSysRoles. Migracja nie została rozpoczęta.', 1;
END;

-- Jeśli kolumna została wcześniej dodana ręcznie, musi mieć uzgodniony typ i nullowalność.
IF EXISTS
(
    SELECT 1
    FROM sys.columns c
    JOIN sys.types t ON t.user_type_id = c.user_type_id
    WHERE c.object_id IN (OBJECT_ID(N'dbo.tSysGroups'), OBJECT_ID(N'dbo.tSysRoles'))
      AND c.name = N'IsActive'
      AND (t.name <> N'bit' OR c.is_nullable <> 0)
)
BEGIN
    THROW 50003, N'Istniejąca kolumna IsActive ma niezgodny typ albo dopuszcza NULL.', 1;
END;

BEGIN TRY
    IF COL_LENGTH(N'dbo.tSysGroups', N'IsActive') IS NULL
    BEGIN
        ALTER TABLE dbo.tSysGroups
        ADD IsActive bit NOT NULL
            CONSTRAINT DF_tSysGroups_IsActive DEFAULT (1) WITH VALUES;
    END;

    IF COL_LENGTH(N'dbo.tSysRoles', N'IsActive') IS NULL
    BEGIN
        ALTER TABLE dbo.tSysRoles
        ADD IsActive bit NOT NULL
            CONSTRAINT DF_tSysRoles_IsActive DEFAULT (1) WITH VALUES;
    END;

    UPDATE dbo.tSysDBVersion
    SET VersionID = @TargetDBVersion;

    IF @@ROWCOUNT <> 1
    BEGIN
        THROW 50004, N'Nie udało się jednoznacznie zaktualizować wersji bazy.', 1;
    END;

    PRINT N'Dodano obsługę aktywnych ról i grup. Wersja bazy: 8.';
END TRY
BEGIN CATCH
    THROW;
END CATCH;
