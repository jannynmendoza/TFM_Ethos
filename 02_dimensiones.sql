-- =============================================
-- SCRIPT 2 (v2): TABLAS DE DIMENSIONES
-- Corrige respecto a v1:
--   - USE BancoSabadellDW (v1 apuntaba por error a USE Ethos_BD)
--   - Todas las tablas van con el prefijo de esquema dimensiones.*
--   - Nombres consistentes con las FK de 03_tabla_hechos.sql (dim_cliente,
--     dim_producto, dim_tiempo, dim_geografia, dim_segmento)
--   - dim_segmento ahora representa tipo_inversion (el segmento real del
--     archivo), no la segmentación SIO inventada de v1
--   - dim_geografia se reduce a lo que el dato realmente tiene (código de
--     provincia), en vez de ciudad/código postal/densidad poblacional que
--     no existen en el origen
--   - dim_producto es nueva: catálogo de los 45 indicadores ind_*, para
--     soportar la tabla puente hechos.fact_producto_cliente
-- =============================================

USE BancoSabadellDW;
GO

-- =============================================
-- 1. DIMENSIÓN SEGMENTO (tipo_inversion real del archivo)
-- =============================================
CREATE TABLE dimensiones.dim_segmento (
    segmento_sk        INT IDENTITY(1,1) PRIMARY KEY,
    tipo_inversion      VARCHAR(50) NOT NULL UNIQUE,   -- valor tal cual viene en el Excel
    descripcion         VARCHAR(300),
    orden_perfil        TINYINT                        -- para ordenar Juvenil -> Conservador -> Pensionado en informes
);
GO

INSERT INTO dimensiones.dim_segmento (tipo_inversion, descripcion, orden_perfil) VALUES
    (N'Inversión Perfil Juvenil',      N'Clientes de menor vinculación patrimonial; perfil más joven de la cartera (7.9% de la cartera en el Excel de referencia)', 1),
    (N'Inversión Perfil Conservador',  N'Vinculación patrimonial intermedia (10.3% de la cartera en el Excel de referencia)', 2),
    (N'Inversión Perfil Pensionado',   N'Mayor vinculación patrimonial; perfil predominante de la cartera (81.8% de la cartera en el Excel de referencia)', 3),
    (N'Sin clasificar',                N'Valor no reconocido o ausente en tipo_inversion al momento de la carga', 99);
GO

CREATE INDEX idx_segmento_tipo ON dimensiones.dim_segmento(tipo_inversion);
GO

-- =============================================
-- 2. DIMENSIÓN GEOGRAFÍA (código de provincia — es el único dato geográfico real)
-- =============================================
CREATE TABLE dimensiones.dim_geografia (
    geografia_sk        INT IDENTITY(1,1) PRIMARY KEY,
    prov_codigo          SMALLINT NOT NULL UNIQUE,      -- valor de la columna 'prov' del Excel
    provincia_nombre     VARCHAR(60) NOT NULL,
    es_extranjero        BIT NOT NULL DEFAULT 0          -- prov = 99
);
GO

INSERT INTO dimensiones.dim_geografia (prov_codigo, provincia_nombre, es_extranjero) VALUES
(1, N'Álava', 0),
(2, N'Albacete', 0),
(3, N'Alicante/Alacant', 0),
(4, N'Almería', 0),
(5, N'Ávila', 0),
(6, N'Badajoz', 0),
(7, N'Illes Balears', 0),
(8, N'Barcelona', 0),
(9, N'Burgos', 0),
(10, N'Cáceres', 0),
(11, N'Cádiz', 0),
(12, N'Castellón/Castelló', 0),
(13, N'Ciudad Real', 0),
(14, N'Córdoba', 0),
(15, N'A Coruña', 0),
(16, N'Cuenca', 0),
(17, N'Girona', 0),
(18, N'Granada', 0),
(19, N'Guadalajara', 0),
(20, N'Gipuzkoa', 0),
(21, N'Huelva', 0),
(22, N'Huesca', 0),
(23, N'Jaén', 0),
(24, N'León', 0),
(25, N'Lleida', 0),
(26, N'La Rioja', 0),
(27, N'Lugo', 0),
(28, N'Madrid', 0),
(29, N'Málaga', 0),
(30, N'Murcia', 0),
(31, N'Navarra', 0),
(32, N'Ourense', 0),
(33, N'Asturias', 0),
(34, N'Palencia', 0),
(35, N'Las Palmas', 0),
(36, N'Pontevedra', 0),
(37, N'Salamanca', 0),
(38, N'Santa Cruz de Tenerife', 0),
(39, N'Cantabria', 0),
(40, N'Segovia', 0),
(41, N'Sevilla', 0),
(42, N'Soria', 0),
(43, N'Tarragona', 0),
(44, N'Teruel', 0),
(45, N'Toledo', 0),
(46, N'Valencia/València', 0),
(47, N'Valladolid', 0),
(48, N'Bizkaia', 0),
(49, N'Zamora', 0),
(50, N'Zaragoza', 0),
(51, N'Ceuta', 0),
(52, N'Melilla', 0),
(99, N'Extranjero / No residente', 1),
(0, N'Sin clasificar / código no reconocido', 0);
GO

CREATE INDEX idx_geografia_prov ON dimensiones.dim_geografia(prov_codigo);
GO

-- =============================================
-- 3. DIMENSIÓN PRODUCTO (catálogo de los 45 indicadores ind_* del Excel)
-- =============================================
CREATE TABLE dimensiones.dim_producto (
    producto_sk          INT IDENTITY(1,1) PRIMARY KEY,
    codigo_indicador      VARCHAR(50) NOT NULL UNIQUE,   -- nombre exacto de la columna ind_* en el Excel
    nombre_producto       NVARCHAR(150) NOT NULL,
    categoria             VARCHAR(30) NOT NULL           -- Cuentas / Tarjetas / Inversion_Ahorro / Financiacion / Otros
);
GO

INSERT INTO dimensiones.dim_producto (codigo_indicador, nombre_producto, categoria) VALUES
('ind_cuentaexpansion', N'Cuenta Expansión', 'Cuentas'),
('ind_cuentaexpansionnegocios', N'Cuenta Expansión Negocios', 'Cuentas'),
('ind_cuentaexpansionpremium', N'Cuenta Expansión Premium', 'Cuentas'),
('ind_cuentaexperiencia', N'Cuenta Experiencia', 'Cuentas'),
('ind_cuentaprimera', N'Cuenta Primera', 'Cuentas'),
('ind_cuentaproyeccion', N'Cuenta Proyección', 'Cuentas'),
('ind_cvautonomos', N'Tarjeta CV Autónomos', 'Tarjetas'),
('ind_cvdirect', N'Tarjeta CV Direct', 'Tarjetas'),
('ind_cvhabit', N'Tarjeta CV Habit', 'Tarjetas'),
('ind_cvjove', N'Tarjeta CV Jove', 'Tarjetas'),
('ind_cvjunior', N'Tarjeta CV Junior', 'Tarjetas'),
('ind_cvmas', N'Tarjeta CV Mas', 'Tarjetas'),
('ind_cvprestige', N'Tarjeta CV Prestige', 'Tarjetas'),
('ind_cvsenior', N'Tarjeta CV Senior', 'Tarjetas'),
('ind_estalinv', N'Estalvi Inversión', 'Inversion_Ahorro'),
('ind_estalvi', N'Estalvi (Ahorro)', 'Inversion_Ahorro'),
('ind_altrescc', N'Otras Cuentas Corrientes', 'Inversion_Ahorro'),
('ind_asvidaestgarcol', N'Seguro Vida Est. Garantizado Colectivo', 'Inversion_Ahorro'),
('ind_asvidaestulinkc', N'Seguro Vida Est. Unit Linked', 'Inversion_Ahorro'),
('ind_bonsestruc', N'Bonos Estructurados', 'Inversion_Ahorro'),
('ind_cialp', N'CIALP (Cta. Individual Ahorro L.P.)', 'Inversion_Ahorro'),
('ind_credf', N'Crédito Fijo', 'Financiacion'),
('ind_credv', N'Crédito Variable', 'Financiacion'),
('ind_diposit', N'Depósito', 'Inversion_Ahorro'),
('ind_fi', N'Fondo de Inversión', 'Inversion_Ahorro'),
('ind_fialtent', N'Fondo Inversión Alta Rentabilidad', 'Inversion_Ahorro'),
('ind_gcfisbp', N'Gestión Carteras Fiscal BP', 'Inversion_Ahorro'),
('ind_gransel', N'Gran Selección (fondo)', 'Inversion_Ahorro'),
('ind_hipfix', N'Hipoteca Fija', 'Financiacion'),
('ind_hipmixt', N'Hipoteca Mixta', 'Financiacion'),
('ind_hipoteca', N'Hipoteca (general)', 'Financiacion'),
('ind_hipvar', N'Hipoteca Variable', 'Financiacion'),
('ind_pp', N'Plan de Pensiones', 'Inversion_Ahorro'),
('ind_ppassoci', N'Plan Pensiones Asociado', 'Inversion_Ahorro'),
('ind_ppemp', N'Plan Pensiones Empleo', 'Inversion_Ahorro'),
('ind_pprest', N'Plan Pensiones Restringido', 'Inversion_Ahorro'),
('ind_promotor', N'Cliente Promotor', 'Otros'),
('ind_renttempcol', N'Renta Temporal Colectiva', 'Inversion_Ahorro'),
('ind_renttempind', N'Renta Temporal Individual', 'Inversion_Ahorro'),
('ind_rentvehic', N'Renta Vehículo', 'Inversion_Ahorro'),
('ind_rentvitindiv', N'Renta Vitalicia Individual', 'Inversion_Ahorro'),
('ind_restorvrf', N'Restorvrf (fondo)', 'Inversion_Ahorro'),
('ind_rfixaval', N'Renta Fija Avalada', 'Inversion_Ahorro'),
('ind_varispassiu', N'Vari. Pasiu (fondo)', 'Inversion_Ahorro'),
('ind_vrdafix', N'VRDA Fijo', 'Inversion_Ahorro');
GO

CREATE INDEX idx_producto_categoria ON dimensiones.dim_producto(categoria);
GO

-- =============================================
-- 4. DIMENSIÓN TIEMPO (una fila por fecha de carga/snapshot)
-- =============================================
CREATE TABLE dimensiones.dim_tiempo (
    tiempo_id             INT PRIMARY KEY,               -- formato YYYYMMDD
    fecha                 DATE NOT NULL UNIQUE,
    anio                  SMALLINT NOT NULL,
    trimestre             TINYINT NOT NULL,
    mes                   TINYINT NOT NULL,
    dia                   TINYINT NOT NULL,
    dia_semana            TINYINT NOT NULL,              -- 1=Domingo ... 7=Sábado (DATEPART WEEKDAY por defecto)
    nombre_dia_semana     VARCHAR(20),
    nombre_mes            VARCHAR(20),
    es_fin_semana         BIT
);
GO

CREATE INDEX idx_tiempo_anio_mes ON dimensiones.dim_tiempo(anio, mes);
GO

-- Procedimiento para insertar una fecha de snapshot si no existe todavía
-- (se llama desde el ETL, una vez por carga; sustituye al bucle diario 2020-2025
--  de v1, que poblaba 6 años de fechas sin que hicieran falta)
CREATE OR ALTER PROCEDURE staging.sp_asegurar_fecha_tiempo
    @fecha DATE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @tiempo_id INT = CONVERT(INT, CONVERT(VARCHAR(8), @fecha, 112));

    IF NOT EXISTS (SELECT 1 FROM dimensiones.dim_tiempo WHERE tiempo_id = @tiempo_id)
    BEGIN
        INSERT INTO dimensiones.dim_tiempo (
            tiempo_id, fecha, anio, trimestre, mes, dia,
            dia_semana, nombre_dia_semana, nombre_mes, es_fin_semana
        )
        VALUES (
            @tiempo_id, @fecha, YEAR(@fecha), DATEPART(QUARTER, @fecha), MONTH(@fecha), DAY(@fecha),
            DATEPART(WEEKDAY, @fecha), DATENAME(WEEKDAY, @fecha), DATENAME(MONTH, @fecha),
            CASE WHEN DATEPART(WEEKDAY, @fecha) IN (1, 7) THEN 1 ELSE 0 END
        );
    END
END;
GO

-- =============================================
-- 5. DIMENSIÓN CLIENTE
-- =============================================
CREATE TABLE dimensiones.dim_cliente (
    cliente_sk            INT IDENTITY(1,1) PRIMARY KEY,
    id_cliente             INT NOT NULL UNIQUE,           -- clave de negocio (columna id_cliente del Excel)

    -- Atributos descriptivos (recalculados en cada carga; ver ETL)
    grupo_edad             VARCHAR(20),                    -- Joven / Adulto / Senior / Jubilado, a partir de 'edad'
    nivel_renta            VARCHAR(20),                    -- decodificado de 'nivren' (0-5)
    residente               BIT,                            -- columna 'residente'
    tipo_familia            VARCHAR(100) NULL,              -- puede venir NULL (49.8% de los casos en el Excel de referencia)
    miembros_familia        TINYINT NULL,
    menores_18              TINYINT NULL,
    entre_18_45             TINYINT NULL,
    entre_46_65             TINYINT NULL,
    jubilados_familia       TINYINT NULL,
    fase_cliente            SMALLINT NULL,                  -- código crudo 'fase' (sin tabla de equivalencias en origen)
    tipcart_codigo          SMALLINT NULL,                  -- código crudo 'tipcart' (sin tabla de equivalencias en origen)
    tiene_inversion         BIT,
    num_prod_inversion      TINYINT,

    -- Claves foráneas a otras dimensiones
    geografia_sk            INT NOT NULL,
    segmento_sk              INT NOT NULL,

    fecha_carga             DATETIME DEFAULT GETDATE(),
    fecha_actualizacion     DATETIME DEFAULT GETDATE(),

    CONSTRAINT fk_dimcliente_geografia FOREIGN KEY (geografia_sk) REFERENCES dimensiones.dim_geografia(geografia_sk),
    CONSTRAINT fk_dimcliente_segmento FOREIGN KEY (segmento_sk) REFERENCES dimensiones.dim_segmento(segmento_sk)
);
GO

CREATE INDEX idx_cliente_grupo_edad ON dimensiones.dim_cliente(grupo_edad);
CREATE INDEX idx_cliente_nivel_renta ON dimensiones.dim_cliente(nivel_renta);
CREATE INDEX idx_cliente_segmento ON dimensiones.dim_cliente(segmento_sk);
CREATE INDEX idx_cliente_geografia ON dimensiones.dim_cliente(geografia_sk);
GO

PRINT 'Tablas de dimensiones (v2) creadas y semillas cargadas correctamente';
GO
