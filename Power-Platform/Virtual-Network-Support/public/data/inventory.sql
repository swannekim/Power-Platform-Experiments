SET XACT_ABORT ON;
BEGIN TRANSACTION;

IF OBJECT_ID(N'dbo.Inventory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Inventory
    (
        SKU nvarchar(24) NOT NULL PRIMARY KEY,
        ProductName nvarchar(100) NOT NULL,
        Warehouse nvarchar(40) NOT NULL,
        AvailableQuantity int NOT NULL CHECK (AvailableQuantity >= 0),
        UnitPrice decimal(10, 2) NOT NULL CHECK (UnitPrice >= 0),
        Currency char(3) NOT NULL,
        VerificationCode nvarchar(40) NOT NULL
    );
END;

INSERT INTO dbo.Inventory
    (SKU, ProductName, Warehouse, AvailableQuantity, UnitPrice, Currency, VerificationCode)
SELECT seed.*
FROM (VALUES
    (N'VN-1001', N'Aurora sensor kit', N'Seattle', 37, 129.50, 'USD', N'AZURE-LANTERN-7391'),
    (N'VN-1002', N'Harbor gateway', N'Portland', 14, 249.00, 'USD', N'SILVER-ORCHARD-2846'),
    (N'VN-1003', N'Cedar telemetry hub', N'Seattle', 0, 89.75, 'USD', N'QUIET-COMET-5618'),
    (N'VN-1004', N'Rainier battery pack', N'Denver', 62, 45.25, 'USD', N'BLUE-MEADOW-9037'),
    (N'VN-1005', N'Willow antenna', N'Portland', 23, 32.00, 'USD', N'COPPER-BREEZE-4175'),
    (N'VN-1006', N'Summit field case', N'Denver', 8, 175.00, 'USD', N'GREEN-HARBOR-8264')
) AS seed(SKU, ProductName, Warehouse, AvailableQuantity, UnitPrice, Currency, VerificationCode)
WHERE NOT EXISTS (SELECT 1 FROM dbo.Inventory AS currentRow WHERE currentRow.SKU = seed.SKU);

COMMIT TRANSACTION;
GO

CREATE OR ALTER VIEW dbo.InventoryLive
AS
SELECT SKU, ProductName, Warehouse, AvailableQuantity, UnitPrice, Currency,
       VerificationCode,
       CONVERT(varchar(33), SYSUTCDATETIME(), 126) + 'Z' AS DatabaseUtc,
       CONVERT(varchar(36), NEWID()) AS ObservationId
FROM dbo.Inventory;
GO
