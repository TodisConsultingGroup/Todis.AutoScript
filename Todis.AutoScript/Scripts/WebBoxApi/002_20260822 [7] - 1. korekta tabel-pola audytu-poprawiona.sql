/*
2026-08-22 - pola audytu w najważniejszych tabelach systemowych
Co zmieniono względem oryginalnego skryptu:

1. Oryginalny skrypt dodawał pola audytu tylko do tSysUsers. Poprawiona wersja obejmuje jawną listę
   14 najważniejszych tabel systemowych.ś
2. Oryginał zwiększał VersionID przed wykonaniem ALTER TABLE. Poprawiona wersja zmienia wersję dopiero
   po pomyślnym wykonaniu wszystkich zmian i sprawdza, czy zaktualizowano dokładnie jeden rekord wersji.
3. Oryginał przy nieprawidłowej wersji bazy wykonywał tylko PRINT. Poprawiona wersja przerywa wykonanie
   przez THROW i pozwala bezpiecznie uruchomić skrypt ponownie, jeśli baza ma już wersję docelową 7.
4. Dodano SET NOCOUNT ON, SET XACT_ABORT ON i jedną transakcję. Błąd dowolnej operacji powoduje
   wycofanie całej migracji.
5. Przed rozpoczęciem zmian sprawdzana jest obecność wszystkich wymaganych tabel. Brak choć jednej
   tabeli zatrzymuje migrację, dzięki czemu baza nie pozostaje częściowo zmieniona.
6. Oryginał używał datetime, GETDATE() i sztucznej daty 1900-01-01. Poprawiona wersja używa datetime2(3),
   czasu UTC dla CreatedOn oraz NULL, gdy prawdziwa data utworzenia lub aktualizacji nie jest znana.
7. Oryginał wymuszał puste wartości CreatedBy i UpdatedBy. Poprawiona wersja dopuszcza NULL dla danych,
   których nie można wiarygodnie odtworzyć, a wartości dla nowych operacji uzupełnia API.
8. Oryginał usuwał wszystkie ograniczenia DEFAULT po dodaniu kolumn. Poprawiona wersja zachowuje
   wartości domyślne dla CreatedOn i RevisionID, a istniejącym rekordom nadaje RevisionID równy 1.
9. Każda kolumna jest dodawana tylko wtedy, gdy jeszcze nie istnieje. Nazwy tabel i ograniczeń są
   bezpiecznie składane przez QUOTENAME, a kursor jest zamykany także podczas obsługi błędu.
10. Nie dodano IsDeleted do tSysUsers. Konto użytkownika jest blokowane przez istniejące IsBlocked,
    a pełna historia zmian i usunięć jest przechowywana w osobnej tabeli tSysAuditLog.

Odpowiedzi na wcześniejsze pytania:

1. Czy UpdatedOn i UpdatedBy powinny dopuszczać NULL?
   Tak. Nowy rekord nie był jeszcze aktualizowany, dlatego NULL opisuje jego stan lepiej niż sztuczna
   data 1900-01-01 i pusty użytkownik. API uzupełni oba pola dopiero podczas pierwszej aktualizacji.

2. Czy CreatedOn i CreatedBy powinny być wymagane dla istniejących rekordów?
   Nie podczas migracji. Nie znamy prawdziwej daty ani autora utworzenia starych danych, dlatego pola
   pozostają dla nich NULL. Przypisanie daty wykonania migracji dawałoby nieprawdziwą historię.
   Dla nowych rekordów wartości zostaną ustawione automatycznie przez API.

3. Dlaczego używamy datetime2(3) i czasu UTC?
   datetime2 jest dokładniejszym typem dla nowych kolumn. UTC pozwala jednoznacznie porównywać wpisy
   pochodzące z różnych serwerów i stref czasowych. Czas lokalny należy wyliczać dopiero przy prezentacji.

4. Czy dodajemy IsDeleted do tSysUsers?
   Nie. Użytkownik ma już pole IsBlocked i konto powinno być blokowane zamiast fizycznie usuwane (nie
   preferuję fizycznego usuwania użytkownika). Dzięki temu zachowujemy UserID używany w historii innych 
   operacji. Osobne IsDeleted będzie miało sens tylko wtedy, gdy biznesowo rozróżnimy konto zablokowane 
   od logicznie usuniętego.

5. Do czego służy RevisionID?
   RevisionID zaczyna się od 1 i rośnie przy każdej aktualizacji. Pozwala wykryć, że dwie osoby próbują
   zapisać różne wersje tego samego rekordu. API będzie mogło wtedy zwrócić 409 Conflict zamiast nadpisać
   nowsze dane.

6. Te kolumny pokazują utworzenie i ostatnią aktualizację rekordu. Pełne informacje o każdej zmianie, wartościach
   przed i po operacji oraz usunięciach powinny później trafiać do osobnej tabeli np. tSysAuditLog.
   W dzienniku nie wolno zapisywać haseł, saltów, tokenów ani kluczy licencji.

7. API, na podstawie zweryfikowanego użytkownika z HttpContext.Items["UserInfo"] uzupełnia pola audytu. 

*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @RequiredDBVersion int = 6;
DECLARE @TargetDBVersion int = 7;
DECLARE @CurrentDBVersion int;

SELECT TOP (1) @CurrentDBVersion = VersionID
FROM dbo.tSysDBVersion;

-- Powtórne uruchomienie zakończy się bez wykonywania zmian.
IF @CurrentDBVersion = @TargetDBVersion
BEGIN
    PRINT N'Pola audytu są już zainstalowane. Wersja bazy: 7.';
    RETURN;
END;

IF @CurrentDBVersion <> @RequiredDBVersion
BEGIN
    THROW 50001, N'Nieprawidłowa wersja bazy. Skrypt wymaga wersji 6.', 1;
END;

DECLARE @Tables table
(
    TableName sysname NOT NULL PRIMARY KEY
);

-- Najpierw audytujemy dane bezpieczeństwa, firmy, parametry, menu i licencje.
INSERT INTO @Tables (TableName)
VALUES
    (N'tSysUsers'),
    (N'tSysGroups'),
    (N'tSysUsersInGroups'),
    (N'tSysUsersForCompany'),
    (N'tSysRoles'),
    (N'tSysRolesToGroups'),
    (N'tSysPermissionsForRoles'),
    (N'tSysCompanies'),
    (N'tSysYearsForCompany'),
    (N'tSysParameters'),
    (N'tSysAppMenu'),
    (N'tSysAppMenuActions'),
    (N'tSysLicences'),
    (N'tSysLicencesDetails');

DECLARE @MissingTables nvarchar(max);

SELECT @MissingTables = STRING_AGG(TableName, N', ')
FROM @Tables
WHERE OBJECT_ID(N'dbo.' + TableName, N'U') IS NULL;

-- Nie rozpoczynamy częściowej migracji, jeśli schemat wejściowy jest niekompletny.
IF @MissingTables IS NOT NULL
BEGIN
    DECLARE @MissingTablesMessage nvarchar(2048) =
        N'Brak wymaganych tabel: ' + @MissingTables + N'. Migracja nie została rozpoczęta.';
    THROW 50002, @MissingTablesMessage, 1;
END;

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @TableName sysname;
    DECLARE @QualifiedTable nvarchar(258);
    DECLARE @Sql nvarchar(max);

    DECLARE AuditTables CURSOR LOCAL FAST_FORWARD FOR
        SELECT TableName
        FROM @Tables
        ORDER BY TableName;

    OPEN AuditTables;
    FETCH NEXT FROM AuditTables INTO @TableName;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @QualifiedTable = N'dbo.' + QUOTENAME(@TableName);

        -- Dla danych istniejących NULL uczciwie oznacza, że data i autor utworzenia są nieznani.
        IF COL_LENGTH(N'dbo.' + @TableName, N'CreatedOn') IS NULL
        BEGIN
            SET @Sql = N'ALTER TABLE ' + @QualifiedTable
                + N' ADD CreatedOn datetime2(3) NULL'
                + N' CONSTRAINT ' + QUOTENAME(N'DF_' + @TableName + N'_CreatedOn')
                + N' DEFAULT SYSUTCDATETIME();';
            EXEC sys.sp_executesql @Sql;
        END;

        IF COL_LENGTH(N'dbo.' + @TableName, N'CreatedBy') IS NULL
        BEGIN
            SET @Sql = N'ALTER TABLE ' + @QualifiedTable
                + N' ADD CreatedBy nvarchar(15) NULL;';
            EXEC sys.sp_executesql @Sql;
        END;

        -- Brak aktualizacji jest normalnym stanem nowego rekordu, dlatego te pola są opcjonalne.
        IF COL_LENGTH(N'dbo.' + @TableName, N'UpdatedOn') IS NULL
        BEGIN
            SET @Sql = N'ALTER TABLE ' + @QualifiedTable
                + N' ADD UpdatedOn datetime2(3) NULL;';
            EXEC sys.sp_executesql @Sql;
        END;

        IF COL_LENGTH(N'dbo.' + @TableName, N'UpdatedBy') IS NULL
        BEGIN
            SET @Sql = N'ALTER TABLE ' + @QualifiedTable
                + N' ADD UpdatedBy nvarchar(15) NULL;';
            EXEC sys.sp_executesql @Sql;
        END;

        IF COL_LENGTH(N'dbo.' + @TableName, N'RevisionID') IS NULL
        BEGIN
            SET @Sql = N'ALTER TABLE ' + @QualifiedTable
                + N' ADD RevisionID int NOT NULL'
                + N' CONSTRAINT ' + QUOTENAME(N'DF_' + @TableName + N'_RevisionID')
                + N' DEFAULT (1) WITH VALUES;';
            EXEC sys.sp_executesql @Sql;
        END;

        FETCH NEXT FROM AuditTables INTO @TableName;
    END;

    CLOSE AuditTables;
    DEALLOCATE AuditTables;

    -- Wersję zmieniamy na końcu, gdy cały schemat został poprawnie rozszerzony.
    UPDATE dbo.tSysDBVersion
    SET VersionID = @TargetDBVersion;

    IF @@ROWCOUNT <> 1
    BEGIN
        THROW 50003, N'Nie udało się jednoznacznie zaktualizować wersji bazy.', 1;
    END;

    COMMIT TRANSACTION;
    PRINT N'Zakończono migrację pól audytu. Wersja bazy: 7.';
END TRY
BEGIN CATCH
    IF CURSOR_STATUS(N'local', N'AuditTables') >= 0
        CLOSE AuditTables;

    IF CURSOR_STATUS(N'local', N'AuditTables') > -3
        DEALLOCATE AuditTables;

    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
