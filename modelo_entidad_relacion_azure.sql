-- ======================================================
-- MODELO ENTIDAD-RELACIÓN PARA BANCO SABADELL - AZURE SQL
-- Basado en datasabadell_actualizado.xlsx y EntregaNoteboookTFM_.ipynb
-- Fecha: $(Get-Date -Format "dd/MM/yyyy")
-- ======================================================

-- ======================================================
-- 1. CREACIÓN DE LA BASE DE DATOS
-- ======================================================

CREATE DATABASE BancoSabadell_ETL;
GO

USE BancoSabadell_ETL;
GO

-- ======================================================
-- 2. TABLA PRINCIPAL DE CLIENTES (Datos demográficos y de perfil)
-- ======================================================

CREATE TABLE Clientes (
    id_cliente INT PRIMARY KEY,
    antig INT NOT NULL,                           -- Antigüedad del cliente (días)
    edad DECIMAL(5,2) NOT NULL,                   -- Edad del cliente
    totalpasta DECIMAL(15,2) NOT NULL,            -- Patrimonio total gestionado (€)
    impoped DECIMAL(15,2) NOT NULL,               -- Importe operaciones débito
    impopeh DECIMAL(15,2) NOT NULL,               -- Importe operaciones haber
    nivren TINYINT NOT NULL,                      -- Nivel de renta (0-5)
    renta_final DECIMAL(15,2) NOT NULL,           -- Renta estimada final
    gastos_tot DECIMAL(15,2) NOT NULL,            -- Gastos totales
    prov INT NOT NULL,                            -- Provincia
    credit DECIMAL(15,2) NOT NULL,                -- Crédito
    revolving DECIMAL(15,2) NOT NULL,             -- Revolving
    tothipo DECIMAL(15,2) NOT NULL,               -- Total hipotecas
    nominaimp DECIMAL(15,2) NOT NULL,             -- Importe nómina
    rdom INT NOT NULL,                            -- Relación domiciliación
    tpv TINYINT NOT NULL,                         -- TPV (Terminal Punto de Venta)
    margecomercialut DECIMAL(15,2) NOT NULL,      -- Margen comercial utilidad
    total_proteccio DECIMAL(10,2) NOT NULL,       -- Total protección
    fase TINYINT NOT NULL,                        -- Fase (0-30)
    fecha_carga DATETIME DEFAULT GETDATE()        -- Fecha de carga
);

-- ======================================================
-- 3. TABLA DE INDICADORES DE PRODUCTOS (Columnas ind_*)
-- ======================================================

CREATE TABLE ProductosClientes (
    id_registro INT IDENTITY(1,1) PRIMARY KEY,
    id_cliente INT NOT NULL,
    tipo_producto VARCHAR(50) NOT NULL,           -- Nombre del indicador
    tiene_producto BIT NOT NULL,                  -- 0 = No tiene, 1 = Tiene
    fecha_carga DATETIME DEFAULT GETDATE(),
    
    FOREIGN KEY (id_cliente) REFERENCES Clientes(id_cliente),
    CONSTRAINT UC_ClienteProducto UNIQUE (id_cliente, tipo_producto)
);

-- Índice para mejor performance en consultas por cliente
CREATE INDEX IX_ProductosClientes_Cliente ON ProductosClientes(id_cliente);
CREATE INDEX IX_ProductosClientes_Producto ON ProductosClientes(tipo_producto);

-- ======================================================
-- 4. TABLA DE SEGMENTACIÓN Y CATEGORIZACIÓN (Variables derivadas del notebook)
-- ======================================================

CREATE TABLE SegmentacionClientes (
    id_segmentacion INT IDENTITY(1,1) PRIMARY KEY,
    id_cliente INT NOT NULL,
    segmento_edad VARCHAR(20) NOT NULL,           -- Joven (<=30), Adulto (31-45), Senior (46-65), Jubilado (65+)
    tipo_inversion
	num_prod_inversion INT NOT NULL,              -- Número de productos de inversión
    tiene_inversion BIT NOT NULL,                 -- 0 = Sin inversión, 1 = Con inversión
    
    FOREIGN KEY (id_cliente) REFERENCES Clientes(id_cliente),
    CONSTRAINT UC_ClienteSegmentacion UNIQUE (id_cliente)
);

-- ======================================================
-- 5. TABLA DE SIO (SERVICIOS DE INVERSIÓN Y OPERACIONES)
-- ======================================================

CREATE TABLE SIOServicios (
    id_sio INT IDENTITY(1,1) PRIMARY KEY,
    id_cliente INT NOT NULL,
    sio_vinculacion DECIMAL(10,2) NOT NULL,       -- SIO vinculación
    sio_inversion DECIMAL(10,2) NOT NULL,         -- SIO inversión
    sio_cuenta DECIMAL(10,2) NOT NULL,            -- SIO cuenta
    sio_financiacion DECIMAL(10,2) NOT NULL,      -- SIO financiación
    sio_proteccion DECIMAL(10,2) NOT NULL,        -- SIO protección
    fecha_calculo DATETIME DEFAULT GETDATE(),
    
    FOREIGN KEY (id_cliente) REFERENCES Clientes(id_cliente),
    CONSTRAINT UC_ClienteSIO UNIQUE (id_cliente)
);

-- ======================================================
-- 6. TABLA DE LOGS DE CARGA (Auditoría)
-- ======================================================

CREATE TABLE LogsCargaETL (
    id_log INT IDENTITY(1,1) PRIMARY KEY,
    fecha_carga DATETIME DEFAULT GETDATE(),
    origen_datos VARCHAR(100) NOT NULL,           -- Ej: 'datasabadell_actualizado.xlsx'
    numero_registros INT NOT NULL,
    estado VARCHAR(20) NOT NULL,                  -- COMPLETADO, ERROR, PARCIAL
    mensaje VARCHAR(500) NULL,
    duracion_segundos INT NULL
);

-- ======================================================
-- 7. VISTAS PARA ANÁLISIS
-- ======================================================

-- Vista 1: Perfil completo del cliente
CREATE VIEW vw_PerfilCompletoCliente AS
SELECT 
    c.id_cliente,
    c.edad,
    c.totalpasta,
    c.nivren,
    s.segmento_edad,
    s.num_prod_inversion,
    s.tiene_inversion,
    si.sio_vinculacion,
    si.sio_inversion,
    -- Conteo de productos por tipo
    (SELECT COUNT(*) FROM ProductosClientes pc 
     WHERE pc.id_cliente = c.id_cliente AND pc.tiene_producto = 1 
     AND pc.tipo_producto LIKE 'ind_cuenta%') AS num_cuentas,
    (SELECT COUNT(*) FROM ProductosClientes pc 
     WHERE pc.id_cliente = c.id_cliente AND pc.tiene_producto = 1 
     AND pc.tipo_producto LIKE 'ind_cv%') AS num_tarjetas
FROM Clientes c
LEFT JOIN SegmentacionClientes s ON c.id_cliente = s.id_cliente
LEFT JOIN SIOServicios si ON c.id_cliente = si.id_cliente;
GO


-- Vista 3: Productos más comunes
CREATE VIEW vw_ProductosMasComunes AS
SELECT 
    tipo_producto,
    COUNT(*) AS num_clientes,
    COUNT(*) * 100.0 / (SELECT COUNT(*) FROM Clientes) AS porcentaje_clientes
FROM ProductosClientes
WHERE tiene_producto = 1
GROUP BY tipo_producto
ORDER BY num_clientes DESC;
GO

-- ======================================================
-- 8. PROCEDIMIENTOS ALMACENADOS PARA CARGA DE DATOS
-- ======================================================

-- Procedimiento para cargar un cliente
CREATE PROCEDURE sp_CargarCliente
    @id_cliente INT,
    @antig INT,
    @edad DECIMAL(5,2),
    @totalpasta DECIMAL(15,2),
    @impoped DECIMAL(15,2),
    @impopeh DECIMAL(15,2),
    @nivren TINYINT,
    @renta_final DECIMAL(15,2),
    @gastos_tot DECIMAL(15,2),
    @prov INT,
    @credit DECIMAL(15,2),
    @revolving DECIMAL(15,2),
    @tothipo DECIMAL(15,2),
    @nominaimp DECIMAL(15,2),
    @rdom INT,
    @tpv TINYINT,
    @margecomercialut DECIMAL(15,2),
    @total_proteccio DECIMAL(10,2),
    @fase TINYINT
AS
BEGIN
    SET NOCOUNT ON;
    
    BEGIN TRY
        -- Insertar en tabla Clientes
        INSERT INTO Clientes (
            id_cliente, antig, edad, totalpasta, impoped, impopeh, nivren,
            renta_final, gastos_tot, prov, credit, revolving, tothipo,
            nominaimp, rdom, tpv, margecomercialut, total_proteccio, fase
        ) VALUES (
            @id_cliente, @antig, @edad, @totalpasta, @impoped, @impopeh, @nivren,
            @renta_final, @gastos_tot, @prov, @credit, @revolving, @tothipo,
            @nominaimp, @rdom, @tpv, @margecomercialut, @total_proteccio, @fase
        );
        
        PRINT 'Cliente ' + CAST(@id_cliente AS VARCHAR) + ' cargado exitosamente';
    END TRY
    BEGIN CATCH
        PRINT 'Error al cargar cliente ' + CAST(@id_cliente AS VARCHAR) + ': ' + ERROR_MESSAGE();
        THROW;
    END CATCH
END;
GO

-- Procedimiento para registrar log de carga
CREATE PROCEDURE sp_RegistrarLogCarga
    @origen_datos VARCHAR(100),
    @numero_registros INT,
    @estado VARCHAR(20),
    @mensaje VARCHAR(500) = NULL,
    @duracion_segundos INT = NULL
AS
BEGIN
    INSERT INTO LogsCargaETL (origen_datos, numero_registros, estado, mensaje, duracion_segundos)
    VALUES (@origen_datos, @numero_registros, @estado, @mensaje, @duracion_segundos);
END;
GO

-- ======================================================
-- 9. SCRIPT DE CARGA INICIAL (EJEMPLO)
-- ======================================================

/*
-- Ejemplo de carga inicial desde Python:
-- 1. Leer archivo Excel con pandas
-- 2. Para cada fila, llamar a sp_CargarCliente
-- 3. Insertar productos en tabla ProductosClientes
-- 4. Calcular segmentación e insertar en SegmentacionClientes
-- 5. Registrar log de carga

-- Código Python de ejemplo:
import pandas as pd
import pyodbc

# Conexión a Azure SQL
conn_str = (
    "Driver={ODBC Driver 18 for SQL Server};"
    "Server=tcp:tu-servidor.database.windows.net,1433;"
    "Database=BancoSabadell_ETL;"
    "Uid=tu-usuario;"
    "Pwd=tu-contraseña;"
    "Encrypt=yes;"
    "TrustServerCertificate=no;"
    "Connection Timeout=30;"
)

conn = pyodbc.connect(conn_str)
cursor = conn.cursor()

# Leer archivo Excel
df = pd.read_excel('datasabadell_actualizado.xlsx')

# Cargar clientes
for _, row in df.iterrows():
    cursor.execute("EXEC sp_CargarCliente ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?",
                   row['id_cliente'], row['antig'], row['edad'], row['totalpasta'],
                   row['impoped'], row['impopeh'], row['nivren'], row['renta_final'],
                   row['gastos_tot'], row['prov'], row['credit'], row['revolving'],
                   row['tothipo'], row['nominaimp'], row['rdom'], row['tpv'],
                   row['margecomercialut'], row['total_proteccio'], row['fase'])

conn.commit()
conn.close()
*/

-- ======================================================
-- 10. DIAGRAMA ENTIDAD-RELACIÓN (DESCRIPCIÓN)
-- ======================================================

/*
DIAGRAMA ENTIDAD-RELACIÓN:

Clientes (1) ----- (1) SegmentacionClientes
    |                     |
    |                     |
    | (1)                 |
    |                     |
    v                     v
ProductosClientes (M)     SIOServicios (1)

RELACIONES:
1. Un Cliente tiene una Segmentación (1:1)
2. Un Cliente tiene múltiples Productos (1:M)  
3. Un Cliente tiene un registro SIO (1:1)

CARDINALIDAD:
- Clientes → SegmentacionClientes: 1:1
- Clientes → ProductosClientes: 1:M
- Clientes → SIOServicios: 1:1

CLAVES:
- Clientes: id_cliente (PK)
- ProductosClientes: id_registro (PK), id_cliente (FK)
- SegmentacionClientes: id_segmentacion (PK), id_cliente (FK)
- SIOServicios: id_sio (PK), id_cliente (FK)
*/

-- ======================================================
-- 11. NOTAS DE IMPLEMENTACIÓN
-- ======================================================

/*
NOTAS IMPORTANTES:

1. OPTIMIZACIÓN PARA AZURE:
   - Usar índices apropiados para consultas frecuentes
   - Considerar particionamiento por fecha para tablas grandes
   - Configurar retención de datos según políticas de negocio

2. SEGURIDAD:
   - Implementar roles específicos (lectura, escritura, administración)
   - Usar Always Encrypted para datos sensibles
   - Configurar auditoría de acceso

3. MANTENIMIENTO:
   - Programar limpieza de logs antiguos
   - Monitorear espacio de almacenamiento
   - Realizar backup regularmente

5. ESCALABILIDAD:
   - Este modelo soporta hasta millones de clientes
   - Considerar Azure SQL Database con escalado automático
   - Evaluar uso de Azure Synapse Analytics para análisis avanzado
*/

PRINT 'Modelo Entidad-Relación creado exitosamente.';
PRINT 'Base de datos: BancoSabadell_ETL';
PRINT 'Tablas creadas: 5';
PRINT 'Vistas creadas: 3';
PRINT 'Procedimientos almacenados: 2';