-- =============================================
-- SCRIPT 1 (v2): CREACIÓN DE BASE DE DATOS EN AZURE SQL
-- Corrige respecto a v1:
--   - Ya NO se intenta CREATE ROLE sobre db_datareader / db_datawriter / db_ddladmin
--     (son roles fijos que Azure SQL crea automáticamente; intentarlo falla con
--     "The database principal ... already exists").
--   - Se crean TODOS los esquemas aquí (incluidos analitica y auditoria), antes de
--     que ningún otro script los use — en v1 se creaban al final de otros scripts,
--     después de ya haberlos referenciado.
-- =============================================

-- 1. Crear la base de datos (ejecutar conectado a la base 'master')
--    Ajusta el service objective según tu presupuesto/carga real; S3 es el que
--    ya tenías anotado en config.json / la guía de despliegue.
IF DB_ID('BancoSabadellDW') IS NULL
BEGIN
    CREATE DATABASE BancoSabadellDW
        COLLATE Latin1_General_CI_AS
        (EDITION = 'Standard', SERVICE_OBJECTIVE = 'S3', MAXSIZE = 250 GB);
END
GO

-- 2. Cambiar al contexto de la base de datos creada
--    (En Azure SQL Database esto solo funciona si ya estás conectado a esa base;
--     si usas SSMS/Azure Data Studio, reconéctate a BancoSabadellDW antes de
--     continuar en vez de depender de USE)
USE BancoSabadellDW;
GO

-- 3. Configurar opciones de la base de datos
--    (AUTO_CREATE/UPDATE_STATISTICS ya vienen ON por defecto en Azure SQL DB;
--     se dejan explícitos por claridad/documentación)
ALTER DATABASE CURRENT SET AUTO_CREATE_STATISTICS ON;
ALTER DATABASE CURRENT SET AUTO_UPDATE_STATISTICS ON;
ALTER DATABASE CURRENT SET AUTO_UPDATE_STATISTICS_ASYNC ON;
GO

-- 4. Crear TODOS los esquemas de una vez, antes de que cualquier otro script
--    los use (evita el bug de v1 de crear el esquema al final del archivo que
--    ya lo estaba usando)
CREATE SCHEMA dimensiones AUTHORIZATION dbo;
GO
CREATE SCHEMA hechos AUTHORIZATION dbo;
GO
CREATE SCHEMA staging AUTHORIZATION dbo;
GO
CREATE SCHEMA analitica AUTHORIZATION dbo;
GO
CREATE SCHEMA auditoria AUTHORIZATION dbo;
GO

PRINT 'Base de datos BancoSabadellDW y esquemas creados correctamente';
GO
