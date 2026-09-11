-- =============================================
-- SCRIPT 4 (v2): TABLA STAGING Y PROCEDIMIENTOS ETL
-- Corrige respecto a v1:
--   - staging.stg_clientes_original se conserva casi igual (v1 ya tenía las
--     86 columnas bien nombradas, coinciden con el Excel real) salvo
--     gastos_totales, que ahora es numérico ya limpio (en vez de texto
--     "€ 1,278.64" sin parsear)
--   - sp_cargar_dim_cliente ahora usa tipo_inversion TAL CUAL viene en el
--     archivo como segmento (vía dimensiones.dim_segmento), en vez de
--     inventar una segmentación con umbrales SIO no documentados
--   - sp_cargar_dim_cliente resuelve geografia_sk contra dimensiones.dim_geografia
--     por código de provincia real (antes: geografia_id = 1 fijo, sin fila 1
--     nunca insertada -> violación de integridad referencial garantizada)
--   - Se usa MERGE (upsert) en vez de INSERT+UPDATE por separado
--   - Nueva sp_cargar_fact_producto_cliente: despivota los 45 indicadores
--     ind_* hacia la tabla puente hechos.fact_producto_cliente
--   - sp_ejecutar_etl_completo recibe la fecha de snapshot como parámetro
--     en vez de asumir siempre GETDATE(), y ya no puebla 6 años de
--     dim_tiempo día a día sin necesidad
-- =============================================

USE BancoSabadellDW;
GO

-- =============================================
-- 1. TABLA STAGING (mapea 1:1 las 86 columnas del Excel de origen)
-- =============================================
CREATE TABLE staging.stg_clientes_original (
    id_cliente INT NOT NULL,
    antig INT,
    edad INT,
    totalpasta DECIMAL(15,2),
    impoped DECIMAL(15,2),
    impopeh DECIMAL(15,2),

    -- 45 indicadores de producto (0/1)
    ind_cuentaexpansion TINYINT, ind_cuentaexpansionnegocios TINYINT, ind_cuentaexpansionpremium TINYINT,
    ind_cuentaexperiencia TINYINT, ind_cuentaprimera TINYINT, ind_cuentaproyeccion TINYINT,
    ind_cvautonomos TINYINT, ind_cvdirect TINYINT, ind_cvhabit TINYINT, ind_cvjove TINYINT,
    ind_cvjunior TINYINT, ind_cvmas TINYINT, ind_cvprestige TINYINT, ind_cvsenior TINYINT,
    ind_estalinv TINYINT, ind_estalvi TINYINT, ind_altrescc TINYINT, ind_asvidaestgarcol TINYINT,
    ind_asvidaestulinkc TINYINT, ind_bonsestruc TINYINT, ind_cialp TINYINT, ind_credf TINYINT,
    ind_credv TINYINT, ind_diposit TINYINT, ind_fi TINYINT, ind_fialtent TINYINT, ind_gcfisbp TINYINT,
    ind_gransel TINYINT, ind_hipfix TINYINT, ind_hipmixt TINYINT, ind_hipoteca TINYINT, ind_hipvar TINYINT,
    ind_pp TINYINT, ind_ppassoci TINYINT, ind_ppemp TINYINT, ind_pprest TINYINT, ind_promotor TINYINT,
    ind_renttempcol TINYINT, ind_renttempind TINYINT, ind_rentvehic TINYINT, ind_rentvitindiv TINYINT,
    ind_restorvrf TINYINT, ind_rfixaval TINYINT, ind_varispassiu TINYINT, ind_vrdafix TINYINT,

    renta_final DECIMAL(15,2),

    -- 11 scores SIO
    sio_accionabilidad DECIMAL(6,3), sio_ahorro DECIMAL(6,3), sio_aldia DECIMAL(6,3),
    sio_captacion DECIMAL(6,3), sio_desvinculacion DECIMAL(6,3), sio_financiacion DECIMAL(6,3),
    sio_mediospago DECIMAL(6,3), sio_noaccionable DECIMAL(6,3), sio_proteccion DECIMAL(6,3),
    sio_transaccionalidad DECIMAL(6,3), sio_vinculacion DECIMAL(6,3),

    miembrosfamilia TINYINT NULL,
    menores18 TINYINT NULL,
    entre18_45 TINYINT NULL,
    entre46_65 TINYINT NULL,
    jubilados TINYINT NULL,
    tipofamilia VARCHAR(100) NULL,
    gastos_totales DECIMAL(15,2),      -- ya limpiado desde 'gastos_tot' (texto con formato € en el Excel) por el ETL en Python
    nivren TINYINT,
    residente BIT,
    tipcart SMALLINT,
    prov SMALLINT,
    credit DECIMAL(15,2),
    revolving DECIMAL(15,2),
    tothipo DECIMAL(15,2),
    nominaimp DECIMAL(15,2),
    rdom INT,
    tpv BIT,
    margecomercialut DECIMAL(15,2),
    total_proteccio TINYINT,
    fase SMALLINT,
    tipo_inversion VARCHAR(100),
    num_prod_inversion TINYINT,
    tiene_inversion BIT,

    fecha_carga DATETIME DEFAULT GETDATE(),
    batch_id UNIQUEIDENTIFIER DEFAULT NEWID()
);
GO

CREATE INDEX idx_stg_cliente_id ON staging.stg_clientes_original(id_cliente);
CREATE INDEX idx_stg_batch_id ON staging.stg_clientes_original(batch_id);
GO

-- =============================================
-- 2. CARGA DE DIMENSIÓN CLIENTE (upsert vía MERGE)
-- =============================================
CREATE OR ALTER PROCEDURE staging.sp_cargar_dim_cliente
    @batch_id UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        ;WITH origen AS (
            SELECT
                s.id_cliente,
                CASE
                    WHEN s.edad <= 30 THEN 'Joven'
                    WHEN s.edad BETWEEN 31 AND 45 THEN 'Adulto'
                    WHEN s.edad BETWEEN 46 AND 65 THEN 'Senior'
                    ELSE 'Jubilado'
                END AS grupo_edad,
                CASE s.nivren
                    WHEN 0 THEN 'Sin datos'
                    WHEN 1 THEN 'Bajo'
                    WHEN 2 THEN 'Medio-Bajo'
                    WHEN 3 THEN 'Medio'
                    WHEN 4 THEN 'Medio-Alto'
                    WHEN 5 THEN 'Alto'
                    ELSE 'Sin datos'
                END AS nivel_renta,
                s.residente,
                s.tipofamilia,
                s.miembrosfamilia,
                s.menores18,
                s.entre18_45,
                s.entre46_65,
                s.jubilados,
                s.fase,
                s.tipcart,
                s.tiene_inversion,
                s.num_prod_inversion,
                ISNULL(g.geografia_sk, g0.geografia_sk) AS geografia_sk,
                ISNULL(sg.segmento_sk, sg0.segmento_sk) AS segmento_sk
            FROM staging.stg_clientes_original s
            LEFT JOIN dimensiones.dim_geografia g  ON g.prov_codigo = s.prov
            LEFT JOIN dimensiones.dim_geografia g0 ON g0.prov_codigo = 0            -- fallback "Sin clasificar"
            LEFT JOIN dimensiones.dim_segmento sg  ON sg.tipo_inversion = s.tipo_inversion
            LEFT JOIN dimensiones.dim_segmento sg0 ON sg0.tipo_inversion = N'Sin clasificar'  -- fallback
            WHERE s.batch_id = @batch_id
        )
        MERGE dimensiones.dim_cliente AS destino
        USING origen AS o
        ON destino.id_cliente = o.id_cliente
        WHEN MATCHED THEN UPDATE SET
            grupo_edad           = o.grupo_edad,
            nivel_renta          = o.nivel_renta,
            residente            = o.residente,
            tipo_familia         = o.tipofamilia,
            miembros_familia     = o.miembrosfamilia,
            menores_18           = o.menores18,
            entre_18_45          = o.entre18_45,
            entre_46_65          = o.entre46_65,
            jubilados_familia    = o.jubilados,
            fase_cliente         = o.fase,
            tipcart_codigo       = o.tipcart,
            tiene_inversion      = o.tiene_inversion,
            num_prod_inversion   = o.num_prod_inversion,
            geografia_sk         = o.geografia_sk,
            segmento_sk          = o.segmento_sk,
            fecha_actualizacion  = GETDATE()
        WHEN NOT MATCHED THEN INSERT (
            id_cliente, grupo_edad, nivel_renta, residente, tipo_familia,
            miembros_familia, menores_18, entre_18_45, entre_46_65, jubilados_familia,
            fase_cliente, tipcart_codigo, tiene_inversion, num_prod_inversion,
            geografia_sk, segmento_sk
        ) VALUES (
            o.id_cliente, o.grupo_edad, o.nivel_renta, o.residente, o.tipofamilia,
            o.miembrosfamilia, o.menores18, o.entre18_45, o.entre46_65, o.jubilados,
            o.fase, o.tipcart, o.tiene_inversion, o.num_prod_inversion,
            o.geografia_sk, o.segmento_sk
        );

        COMMIT TRANSACTION;
        PRINT 'Dimensión cliente cargada correctamente';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- =============================================
-- 3. CARGA DE LA TABLA DE HECHOS: fact_cliente_snapshot
-- =============================================
CREATE OR ALTER PROCEDURE staging.sp_cargar_fact_cliente_snapshot
    @batch_id UNIQUEIDENTIFIER,
    @fecha_snapshot DATE
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        EXEC staging.sp_asegurar_fecha_tiempo @fecha = @fecha_snapshot;
        DECLARE @tiempo_id INT = CONVERT(INT, CONVERT(VARCHAR(8), @fecha_snapshot, 112));

        INSERT INTO hechos.fact_cliente_snapshot (
            cliente_sk, tiempo_id, edad, antiguedad_meses,
            total_patrimonio, importe_posicion_deudora, importe_posicion_acreedora,
            renta_final, gastos_totales, margen_comercial, credito_utilizado,
            revolving_utilizado, total_hipoteca, nomina_importe, rdom, tpv, total_proteccion,
            sio_accionabilidad, sio_ahorro, sio_aldia, sio_captacion, sio_desvinculacion,
            sio_financiacion, sio_mediospago, sio_noaccionable, sio_proteccion,
            sio_transaccionalidad, sio_vinculacion, total_productos_activos
        )
        SELECT
            dc.cliente_sk,
            @tiempo_id,
            s.edad,
            s.antig,
            s.totalpasta,
            s.impoped,
            s.impopeh,
            s.renta_final,
            s.gastos_totales,
            s.margecomercialut,
            s.credit,
            s.revolving,
            s.tothipo,
            s.nominaimp,
            s.rdom,
            s.tpv,
            s.total_proteccio,
            s.sio_accionabilidad, s.sio_ahorro, s.sio_aldia, s.sio_captacion, s.sio_desvinculacion,
            s.sio_financiacion, s.sio_mediospago, s.sio_noaccionable, s.sio_proteccion,
            s.sio_transaccionalidad, s.sio_vinculacion,
            (
                s.ind_cuentaexpansion + s.ind_cuentaexpansionnegocios + s.ind_cuentaexpansionpremium +
                s.ind_cuentaexperiencia + s.ind_cuentaprimera + s.ind_cuentaproyeccion +
                s.ind_cvautonomos + s.ind_cvdirect + s.ind_cvhabit + s.ind_cvjove + s.ind_cvjunior +
                s.ind_cvmas + s.ind_cvprestige + s.ind_cvsenior +
                s.ind_estalinv + s.ind_estalvi + s.ind_altrescc + s.ind_asvidaestgarcol +
                s.ind_asvidaestulinkc + s.ind_bonsestruc + s.ind_cialp + s.ind_credf + s.ind_credv +
                s.ind_diposit + s.ind_fi + s.ind_fialtent + s.ind_gcfisbp + s.ind_gransel +
                s.ind_hipfix + s.ind_hipmixt + s.ind_hipoteca + s.ind_hipvar +
                s.ind_pp + s.ind_ppassoci + s.ind_ppemp + s.ind_pprest + s.ind_promotor +
                s.ind_renttempcol + s.ind_renttempind + s.ind_rentvehic + s.ind_rentvitindiv +
                s.ind_restorvrf + s.ind_rfixaval + s.ind_varispassiu + s.ind_vrdafix
            ) AS total_productos_activos
        FROM staging.stg_clientes_original s
        INNER JOIN dimensiones.dim_cliente dc ON dc.id_cliente = s.id_cliente
        WHERE s.batch_id = @batch_id
        AND NOT EXISTS (
            SELECT 1 FROM hechos.fact_cliente_snapshot f
            WHERE f.cliente_sk = dc.cliente_sk AND f.tiempo_id = @tiempo_id
        );

        COMMIT TRANSACTION;
        PRINT 'fact_cliente_snapshot cargada correctamente';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- =============================================
-- 4. CARGA DE LA TABLA PUENTE: fact_producto_cliente (despivote de los ind_*)
-- =============================================
CREATE OR ALTER PROCEDURE staging.sp_cargar_fact_producto_cliente
    @batch_id UNIQUEIDENTIFIER,
    @fecha_snapshot DATE
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @tiempo_id INT = CONVERT(INT, CONVERT(VARCHAR(8), @fecha_snapshot, 112));

        ;WITH despivotado AS (
            SELECT s.id_cliente, u.codigo_indicador, u.valor
            FROM staging.stg_clientes_original s
            CROSS APPLY (VALUES
                ('ind_cuentaexpansion', s.ind_cuentaexpansion), ('ind_cuentaexpansionnegocios', s.ind_cuentaexpansionnegocios),
                ('ind_cuentaexpansionpremium', s.ind_cuentaexpansionpremium), ('ind_cuentaexperiencia', s.ind_cuentaexperiencia),
                ('ind_cuentaprimera', s.ind_cuentaprimera), ('ind_cuentaproyeccion', s.ind_cuentaproyeccion),
                ('ind_cvautonomos', s.ind_cvautonomos), ('ind_cvdirect', s.ind_cvdirect), ('ind_cvhabit', s.ind_cvhabit),
                ('ind_cvjove', s.ind_cvjove), ('ind_cvjunior', s.ind_cvjunior), ('ind_cvmas', s.ind_cvmas),
                ('ind_cvprestige', s.ind_cvprestige), ('ind_cvsenior', s.ind_cvsenior),
                ('ind_estalinv', s.ind_estalinv), ('ind_estalvi', s.ind_estalvi), ('ind_altrescc', s.ind_altrescc),
                ('ind_asvidaestgarcol', s.ind_asvidaestgarcol), ('ind_asvidaestulinkc', s.ind_asvidaestulinkc),
                ('ind_bonsestruc', s.ind_bonsestruc), ('ind_cialp', s.ind_cialp), ('ind_credf', s.ind_credf),
                ('ind_credv', s.ind_credv), ('ind_diposit', s.ind_diposit), ('ind_fi', s.ind_fi),
                ('ind_fialtent', s.ind_fialtent), ('ind_gcfisbp', s.ind_gcfisbp), ('ind_gransel', s.ind_gransel),
                ('ind_hipfix', s.ind_hipfix), ('ind_hipmixt', s.ind_hipmixt), ('ind_hipoteca', s.ind_hipoteca),
                ('ind_hipvar', s.ind_hipvar), ('ind_pp', s.ind_pp), ('ind_ppassoci', s.ind_ppassoci),
                ('ind_ppemp', s.ind_ppemp), ('ind_pprest', s.ind_pprest), ('ind_promotor', s.ind_promotor),
                ('ind_renttempcol', s.ind_renttempcol), ('ind_renttempind', s.ind_renttempind),
                ('ind_rentvehic', s.ind_rentvehic), ('ind_rentvitindiv', s.ind_rentvitindiv),
                ('ind_restorvrf', s.ind_restorvrf), ('ind_rfixaval', s.ind_rfixaval),
                ('ind_varispassiu', s.ind_varispassiu), ('ind_vrdafix', s.ind_vrdafix)
            ) AS u(codigo_indicador, valor)
            WHERE s.batch_id = @batch_id AND u.valor = 1
        )
        INSERT INTO hechos.fact_producto_cliente (cliente_sk, producto_sk, tiempo_id)
        SELECT dc.cliente_sk, dp.producto_sk, @tiempo_id
        FROM despivotado d
        INNER JOIN dimensiones.dim_cliente dc ON dc.id_cliente = d.id_cliente
        INNER JOIN dimensiones.dim_producto dp ON dp.codigo_indicador = d.codigo_indicador
        WHERE NOT EXISTS (
            SELECT 1 FROM hechos.fact_producto_cliente f
            WHERE f.cliente_sk = dc.cliente_sk AND f.producto_sk = dp.producto_sk AND f.tiempo_id = @tiempo_id
        );

        COMMIT TRANSACTION;
        PRINT 'fact_producto_cliente cargada correctamente';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- =============================================
-- 5. PROCEDIMIENTO MAESTRO: ejecuta el ETL completo para un batch ya cargado en staging
-- =============================================
CREATE OR ALTER PROCEDURE staging.sp_ejecutar_etl_completo
    @batch_id UNIQUEIDENTIFIER,
    @fecha_snapshot DATE = NULL,
    @limpiar_staging BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    IF @fecha_snapshot IS NULL SET @fecha_snapshot = CAST(GETDATE() AS DATE);

    PRINT 'Iniciando ETL. Batch: ' + CAST(@batch_id AS VARCHAR(50)) + ' | Snapshot: ' + CONVERT(VARCHAR(10), @fecha_snapshot, 120);

    PRINT '1. Dimensión cliente...';
    EXEC staging.sp_cargar_dim_cliente @batch_id = @batch_id;

    PRINT '2. Tabla de hechos (fact_cliente_snapshot)...';
    EXEC staging.sp_cargar_fact_cliente_snapshot @batch_id = @batch_id, @fecha_snapshot = @fecha_snapshot;

    PRINT '3. Tabla puente de productos (fact_producto_cliente)...';
    EXEC staging.sp_cargar_fact_producto_cliente @batch_id = @batch_id, @fecha_snapshot = @fecha_snapshot;

    IF @limpiar_staging = 1
    BEGIN
        PRINT '4. Limpiando staging del batch...';
        DELETE FROM staging.stg_clientes_original WHERE batch_id = @batch_id;
    END

    PRINT 'ETL completado correctamente';
END;
GO

PRINT 'Procedimientos ETL (v2) creados correctamente';
GO
