-- =============================================
-- SCRIPT 7 (v2): SEGURIDAD, AUDITORÍA Y MONITOREO
-- Corrige respecto a v1 (06_seguridad_monitoreo.sql):
--   - Ya no intenta CREATE ROLE sobre nombres reservados (ese bug estaba en
--     01, no aquí, pero se documenta el prerrequisito de LOGIN a nivel servidor)
--   - auditoria.* ya se crea en 01_crear_base_datos.sql, antes de usarse aquí
--   - Los objetos referenciados (dimensiones.dim_cliente, hechos.fact_cliente_snapshot)
--     coinciden con los nombres reales de v2
--
-- PRERREQUISITO (ejecutar en la base 'master', no aquí, con un usuario con
-- permisos de servidor): crear los LOGIN antes de los CREATE USER de abajo.
--   CREATE LOGIN administrador WITH PASSWORD = '<contraseña-fuerte>';
--   CREATE LOGIN analista      WITH PASSWORD = '<contraseña-fuerte>';
--   CREATE LOGIN etl_user      WITH PASSWORD = '<contraseña-fuerte>';
-- En Azure SQL Database esto se hace conectado a 'master'; luego cada CREATE
-- USER de aquí abajo se ejecuta ya conectado a BancoSabadellDW.
-- =============================================

USE BancoSabadellDW;
GO

-- 1. USUARIOS Y ROLES ------------------------------------------------------

CREATE USER admin_dw FOR LOGIN [administrador] WITH DEFAULT_SCHEMA = dbo;
CREATE USER analista FOR LOGIN [analista] WITH DEFAULT_SCHEMA = analitica;
CREATE USER etl_user FOR LOGIN [etl_user] WITH DEFAULT_SCHEMA = staging;
GO

ALTER ROLE db_owner ADD MEMBER admin_dw;
ALTER ROLE db_datareader ADD MEMBER analista;
ALTER ROLE db_datareader ADD MEMBER etl_user;
ALTER ROLE db_datawriter ADD MEMBER etl_user;
GO

GRANT SELECT, EXECUTE ON SCHEMA::analitica TO analista;
GRANT SELECT ON SCHEMA::dimensiones TO analista;
GRANT SELECT ON SCHEMA::hechos TO analista;
GRANT SELECT, INSERT, UPDATE, DELETE, EXECUTE ON SCHEMA::staging TO etl_user;
GO

-- 2. AUDITORÍA ---------------------------------------------------------------
-- (el esquema auditoria ya existe, creado en 01_crear_base_datos.sql)

CREATE TABLE auditoria.audit_log (
    audit_id        INT IDENTITY(1,1) PRIMARY KEY,
    usuario         VARCHAR(100),
    accion          VARCHAR(50),
    tabla_afectada  VARCHAR(100),
    fecha_hora      DATETIME DEFAULT GETDATE(),
    descripcion     VARCHAR(500)
);
GO

CREATE TABLE auditoria.etl_log (
    etl_log_id            INT IDENTITY(1,1) PRIMARY KEY,
    batch_id              UNIQUEIDENTIFIER,
    proceso                VARCHAR(100),
    estado                 VARCHAR(20),
    fecha_inicio            DATETIME,
    fecha_fin               DATETIME,
    registros_procesados    INT,
    mensaje                 VARCHAR(1000)
);
GO

CREATE TRIGGER dimensiones.trg_audit_dim_cliente
ON dimensiones.dim_cliente
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @accion VARCHAR(50) =
        CASE
            WHEN EXISTS(SELECT 1 FROM inserted) AND EXISTS(SELECT 1 FROM deleted) THEN 'UPDATE'
            WHEN EXISTS(SELECT 1 FROM inserted) THEN 'INSERT'
            ELSE 'DELETE'
        END;

    INSERT INTO auditoria.audit_log (usuario, accion, tabla_afectada, descripcion)
    VALUES (SUSER_NAME(), @accion, 'dim_cliente', @accion + ' sobre dim_cliente');
END;
GO

-- 3. MONITOREO ---------------------------------------------------------------

CREATE OR ALTER PROCEDURE dbo.sp_monitorear_espacio
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        s.name  AS esquema,
        t.name  AS tabla,
        p.rows  AS filas,
        SUM(a.total_pages) * 8 / 1024 AS espacio_mb
    FROM sys.tables t
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    INNER JOIN sys.partitions p ON t.object_id = p.object_id AND p.index_id IN (0,1)
    INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
    WHERE t.is_ms_shipped = 0
    GROUP BY s.name, t.name, p.rows
    ORDER BY espacio_mb DESC;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_mantenimiento_indices
    @fragmentacion_minima INT = 30
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @tabla SYSNAME, @indice SYSNAME, @fragmentacion DECIMAL(5,2), @sql NVARCHAR(1000);

    DECLARE cur_indices CURSOR LOCAL FAST_FORWARD FOR
        SELECT OBJECT_SCHEMA_NAME(ips.object_id) + '.' + OBJECT_NAME(ips.object_id), i.name, ips.avg_fragmentation_in_percent
        FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
        INNER JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
        WHERE ips.avg_fragmentation_in_percent > @fragmentacion_minima AND ips.page_count > 100
              AND i.name IS NOT NULL;

    OPEN cur_indices;
    FETCH NEXT FROM cur_indices INTO @tabla, @indice, @fragmentacion;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @sql = 'ALTER INDEX ' + QUOTENAME(@indice) + ' ON ' + @tabla +
                   CASE WHEN @fragmentacion > 50 THEN ' REBUILD' ELSE ' REORGANIZE' END;
        PRINT @sql;
        EXEC sp_executesql @sql;
        FETCH NEXT FROM cur_indices INTO @tabla, @indice, @fragmentacion;
    END
    CLOSE cur_indices;
    DEALLOCATE cur_indices;
END;
GO

PRINT 'Seguridad, auditoría y monitoreo (v2) configurados correctamente';
GO
