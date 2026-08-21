/*
2026-08-14 - 
	- usunięcie tabeli tSysPermissionsForUser
	- nowe pole PermissionID w tabeli tSysAppMenuActions 
	- nowa tabela tSysLanDescriptions
	- nowa tabela tSysLicensesDetails
	- aktualizacja pola PermissionID w tabeli tSysAppMenuActions 
*/
 
 
DECLARE @RequiredDBVersion INT =5

IF (SELECT TOP 1 VersionID FROM tSysDBVersion) <> @RequiredDBVersion
      PRINT 'Nieprawidłowa wersja bazy danych!'
ELSE
BEGIN

     UPDATE tSysDBVersion          SET VersionID = @RequiredDBVersion + 1
END


	DROP TABLE tSysPermissionsForUser
	GO

	ALTER TABLE tSysAppMenuActions ADD PermissionID uniqueidentifier NULL
	GO

	CREATE TABLE [dbo].[tSysLanDescriptions](
	[TableName] [nvarchar](50) NOT NULL,
	[FieldName] [nvarchar](50) NOT NULL,
	[RowKey] [nvarchar](50) NOT NULL,
	[LanguageCode] [nchar](3) NOT NULL,
	[Description] [nvarchar](50) NOT NULL,
	 CONSTRAINT [PK_tSysLanDescriptions] PRIMARY KEY CLUSTERED 
	(
		[TableName] ASC,
		[FieldName] ASC,
		[RowKey] ASC,
		[LanguageCode] ASC
	)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON ) ON [PRIMARY]
	) ON [PRIMARY]
	GO

	CREATE TABLE [dbo].[tSysLicencesDetails](
	[SeqNo] [bigint] NOT NULL,
	[ItemID] [uniqueidentifier] NOT NULL,
	[Description] [nvarchar](150) NOT NULL,
	[ItemCount] [int] NOT NULL,
	[ExpiryDate] [datetime] NOT NULL,
	 CONSTRAINT [PK_tSysLicencesDetails] PRIMARY KEY CLUSTERED 
	(
		[SeqNo] ASC,
		[ItemID] ASC
	)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
	) ON [PRIMARY]
	GO



	UPDATE tSysAppMenuActions SET PermissionID='00000003-0006-0001-0000-48180982f373' WHERE ActionValue='ban/payments/forecast'
	UPDATE tSysAppMenuActions SET PermissionID='00000003-0006-0001-0000-75a4d8666276' WHERE ActionValue='ban/payments/prepare'
	UPDATE tSysAppMenuActions SET PermissionID='00000003-0006-0001-0000-ed8e23fe2062' WHERE ActionValue='ban/payments/history'
	UPDATE tSysAppMenuActions SET PermissionID='00000003-0006-0001-0000-7a1a3be13202' WHERE ActionValue='ban/payments/reports/whiteList'
	UPDATE tSysAppMenuActions SET PermissionID='00000003-0006-0001-0000-bddebf36688f' WHERE ActionValue='ban/statements/import'
	--UPDATE tSysAppMenuActions SET PermissionID='' WHERE ActionValue='ban/statements/importHistory'
	UPDATE tSysAppMenuActions SET PermissionID='00000003-0006-0001-0000-69a75c4a46a7' WHERE ActionValue='ban/statements/reconciliation'
	--UPDATE tSysAppMenuActions SET PermissionID='' WHERE ActionValue='ban/statements/reconciliationHistory'
	--UPDATE tSysAppMenuActions SET PermissionID='' WHERE ActionValue='ban/editAccountsList'
	--UPDATE tSysAppMenuActions SET PermissionID='' WHERE ActionValue='ban/editDictionaryItems'
	--UPDATE tSysAppMenuActions SET PermissionID='' WHERE ActionValue='ban/editParameters'


	UPDATE tSysAppMenuActions SET PermissionID='00000003-0008-0105-0000-7b35a3ab0dbc' WHERE ActionValue='vac/generateJpk'
	UPDATE tSysAppMenuActions SET PermissionID='00000003-0008-0104-0000-886bb78807b9' WHERE ActionValue='vac/purchaseReview'
	UPDATE tSysAppMenuActions SET PermissionID='00000003-0008-0103-0000-00c538b8be62' WHERE ActionValue='vac/salesReview'
	UPDATE tSysAppMenuActions SET PermissionID='00000003-0008-0106-0000-59aa8174a8a8' WHERE ActionValue='vac/reports/vatue'
	--UPDATE tSysAppMenuActions SET PermissionID='' WHERE ActionValue='vac/editDictionaryItems'
	UPDATE tSysAppMenuActions SET PermissionID='00000003-0008-0106-0000-ebe0dadd713f' WHERE ActionValue='vac/editParameters'
	UPDATE tSysAppMenuActions SET PermissionID='00000003-0008-0106-0000-accd3f0a6240' WHERE ActionValue='vac/editParametersJpk'
	UPDATE tSysAppMenuActions SET PermissionID='00000003-0008-0106-0000-accd3f0a6241' WHERE ActionValue='vac/editSourceDataMappingV7m'
	UPDATE tSysAppMenuActions SET PermissionID='00000003-0008-0106-0000-accd3f0a6242' WHERE ActionValue='vac/editSourceDataMappingVatUe'

	-- dodanie licencji i podpozycji licencji
	DELETE FROM tSysLicences
	INSERT INTO tSysLicences (LicenceKey, IsActive) SELECT 'nG[nLg4lJTUA5p;nnXQqWqLOocN~_@kDCONMiD2U=qmPdrEVgmaZT{i@k?0dQTZzJ^G}Bi3feNYqHwH`4zUWFnT~_k6p0d4fnr5E;|dF1Q9\HC0~mpbY5z0C_P:Zg?mLhj[gK{faN{8p^}^[GCSI8FYWI^EXdF4mJOZ_Ch[dclSFfQ@nEG',1

	DELETE FROM tSysLicencesDetails
	DECLARE @SeqNo bigint
	SET @SeqNo = (SELECT MAX(SeqNo) FROM tSysLicences)
	-- ToDo: 
	-- Liczba firm
	INSERT INTO tSysLicencesDetails (SeqNo, ItemID, Description, ItemCount, ExpiryDate) VALUES (@SeqNo, '10000001-0000-0000-0000-000000000001','Companies count', -1, CONVERT(DATETIME, '9999-12-31', 120))
	-- Liczba użytkowników
	INSERT INTO tSysLicencesDetails (SeqNo, ItemID, Description, ItemCount, ExpiryDate) VALUES (@SeqNo, '10000001-0000-0000-0000-000000000002','Users count', 10, CONVERT(DATETIME, '9999-12-31', 120))
	-- Weryfikacja licencji
	INSERT INTO tSysLicencesDetails (SeqNo, ItemID, Description, ItemCount, ExpiryDate) VALUES (@SeqNo, 'F0000000-0000-0000-0000-000000000002','Licence check', -1, CONVERT(DATETIME, '9999-12-31', 120))
	
	-- Opcje aplikacji
	-- Uwaga: w generatorze licencji można zaznaczyć główną gałąź, ale w pliku licencji, a następnie w szczgółach licencji, należy umieścić wszystkie podpozycje (zarówno zaznaczoną główną, jak i potomne dla tej pozycji)
	--        np.: w przypadku plików JPK, mozna zaznaczyć gałąź główną JPK, ale w szczegółach trzeba wymienić: JPK-VAT, JPK-KR, JPK-V7M, JPK-CIT, itd....

	INSERT INTO tSysLicencesDetails (SeqNo, ItemID, Description, ItemCount, ExpiryDate) VALUES (@SeqNo, '00000003-0000-0000-0000-000000000001','Application', 1, CONVERT(DATETIME, '9999-12-31', 120))
	INSERT INTO tSysLicencesDetails (SeqNo, ItemID, Description, ItemCount, ExpiryDate) VALUES (@SeqNo, '00000003-0000-0099-0000-C514605EFD37','System Setup', 1, CONVERT(DATETIME, '9999-12-31', 120))

	INSERT INTO tSysLicencesDetails (SeqNo, ItemID, Description, ItemCount, ExpiryDate) VALUES (@SeqNo, '00000003-0006-0001-0000-837F789CC39A','Bankyer', 1, CONVERT(DATETIME, '9999-12-31', 120))
	INSERT INTO tSysLicencesDetails (SeqNo, ItemID, Description, ItemCount, ExpiryDate) VALUES (@SeqNo, '00000003-0006-0001-0000-3790F858C595','Eksport przelewów do pliku', 1, CONVERT(DATETIME, '9999-12-31', 120))
	INSERT INTO tSysLicencesDetails (SeqNo, ItemID, Description, ItemCount, ExpiryDate) VALUES (@SeqNo, '00000003-0006-0001-0000-48180982F373','Generowanie prognozy', 1, CONVERT(DATETIME, '9999-12-31', 120))
	INSERT INTO tSysLicencesDetails (SeqNo, ItemID, Description, ItemCount, ExpiryDate) VALUES (@SeqNo, '00000003-0006-0001-0000-69A75C4A46A7','Analiza wyciągów', 1, CONVERT(DATETIME, '9999-12-31', 120))
	INSERT INTO tSysLicencesDetails (SeqNo, ItemID, Description, ItemCount, ExpiryDate) VALUES (@SeqNo, '00000003-0006-0001-0000-75A4D8666276','Przygotowanie propozycji płatności', 1, CONVERT(DATETIME, '9999-12-31', 120))
	INSERT INTO tSysLicencesDetails (SeqNo, ItemID, Description, ItemCount, ExpiryDate) VALUES (@SeqNo, '00000003-0006-0001-0000-7A1A3BE13202','Weryfikacja konta na Białej Liście', 1, CONVERT(DATETIME, '9999-12-31', 120))
	INSERT INTO tSysLicencesDetails (SeqNo, ItemID, Description, ItemCount, ExpiryDate) VALUES (@SeqNo, '00000003-0006-0001-0000-7C79DE1A05CD','Import i rozliczanie wyciągów', 1, CONVERT(DATETIME, '9999-12-31', 120))
	INSERT INTO tSysLicencesDetails (SeqNo, ItemID, Description, ItemCount, ExpiryDate) VALUES (@SeqNo, '00000003-0006-0001-0000-9CAF87D9D236','Usuwanie wyciagów', 1, CONVERT(DATETIME, '9999-12-31', 120))
	INSERT INTO tSysLicencesDetails (SeqNo, ItemID, Description, ItemCount, ExpiryDate) VALUES (@SeqNo, '00000003-0006-0001-0000-B19620891499','Eksport przelewów', 1, CONVERT(DATETIME, '9999-12-31', 120))
	INSERT INTO tSysLicencesDetails (SeqNo, ItemID, Description, ItemCount, ExpiryDate) VALUES (@SeqNo, '00000003-0006-0001-0000-B3F95C67C0D6','Księgowanie wyciągów', 1, CONVERT(DATETIME, '9999-12-31', 120))
	INSERT INTO tSysLicencesDetails (SeqNo, ItemID, Description, ItemCount, ExpiryDate) VALUES (@SeqNo, '00000003-0006-0001-0000-BDDEBF36688F','Import wyciągów', 1, CONVERT(DATETIME, '9999-12-31', 120))
	INSERT INTO tSysLicencesDetails (SeqNo, ItemID, Description, ItemCount, ExpiryDate) VALUES (@SeqNo, '00000003-0006-0001-0000-ED8E23FE2062','Historia wysłanych przelewów', 1, CONVERT(DATETIME, '9999-12-31', 120))

	INSERT INTO tSysLicencesDetails (SeqNo, ItemID, Description, ItemCount, ExpiryDate) VALUES (@SeqNo, '00000003-0008-0002-0000-9021F653678E','Vacik', 1, CONVERT(DATETIME, '9999-12-31', 120))
	INSERT INTO tSysLicencesDetails (SeqNo, ItemID, Description, ItemCount, ExpiryDate) VALUES (@SeqNo, '00000003-0008-0101-0000-5DD131A2FED1','Sprzedaż', 1, CONVERT(DATETIME, '9999-12-31', 120))
	INSERT INTO tSysLicencesDetails (SeqNo, ItemID, Description, ItemCount, ExpiryDate) VALUES (@SeqNo, '00000003-0008-0102-0000-00C538B8BE62','Zakup', 1, CONVERT(DATETIME, '9999-12-31', 120))
	INSERT INTO tSysLicencesDetails (SeqNo, ItemID, Description, ItemCount, ExpiryDate) VALUES (@SeqNo, '00000003-0008-0103-0000-00C538B8BE62','Przeglądanie zapisów VAT-Sprzedaż', 1, CONVERT(DATETIME, '9999-12-31', 120))
	INSERT INTO tSysLicencesDetails (SeqNo, ItemID, Description, ItemCount, ExpiryDate) VALUES (@SeqNo, '00000003-0008-0104-0000-886BB78807B9','Przeglądanie zapisów VAT-Zakup', 1, CONVERT(DATETIME, '9999-12-31', 120))
	INSERT INTO tSysLicencesDetails (SeqNo, ItemID, Description, ItemCount, ExpiryDate) VALUES (@SeqNo, '00000003-0008-0105-0000-7B35A3AB0DBC','Generowanie plików JPK', 1, CONVERT(DATETIME, '9999-12-31', 120))
	INSERT INTO tSysLicencesDetails (SeqNo, ItemID, Description, ItemCount, ExpiryDate) VALUES (@SeqNo, '00000003-0008-0106-0000-59AA8174A8A8','Generowanie deklaracji VAT-UE', 1, CONVERT(DATETIME, '9999-12-31', 120))
	INSERT INTO tSysLicencesDetails (SeqNo, ItemID, Description, ItemCount, ExpiryDate) VALUES (@SeqNo, '00000003-0008-0106-0000-9A1307D40ED6','Ustawienia', 1, CONVERT(DATETIME, '9999-12-31', 120))
	INSERT INTO tSysLicencesDetails (SeqNo, ItemID, Description, ItemCount, ExpiryDate) VALUES (@SeqNo, '00000003-0008-0106-0000-ACCD3F0A6240','Parametry (JPK)', 1, CONVERT(DATETIME, '9999-12-31', 120))
	INSERT INTO tSysLicencesDetails (SeqNo, ItemID, Description, ItemCount, ExpiryDate) VALUES (@SeqNo, '00000003-0008-0106-0000-ACCD3F0A6241','Mapowanie kodów VAT dla JPK', 1, CONVERT(DATETIME, '9999-12-31', 120))
	INSERT INTO tSysLicencesDetails (SeqNo, ItemID, Description, ItemCount, ExpiryDate) VALUES (@SeqNo, '00000003-0008-0106-0000-ACCD3F0A6242','Mapowanie kodów VAT dla VAT-UE', 1, CONVERT(DATETIME, '9999-12-31', 120))
	INSERT INTO tSysLicencesDetails (SeqNo, ItemID, Description, ItemCount, ExpiryDate) VALUES (@SeqNo, '00000003-0008-0106-0000-EBE0DADD713F','Parametry (VAT)', 1, CONVERT(DATETIME, '9999-12-31', 120))

	
