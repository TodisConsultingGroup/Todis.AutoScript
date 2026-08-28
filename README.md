# Todis AutoScript — instrukcja obsługi

Todis AutoScript uruchamia skrypty SQL po kolei na wybranej bazie SQL Server.

## 1. Uruchomienie aplikacji

```powershell
dotnet run --project .\Todis.AutoScript\Todis.AutoScript.csproj
```

## 2. Pierwsza konfiguracja

Po lewej stronie okna podaj:

1. **Serwer / instancję**, np. `localhost`, `SERWER01` albo `localhost\SQLEXPRESS`.
2. **Nazwę bazy**, na której mają zostać wykonane skrypty.
3. Rodzaj **uwierzytelniania**:
   - **Windows** — program użyje aktualnego konta Windows; login i hasło nie są potrzebne,
   - **SQL Server** — podaj login i hasło użytkownika SQL.
4. W razie potrzeby zaznacz **Ufaj certyfikatowi serwera**.

Kliknij **Testuj połączenie**, a następnie **Zapisz ustawienia**. Konfigurację można zmienić w dowolnym momencie.

Przycisk ze słońcem lub księżycem przełącza motyw **Jasny/Ciemny**. Motyw i szerokości kolumn grida są zapisywane lokalnie.

Hasło SQL jest chronione mechanizmem Windows i może zostać odczytane tylko na koncie użytkownika, które je zapisało. Konfiguracja nie trafia do repozytorium.

## 3. Gdzie umieszczać skrypty

Domyślny katalog skryptów:

```text
Todis.AutoScript\Scripts
```

Każdy podfolder jest osobnym zestawem:

```text
Scripts
├── WebBoxApi
│   ├── 001_utworz_tabele.sql
│   ├── 002_dodaj_kolumny.sql
│   └── 003_uzupelnij_dane.sql
└── InnyZestaw
    ├── 001_utworz_widok.sql
    └── 002_dodaj_procedure.sql
```

Można również kliknąć **Zmień folder główny…** i wskazać inną lokalizację.

## 4. Kolejność wykonywania

Pierwsza grupa cyfr w nazwie oznacza **docelową wersję bazy**. Pliki są sortowane po nazwie:

```text
006_20260815_opis.sql
007_20260822_opis.sql
008_20260822_opis.sql
```

Używaj zawsze co najmniej trzech cyfr. Przed każdym plikiem aplikacja sprawdza, czy aktualna wersja jest o jeden niższa od wersji w nazwie, a po wykonaniu potwierdza wersję docelową. Kontroli wersji nie należy powielać wewnątrz skryptów. Aplikacja obsługuje separatory `GO` i `GO n`.

## 5. Uruchamianie skryptów

1. Sprawdź serwer i bazę.
2. Przetestuj połączenie.
3. Wybierz zestaw skryptów.
4. Sprawdź kolejność na liście.
5. Kliknij **Uruchom wszystkie**.
6. Zweryfikuj bazę w komunikacie potwierdzającym.

Lista aktualizuje się automatycznie po dodaniu, usunięciu lub zmianie nazwy pliku `.sql`. Podczas wykonywania jest zamrożona i odświeża się po zakończeniu.

## 6. Obsługa błędów

Program zatrzymuje się przy pierwszym błędzie i pokazuje nazwę skryptu, numer linii oraz komunikat SQL Server.

Domyślnie każdy plik działa w osobnej transakcji. Błąd zatrzymuje kolejkę, ale nie wycofuje wcześniej zatwierdzonych plików.

Opcja **Uruchom cały zestaw w jednej transakcji** obejmuje wszystkie pliki wspólną transakcją. W tym trybie błąd dowolnego skryptu wycofuje cały zestaw. Skrypty SQL nie powinny samodzielnie otwierać ani zatwierdzać transakcji.

Program nie tworzy tabel historii ani innych obiektów technicznych w bazie. Logi zapisuje lokalnie w `Todis.AutoScript\Logs`. Są ignorowane przez Git, a w opublikowanej wersji folder `Logs` powstaje obok EXE.

Po poprawieniu błędu:

- w trybie osobnych transakcji zaznacz pierwszy niewykonany skrypt i kliknij **Wznów od zaznaczonego**,
- w trybie jednej transakcji uruchom cały zestaw ponownie, ponieważ poprzednia transakcja została wycofana.

## 7. Skrypty w repozytorium

Foldery i skrypty z `Todis.AutoScript\Scripts` można commitować na `master` razem z aplikacją. Nie umieszczaj w nich haseł, loginów, connection stringów ani innych danych poufnych.

## 8. Wersja EXE

Publikacja domyślna:

```powershell
.\Publish.ps1
```

Publikacja do wybranego katalogu:

```powershell
.\Publish.ps1 -OutputPath "C:\codex\Todis.AutoScript-win-x64"
```

Przekaż użytkownikowi cały wygenerowany katalog, nie tylko EXE. Paczka zawiera program i folder `Scripts`. Jest samodzielna dla 64-bitowego Windows — nie wymaga instalowania .NET.

Konfiguracja połączenia, zaszyfrowane hasło, motyw i szerokości kolumn są przechowywane w lokalnym profilu użytkownika. Aktualizacja programu ich nie usuwa.

## 9. Teksty aplikacji

Wszystkie teksty interfejsu, komunikaty, statusy i formaty logów znajdują się w `Todis.AutoScript/Resources/Strings.resx`. Nowych komunikatów nie należy wpisywać bezpośrednio w kodzie C# ani XAML.

## 10. Najważniejsza zasada

Przed uruchomieniem sprawdź właściwy serwer, bazę, zestaw skryptów i ich kolejność.
