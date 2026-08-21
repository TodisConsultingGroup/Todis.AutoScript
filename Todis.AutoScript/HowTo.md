# Todis AutoScript — instrukcja obsługi

Todis AutoScript uruchamia skrypty SQL po kolei na wybranej bazie SQL Server.

## 1. Uruchomienie aplikacji

W głównym katalogu projektu otwórz PowerShell i wykonaj:

```powershell
dotnet run --project .\Todis.AutoScript\Todis.AutoScript.csproj
```

## 2. Pierwsza konfiguracja

Po lewej stronie okna podaj:

1. **Serwer / instancję**, np. `localhost`, `SERWER01` albo `localhost\SQLEXPRESS`.
2. **Nazwę bazy**, na której mają zostać wykonane skrypty.
3. Rodzaj **uwierzytelniania**:
   - **Windows** — program użyje aktualnie zalogowanego konta Windows; login i hasło nie są potrzebne,
   - **SQL Server** — podaj login i hasło użytkownika SQL.
4. W razie potrzeby zaznacz **Ufaj certyfikatowi serwera**.

Kliknij **Testuj połączenie**, a następnie **Zapisz ustawienia**. Konfiguracja zostanie zapamiętana i można ją zmienić w dowolnym momencie.

Hasło SQL jest chronione mechanizmem Windows i może zostać odczytane tylko na koncie użytkownika, które je zapisało. Konfiguracja nie trafia do repozytorium.

## 3. Gdzie umieszczać skrypty

Domyślny katalog skryptów to:

```text
Todis.AutoScript\Scripts
```

Każdy podfolder jest osobnym zestawem skryptów:

```text
Scripts
├── WebBoxApi
│   ├── 001_utworz_tabele.sql
│   ├── 002_dodaj_kolumny.sql
│   └── 003_uzupelnij_dane.sql
└── CośTamJeszcze
    ├── 001_utworz_widok.sql
    └── 002_dodaj_procedure.sql
```

Nazwy folderów mogą być dowolne, ale powinny jasno opisywać przeznaczenie zestawu. W aplikacji można także użyć przycisku **Zmień folder główny…** i wskazać inną lokalizację.

## 4. Kolejność wykonywania plików

Pliki `.sql` są sortowane alfabetycznie. Kolejność należy określić numerem na początku nazwy:

```text
001_pierwszy_krok.sql
002_drugi_krok.sql
003_trzeci_krok.sql
010_pozniejszy_krok.sql
```

Używaj zawsze tej samej liczby cyfr: `001`, `002`, `010`, a nie `1`, `2`, `10`.

Aplikacja obsługuje standardowe separatory partii SQL Server:

```sql
CREATE TABLE dbo.Przyklad
(
    Id int NOT NULL
);
GO

INSERT INTO dbo.Przyklad (Id) VALUES (1);
GO
```

## 5. Uruchamianie skryptów

1. Sprawdź serwer oraz nazwę bazy.
2. Przetestuj połączenie.
3. Wybierz po lewej stronie właściwy zestaw skryptów.
4. Sprawdź kolejność plików na liście.
5. Kliknij **Uruchom skrypty**.
6. Przeczytaj komunikat potwierdzający nazwę bazy i zaakceptuj uruchomienie.

Program pokazuje aktualny plik, stan każdego skryptu, ogólny postęp i komunikaty w logu.

## 6. Obsługa błędów

Program zatrzymuje wykonywanie przy pierwszym błędzie i pokazuje:

- nazwę skryptu,
- numer linii,
- komunikat zwrócony przez SQL Server.

Każdy plik jest wykonywany w osobnej transakcji. Jeżeli drugi plik zakończy się błędem, pierwszy pozostanie zatwierdzony, drugi zostanie wycofany w całości, a trzeci nie zostanie uruchomiony.

Program nie tworzy tabeli historii ani żadnych innych obiektów technicznych w bazie. Log każdego uruchomienia zapisuje wyłącznie lokalnie w:

```text
%LOCALAPPDATA%\Todis.AutoScript\Logs
```

Po poprawieniu błędu sprawdź, czy wcześniejsze pliki można bezpiecznie uruchomić ponownie. Aplikacja celowo nie odczytuje historii z bazy i nie pomija ich automatycznie.

Warto pisać skrypty tak, aby ich ponowne uruchomienie było bezpieczne:

```sql
IF OBJECT_ID(N'dbo.Przyklad', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Przyklad
    (
        Id int NOT NULL
    );
END;
GO
```

Jeżeli kilka operacji musi wykonać się razem, umieść transakcję bezpośrednio w odpowiednim skrypcie SQL.
