# Todis AutoScript

Natywna aplikacja Windows do sekwencyjnego uruchamiania zestawów skryptów SQL Server.

## Uruchomienie

```powershell
dotnet run --project .\Todis.AutoScript\Todis.AutoScript.csproj
```

Przy pierwszym uruchomieniu ustaw serwer, bazę i uwierzytelnianie, przetestuj połączenie, wybierz zestaw, a następnie kliknij **Uruchom skrypty**. Konfiguracja trafia do `%LOCALAPPDATA%\Todis.AutoScript\config.json`. Hasło SQL jest chronione mechanizmem Windows DPAPI i można je odszyfrować wyłącznie na koncie użytkownika, które je zapisało.

## Organizacja skryptów

Każdy podfolder katalogu `Scripts` jest osobnym zestawem, np. `BAZA ZIELONA` albo `BAZA CZERWONA`. Pliki `.sql` są uruchamiane alfabetycznie, dlatego zalecana konwencja to:

```text
001_utworz_tabele.sql
002_dodaj_kolumny.sql
010_uzupelnij_dane.sql
```

Obsługiwane są separatory partii `GO` oraz `GO n`. Program zatrzymuje się na pierwszym błędzie i pokazuje nazwę pliku oraz linię. Skrypty z już wykonanych plików nie są automatycznie cofane — migracje powinny być możliwie idempotentne albo samodzielnie korzystać z transakcji.

## Publikacja pojedynczego EXE

```powershell
dotnet publish .\Todis.AutoScript\Todis.AutoScript.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true
```
