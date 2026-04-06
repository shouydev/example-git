-- Asegurarnos de usar utf8mb4 para soportar emojis y caracteres especiales (ñ, tildes)
CREATE DATABASE IF NOT EXISTS andeva_x
CHARACTER SET utf8mb4
COLLATE utf8mb4_unicode_ci;

USE andeva_x;

-- ==========================================
-- MÓDULO 1: NÚCLEO (Multi-tenancy y Seguridad)
-- ==========================================

CREATE TABLE talleres (
    id CHAR(36) PRIMARY KEY,
    ruc VARCHAR(11) NOT NULL UNIQUE COMMENT 'RUC del taller en Perú',
    razon_social VARCHAR(150) NOT NULL,
    nombre_comercial VARCHAR(150) NOT NULL,
    direccion TEXT,
    telefono VARCHAR(20),
    plan_suscripcion ENUM('GRATIS', 'PRO', 'EMPRESARIAL') DEFAULT 'GRATIS',
    esta_activo BOOLEAN DEFAULT TRUE,
    fecha_creacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    fecha_eliminacion TIMESTAMP NULL
) ENGINE=InnoDB;

CREATE TABLE roles (
    id CHAR(36) PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL UNIQUE COMMENT 'Ej: ADMINISTRADOR, MECANICO, RECEPCIONISTA',
    descripcion TEXT,
    fecha_creacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE usuarios (
    id CHAR(36) PRIMARY KEY,
    taller_id CHAR(36) NOT NULL,
    rol_id CHAR(36) NOT NULL,
    correo VARCHAR(100) NOT NULL,
    contrasena_hash VARCHAR(255) NOT NULL,
    nombre_completo VARCHAR(150) NOT NULL,
    esta_activo BOOLEAN DEFAULT TRUE,
    fecha_creacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    fecha_eliminacion TIMESTAMP NULL,
    UNIQUE KEY uk_taller_correo (taller_id, correo),
    FOREIGN KEY (taller_id) REFERENCES talleres(id) ON DELETE CASCADE,
    FOREIGN KEY (rol_id) REFERENCES roles(id) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- ==========================================
-- MÓDULO 2: FLOTA (Clientes y Vehículos)
-- ==========================================

CREATE TABLE clientes (
    id CHAR(36) PRIMARY KEY,
    taller_id CHAR(36) NOT NULL,
    tipo_documento ENUM('DNI', 'RUC', 'CE', 'PASAPORTE') NOT NULL,
    numero_documento VARCHAR(15) NOT NULL,
    nombre VARCHAR(100),
    apellido VARCHAR(100),
    razon_social VARCHAR(150) COMMENT 'Razón social si es RUC',
    telefono VARCHAR(20),
    correo VARCHAR(100),
    direccion TEXT,
    notas TEXT,
    fecha_creacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    fecha_eliminacion TIMESTAMP NULL,
    UNIQUE KEY uk_taller_doc (taller_id, tipo_documento, numero_documento),
    FOREIGN KEY (taller_id) REFERENCES talleres(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE vehiculos (
    id CHAR(36) PRIMARY KEY,
    taller_id CHAR(36) NOT NULL,
    cliente_id CHAR(36) NOT NULL,
    placa VARCHAR(7) NOT NULL COMMENT 'Formato peruano estándar ABC-123 o ABC1D2',
    vin VARCHAR(17) UNIQUE COMMENT 'Vehicle Identification Number',
    marca VARCHAR(50) NOT NULL,
    modelo VARCHAR(50) NOT NULL,
    anio INT UNSIGNED,
    tipo_motor VARCHAR(50) COMMENT 'Ej: Gasolina 1.6L, Diésel 2.0T',
    color VARCHAR(30),
    kilometraje_actual INT UNSIGNED DEFAULT 0,
    notas TEXT,
    fecha_creacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    fecha_eliminacion TIMESTAMP NULL,
    UNIQUE KEY uk_taller_placa (taller_id, placa),
    FOREIGN KEY (taller_id) REFERENCES talleres(id) ON DELETE CASCADE,
    FOREIGN KEY (cliente_id) REFERENCES clientes(id) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- ==========================================
-- MÓDULO 3: IoT (Hardware OBD2 y Telemetría)
-- ==========================================

CREATE TABLE dispositivos_obd2 (
    id CHAR(36) PRIMARY KEY,
    taller_id CHAR(36) NOT NULL,
    vehiculo_id CHAR(36) NULL COMMENT 'Null si está en stock sin asignar',
    mac_address VARCHAR(17) NOT NULL UNIQUE,
    version_firmware VARCHAR(20),
    estado ENUM('ACTIVO', 'INACTIVO', 'FALLA') DEFAULT 'ACTIVO',
    ultimo_ping TIMESTAMP NULL,
    fecha_creacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (taller_id) REFERENCES talleres(id) ON DELETE CASCADE,
    FOREIGN KEY (vehiculo_id) REFERENCES vehiculos(id) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE cat_codigos_dtc (
    codigo VARCHAR(5) PRIMARY KEY COMMENT 'Ej: P0300, B1234, C0001',
    descripcion TEXT NOT NULL COMMENT 'Descripción estandarizada del fallo',
    severidad ENUM('BAJO', 'MEDIO', 'ALTO', 'CRITICO') DEFAULT 'MEDIO'
) ENGINE=InnoDB;

CREATE TABLE alertas_dtc_vehiculo (
    id CHAR(36) PRIMARY KEY,
    taller_id CHAR(36) NOT NULL,
    vehiculo_id CHAR(36) NOT NULL,
    codigo_dtc VARCHAR(5) NOT NULL,
    esta_activa BOOLEAN DEFAULT TRUE COMMENT 'False cuando el mecánico lo resuelve',
    fecha_deteccion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    fecha_resolucion TIMESTAMP NULL,
    FOREIGN KEY (taller_id) REFERENCES talleres(id) ON DELETE CASCADE,
    FOREIGN KEY (vehiculo_id) REFERENCES vehiculos(id) ON DELETE CASCADE,
    FOREIGN KEY (codigo_dtc) REFERENCES cat_codigos_dtc(codigo) ON DELETE RESTRICT,
    INDEX idx_vehiculo_activa (vehiculo_id, esta_activa)
) ENGINE=InnoDB;

-- TABLA DE TELEMETRÍA (Time-Series con Particionamiento)
-- Nota: Para compatibilidad estricta en MySQL, las tablas particionadas NO usan FOREIGN KEY.
CREATE TABLE telemetria_obd2 (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    dispositivo_id CHAR(36) NOT NULL,
    taller_id CHAR(36) NOT NULL,
    fecha_registro DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    rpm INT UNSIGNED,
    velocidad_kmh DECIMAL(5,2),
    temperatura_motor_c DECIMAL(5,2),
    nivel_combustible_pct DECIMAL(5,2),
    voltaje_bateria DECIMAL(4,2),
    posicion_acelerador INT UNSIGNED,
    PRIMARY KEY (id, fecha_registro),
    INDEX idx_dispositivo_fecha (dispositivo_id, fecha_registro),
    INDEX idx_taller_fecha (taller_id, fecha_registro)
) ENGINE=InnoDB
PARTITION BY RANGE COLUMNS (fecha_registro) (
    PARTITION p_2023_q4 VALUES LESS THAN ('2024-01-01 00:00:00'),
    PARTITION p_2024_q1 VALUES LESS THAN ('2024-04-01 00:00:00'),
    PARTITION p_2024_q2 VALUES LESS THAN ('2024-07-01 00:00:00'),
    PARTITION p_2024_q3 VALUES LESS THAN ('2024-10-01 00:00:00'),
    PARTITION p_2024_q4 VALUES LESS THAN ('2025-01-01 00:00:00'),
    PARTITION p_futuro VALUES LESS THAN (MAXVALUE)
);

-- ==========================================
-- MÓDULO 4: OPERACIONES (Órdenes de Trabajo)
-- ==========================================

CREATE TABLE ordenes_trabajo (
    id CHAR(36) PRIMARY KEY,
    taller_id CHAR(36) NOT NULL,
    vehiculo_id CHAR(36) NOT NULL,
    mecanico_asignado_id CHAR(36) NULL,
    numero_interno INT UNSIGNED NOT NULL COMMENT 'Correlativo interno del taller',
    estado ENUM('BORRADOR', 'DIAGNOSTICANDO', 'ESPERANDO_REPUESTOS', 'EN_PROGRESO', 'TERMINADA', 'FACTURADA', 'ANULADA') DEFAULT 'BORRADOR',
    sintoma_reportado TEXT,
    diagnostico_tecnico TEXT,
    fecha_estimada_termino DATE NULL,
    fecha_termino TIMESTAMP NULL,
    fecha_creacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uk_taller_numero (taller_id, numero_interno),
    FOREIGN KEY (taller_id) REFERENCES talleres(id) ON DELETE CASCADE,
    FOREIGN KEY (vehiculo_id) REFERENCES vehiculos(id) ON DELETE RESTRICT,
    FOREIGN KEY (mecanico_asignado_id) REFERENCES usuarios(id) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE tareas_orden_trabajo (
    id CHAR(36) PRIMARY KEY,
    orden_trabajo_id CHAR(36) NOT NULL,
    descripcion TEXT NOT NULL,
    horas_estimadas DECIMAL(5,2) DEFAULT 0.00,
    horas_reales DECIMAL(5,2) DEFAULT 0.00,
    costo_hora_mano_obra DECIMAL(10,2) NOT NULL,
    costo_total_mano_obra DECIMAL(10,2) GENERATED ALWAYS AS (horas_reales * costo_hora_mano_obra) STORED,
    estado ENUM('PENDIENTE', 'EN_PROGRESO', 'TERMINADA') DEFAULT 'PENDIENTE',
    fecha_creacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (orden_trabajo_id) REFERENCES ordenes_trabajo(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ==========================================
-- MÓDULO 5: INVENTARIO Y PROVEEDORES
-- ==========================================

CREATE TABLE cat_categorias_productos (
    id CHAR(36) PRIMARY KEY,
    taller_id CHAR(36) NOT NULL,
    nombre VARCHAR(100) NOT NULL,
    descripcion TEXT,
    fecha_creacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (taller_id) REFERENCES talleres(id) ON DELETE CASCADE,
    UNIQUE KEY uk_taller_categoria (taller_id, nombre)
) ENGINE=InnoDB;

CREATE TABLE productos (
    id CHAR(36) PRIMARY KEY,
    taller_id CHAR(36) NOT NULL,
    categoria_id CHAR(36) NULL,
    sku VARCHAR(50) NOT NULL COMMENT 'Código interno',
    codigo_barras VARCHAR(50) COMMENT 'Código de barras del fabricante',
    nombre VARCHAR(150) NOT NULL,
    descripcion TEXT,
    stock_actual INT UNSIGNED DEFAULT 0 COMMENT 'Denormalizado para lecturas rápidas',
    stock_minimo_alerta INT UNSIGNED DEFAULT 5,
    precio_compra DECIMAL(10,2) NOT NULL COMMENT 'Precio de costo',
    precio_venta DECIMAL(10,2) NOT NULL COMMENT 'Precio al público',
    unidad_medida ENUM('UNIDAD', 'LITRO', 'KILOGRAMO', 'METRO', 'JUEGO') DEFAULT 'UNIDAD',
    esta_activo BOOLEAN DEFAULT TRUE,
    fecha_creacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    fecha_eliminacion TIMESTAMP NULL,
    UNIQUE KEY uk_taller_sku (taller_id, sku),
    FOREIGN KEY (taller_id) REFERENCES talleres(id) ON DELETE CASCADE,
    FOREIGN KEY (categoria_id) REFERENCES cat_categorias_productos(id) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE proveedores (
    id CHAR(36) PRIMARY KEY,
    taller_id CHAR(36) NOT NULL,
    tipo_documento ENUM('DNI', 'RUC') NOT NULL,
    numero_documento VARCHAR(15) NOT NULL COMMENT 'Para proveedores, casi siempre es RUC',
    razon_social VARCHAR(150) NOT NULL COMMENT 'Nombre legal de la empresa distribuidora',
    nombre_comercial VARCHAR(150) COMMENT 'Ej: AutoPartes Lima',
    contacto_principal VARCHAR(100) COMMENT 'Nombre del vendedor',
    telefono VARCHAR(20),
    correo VARCHAR(100),
    direccion TEXT,
    dias_credito INT UNSIGNED DEFAULT 0 COMMENT 'Ej: 15, 30 días. Si es 0, es de contado.',
    linea_credito_limite DECIMAL(12,2) DEFAULT 0.00 COMMENT 'Monto máximo que permite deber',
    esta_activo BOOLEAN DEFAULT TRUE,
    fecha_creacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    fecha_eliminacion TIMESTAMP NULL,
    UNIQUE KEY uk_taller_doc (taller_id, tipo_documento, numero_documento),
    FOREIGN KEY (taller_id) REFERENCES talleres(id) ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='Catálogo de empresas o personas que venden repuestos al taller';

CREATE TABLE movimientos_stock (
    id CHAR(36) PRIMARY KEY,
    taller_id CHAR(36) NOT NULL,
    producto_id CHAR(36) NOT NULL,
    tipo_movimiento ENUM('ENTRADA', 'SALIDA', 'AJUSTE', 'DEVOLUCION') NOT NULL,
    cantidad INT NOT NULL COMMENT 'Positivo para entradas, Negativo para salidas',
    proveedor_id CHAR(36) NULL COMMENT 'Solo se llena si el movimiento es una ENTRADA',
    referencia_id CHAR(36) NULL,
    tipo_referencia VARCHAR(50) NULL COMMENT 'Ej: ORDEN_TRABAJO, COMPRA_PROVEEDOR',
    notas TEXT,
    fecha_creacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (taller_id) REFERENCES talleres(id) ON DELETE CASCADE,
    FOREIGN KEY (producto_id) REFERENCES productos(id) ON DELETE RESTRICT,
    FOREIGN KEY (proveedor_id) REFERENCES proveedores(id) ON DELETE SET NULL,
    INDEX idx_producto_fecha (producto_id, fecha_creacion),
    INDEX idx_proveedor (proveedor_id)
) ENGINE=InnoDB;

CREATE TABLE repuestos_orden_trabajo (
    id CHAR(36) PRIMARY KEY,
    orden_trabajo_id CHAR(36) NOT NULL,
    producto_id CHAR(36) NOT NULL,
    cantidad INT UNSIGNED NOT NULL,
    precio_unitario DECIMAL(10,2) NOT NULL,
    precio_total DECIMAL(10,2) GENERATED ALWAYS AS (cantidad * precio_unitario) STORED,
    fecha_creacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (orden_trabajo_id) REFERENCES ordenes_trabajo(id) ON DELETE CASCADE,
    FOREIGN KEY (producto_id) REFERENCES productos(id) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- ==========================================
-- MÓDULO 6: FACTURACIÓN (Contexto Perú - SUNAT)
-- ==========================================

CREATE TABLE cat_metodos_pago (
    id SMALLINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    codigo VARCHAR(20) NOT NULL UNIQUE COMMENT 'Ej: EFECTIVO, TARJETA, YAPE',
    descripcion VARCHAR(50) NOT NULL
) ENGINE=InnoDB;

INSERT INTO cat_metodos_pago (codigo, descripcion) VALUES
('EFECTIVO', 'Efectivo'), ('TARJETA_CREDITO', 'Tarjeta de Crédito'),
('TARJETA_DEBITO', 'Tarjeta de Débito'), ('YAPE_PLIN', 'Yape / Plin'),
('TRANSFERENCIA', 'Transferencia Bancaria');

CREATE TABLE comprobantes (
    id CHAR(36) PRIMARY KEY,
    taller_id CHAR(36) NOT NULL,
    orden_trabajo_id CHAR(36) NULL,
    cliente_id CHAR(36) NOT NULL,
    serie VARCHAR(4) NOT NULL COMMENT 'Ej: F001, B001',
    correlativo INT UNSIGNED NOT NULL,
    tipo_comprobante ENUM('01', '03', '07', '08') NOT NULL COMMENT '01-Factura, 03-Boleta, 07-NC, 08-ND',
    codigo_moneda CHAR(3) DEFAULT 'PEN',
    tipo_cambio DECIMAL(10,4) DEFAULT 1.0000,
    subtotal_gravadas DECIMAL(12,2) DEFAULT 0.00,
    subtotal_inafectas DECIMAL(12,2) DEFAULT 0.00,
    subtotal_exoneradas DECIMAL(12,2) DEFAULT 0.00,
    monto_igv DECIMAL(12,2) DEFAULT 0.00,
    total_isc DECIMAL(12,2) DEFAULT 0.00,
    total_icbper DECIMAL(12,2) DEFAULT 0.00,
    monto_total DECIMAL(12,2) NOT NULL,
    fecha_emision TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    fecha_vencimiento TIMESTAMP NULL,
    estado_sunat ENUM('PENDIENTE', 'ENVIADO', 'ACEPTADO', 'RECHAZADO', 'ANULADO') DEFAULT 'PENDIENTE',
    ruta_xml_sunat VARCHAR(255) NULL,
    ruta_cdr_sunat VARCHAR(255) NULL,
    descripcion_error_sunat TEXT NULL,
    fecha_creacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uk_taller_serie_corr (taller_id, serie, correlativo),
    FOREIGN KEY (taller_id) REFERENCES talleres(id) ON DELETE CASCADE,
    FOREIGN KEY (orden_trabajo_id) REFERENCES ordenes_trabajo(id) ON DELETE SET NULL,
    FOREIGN KEY (cliente_id) REFERENCES clientes(id) ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE detalles_comprobante (
    id CHAR(36) PRIMARY KEY,
    comprobante_id CHAR(36) NOT NULL,
    numero_linea INT UNSIGNED NOT NULL,
    producto_id CHAR(36) NULL,
    descripcion TEXT NOT NULL,
    cantidad DECIMAL(12,4) NOT NULL,
    codigo_unidad_medida CHAR(3) NOT NULL DEFAULT 'NIU',
    valor_unitario DECIMAL(12,2) NOT NULL,
    porcentaje_igv DECIMAL(5,2) DEFAULT 18.00,
    monto_igv DECIMAL(12,2) GENERATED ALWAYS AS (cantidad * valor_unitario * (porcentaje_igv/100)) STORED,
    valor_total_linea DECIMAL(12,2) GENERATED ALWAYS AS ((cantidad * valor_unitario) + monto_igv) STORED,
    codigo_afectacion CHAR(2) DEFAULT '10',
    FOREIGN KEY (comprobante_id) REFERENCES comprobantes(id) ON DELETE CASCADE,
    FOREIGN KEY (producto_id) REFERENCES productos(id) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE leyendas_comprobante (
    id CHAR(36) PRIMARY KEY,
    comprobante_id CHAR(36) NOT NULL,
    codigo_legenda VARCHAR(3) NOT NULL,
    texto_legenda TEXT NOT NULL,
    FOREIGN KEY (comprobante_id) REFERENCES comprobantes(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE pagos_comprobante (
    id CHAR(36) PRIMARY KEY,
    comprobante_id CHAR(36) NOT NULL,
    metodo_pago_id SMALLINT UNSIGNED NOT NULL,
    monto_pago DECIMAL(12,2) NOT NULL,
    referencia_transaccion VARCHAR(100) NULL,
    fecha_pago TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (comprobante_id) REFERENCES comprobantes(id) ON DELETE CASCADE,
    FOREIGN KEY (metodo_pago_id) REFERENCES cat_metodos_pago(id) ON DELETE RESTRICT
) ENGINE=InnoDB;


-- ==========================================================================================
-- LÓGICA DE NEGOCIO (Procedimientos, Vistas y Eventos)
-- ==========================================================================================

DELIMITER //

-- ==========================================
-- 1. PROCEDIMIENTO: MOVIMIENTO DE INVENTARIO SEGURO
-- ==========================================
CREATE PROCEDURE SP_REGISTRAR_MOVIMIENTO_STOCK(
    IN p_taller_id CHAR(36),
    IN p_producto_id CHAR(36),
    IN p_tipo_movimiento ENUM('ENTRADA', 'SALIDA', 'AJUSTE', 'DEVOLUCION'),
    IN p_cantidad INT,
    IN p_proveedor_id CHAR(36), -- Nuevo parámetro para la compra
    IN p_referencia_id CHAR(36),
    IN p_tipo_referencia VARCHAR(50),
    IN p_notas TEXT,
    OUT p_exitoso BOOLEAN,
    OUT p_mensaje VARCHAR(255)
)
BEGIN
    DECLARE v_stock_actual INT DEFAULT 0;
    DECLARE v_nuevo_stock INT DEFAULT 0;
    DECLARE v_esta_activo BOOLEAN DEFAULT FALSE;

    SET p_exitoso = FALSE;
    SET p_mensaje = 'Error desconocido';

    SELECT stock_actual, esta_activo INTO v_stock_actual, v_esta_activo
    FROM productos
    WHERE id = p_producto_id AND taller_id = p_taller_id
    FOR UPDATE;

    IF v_esta_activo IS NULL THEN
        SET p_mensaje = 'Producto no encontrado o no pertenece a este taller.';
    ELSEIF v_esta_activo = FALSE THEN
        SET p_mensaje = 'El producto está desactivado.';
    ELSEIF p_cantidad <= 0 THEN
        SET p_mensaje = 'La cantidad debe ser mayor a cero.';
    ELSEIF p_tipo_movimiento = 'SALIDA' AND v_stock_actual < p_cantidad THEN
        SET p_mensaje = CONCAT('Stock insuficiente. Stock actual: ', v_stock_actual);
    ELSE
        IF p_tipo_movimiento IN ('ENTRADA', 'DEVOLUCION') THEN
            SET v_nuevo_stock = v_stock_actual + p_cantidad;
        ELSEIF p_tipo_movimiento = 'SALIDA' THEN
            SET v_nuevo_stock = v_stock_actual - p_cantidad;
        ELSEIF p_tipo_movimiento = 'AJUSTE' THEN
            SET v_nuevo_stock = p_cantidad;
        END IF;

        UPDATE productos SET stock_actual = v_nuevo_stock WHERE id = p_producto_id;

        INSERT INTO movimientos_stock (
            id, taller_id, producto_id, tipo_movimiento,
            cantidad, proveedor_id, referencia_id, tipo_referencia, notas
        ) VALUES (
            UUID(), p_taller_id, p_producto_id, p_tipo_movimiento,
            IF(p_tipo_movimiento = 'SALIDA', -p_cantidad, p_cantidad),
            p_proveedor_id, p_referencia_id, p_tipo_referencia, p_notas
        );

        SET p_exitoso = TRUE;
        SET p_mensaje = CONCAT('Movimiento registrado. Nuevo stock: ', v_nuevo_stock);
    END IF;
END //

-- ==========================================
-- 2. PROCEDIMIENTO: INGESTA MASIVA OBD2
-- ==========================================
CREATE PROCEDURE SP_INSERTAR_LOTE_TELEMETRIA(
    IN p_taller_id CHAR(36),
    IN p_dispositivo_id CHAR(36),
    IN p_json_datos JSON
)
BEGIN
    DECLARE v_existe INT DEFAULT 0;

    SELECT COUNT(*) INTO v_existe FROM dispositivos_obd2
    WHERE id = p_dispositivo_id AND taller_id = p_taller_id;

    IF v_existe > 0 THEN
        INSERT INTO telemetria_obd2 (
            dispositivo_id, taller_id, fecha_registro, rpm, velocidad_kmh, temperatura_motor_c, nivel_combustible_pct, voltaje_bateria
        )
        SELECT
            p_dispositivo_id,
            p_taller_id,
            CAST(j.fecha AS DATETIME),
            CAST(j.rpm AS UNSIGNED),
            CAST(j.velocidad AS DECIMAL(5,2)),
            CAST(j.temperatura AS DECIMAL(5,2)),
            CAST(j.combustible AS DECIMAL(5,2)),
            CAST(j.bateria AS DECIMAL(4,2))
        FROM JSON_TABLE(
            p_json_datos,
            '$[*]' COLUMNS(
                fecha VARCHAR(20) PATH '$.fecha',
                rpm INT PATH '$.rpm',
                velocidad DECIMAL(5,2) PATH '$.velocidad',
                temperatura DECIMAL(5,2) PATH '$.temperatura',
                combustible DECIMAL(5,2) PATH '$.combustible',
                bateria DECIMAL(4,2) PATH '$.bateria'
            )
        ) AS j;

        UPDATE dispositivos_obd2 SET ultimo_ping = NOW() WHERE id = p_dispositivo_id;
    END IF;
END //

DELIMITER ;


-- ==========================================
-- 3. VISTAS PARA TABLEROS DE CONTROL (DASHBOARDS)
-- ==========================================

CREATE OR REPLACE VIEW v_resumen_ventas_dashboard AS
SELECT
    t.id AS taller_id,
    DATE_FORMAT(c.fecha_emision, '%Y-%m') AS anio_mes,
    COUNT(c.id) AS total_comprobantes_emitidos,
    SUM(CASE WHEN c.tipo_comprobante = '01' THEN c.monto_total ELSE 0 END) AS total_facturas,
    SUM(CASE WHEN c.tipo_comprobante = '03' THEN c.monto_total ELSE 0 END) AS total_boletas,
    SUM(c.monto_total) AS ingreso_total,
    SUM(c.monto_igv) AS total_impuestos_recaudados
FROM talleres t
JOIN comprobantes c ON t.id = c.taller_id
WHERE c.estado_sunat IN ('ACEPTADO', 'PENDIENTE')
GROUP BY t.id, anio_mes;

CREATE OR REPLACE VIEW v_cuentas_por_cobrar AS
SELECT * FROM (
    SELECT
        c.taller_id,
        c.cliente_id,
        cli.razon_social,
        CONCAT(cli.nombre, ' ', cli.apellido) AS nombre_completo_cliente,
        cli.numero_documento,
        c.id AS comprobante_id,
        CONCAT(c.serie, '-', c.correlativo) AS numero_comprobante,
        c.monto_total AS valor_factura,
        COALESCE(SUM(p.monto_pago), 0) AS total_pagado,
        (c.monto_total - COALESCE(SUM(p.monto_pago), 0)) AS saldo_pendiente,
        c.fecha_emision
    FROM comprobantes c
    JOIN clientes cli ON c.cliente_id = cli.id
    LEFT JOIN pagos_comprobante p ON c.id = p.comprobante_id
    WHERE c.estado_sunat IN ('ACEPTADO', 'PENDIENTE')
    GROUP BY c.id, c.taller_id
) AS subquery_cxc
WHERE saldo_pendiente > 0;

CREATE OR REPLACE VIEW v_salud_vehiculo_iot AS
SELECT
    v.taller_id,
    v.id AS vehiculo_id,
    v.placa,
    CONCAT(cli.nombre, ' ', cli.apellido) AS nombre_propietario,
    cli.telefono AS telefono_propietario,
    COUNT(adv.id) AS cantidad_fallas_activas,
    MAX(CASE WHEN cd.severidad = 'CRITICO' THEN 1 ELSE 0 END) AS tiene_alerta_critica,
    GROUP_CONCAT(DISTINCT CONCAT(cd.codigo, '-', cd.descripcion) SEPARATOR ' | ') AS detalle_fallas_activas,
    MAX(adv.fecha_deteccion) AS ultima_falla_detectada,
    IF(MAX(cd.severidad) = 'CRITICO', 'CRITICO',
        IF(MAX(cd.severidad) = 'ALTO', 'ADVERTENCIA',
            IF(COUNT(adv.id) > 0, 'ATENCION', 'SALUDABLE')
        )
    ) AS estado_salud_vehiculo
FROM vehiculos v
JOIN clientes cli ON v.cliente_id = cli.id
LEFT JOIN alertas_dtc_vehiculo adv ON v.id = adv.vehiculo_id AND adv.esta_activa = TRUE
LEFT JOIN cat_codigos_dtc cd ON adv.codigo_dtc = cd.codigo
GROUP BY v.id;

CREATE OR REPLACE VIEW v_alertas_stock_bajo AS
SELECT
    p.taller_id,
    cp.nombre AS nombre_categoria,
    p.id AS producto_id,
    p.sku,
    p.nombre AS nombre_producto,
    p.stock_actual,
    p.stock_minimo_alerta,
    (p.stock_minimo_alerta - p.stock_actual) AS unidades_faltantes,
    p.precio_compra,
    ((p.stock_minimo_alerta - p.stock_actual) * p.precio_compra) AS inversion_requerida_reposicion
FROM productos p
LEFT JOIN cat_categorias_productos cp ON p.categoria_id = cp.id
WHERE p.esta_activo = TRUE
  AND p.stock_actual <= p.stock_minimo_alerta;

CREATE OR REPLACE VIEW v_rentabilidad_ordenes_trabajo AS
SELECT
    ot.taller_id,
    ot.id AS orden_trabajo_id,
    CONCAT('OT-', LPAD(ot.numero_interno, 4, '0')) AS codigo_ot,
    ot.estado,
    v.placa,
    CONCAT(u.nombre_completo, ' (Mecánico)') AS mecanico_asignado,
    COALESCE(SUM(tot.costo_total_mano_obra), 0) AS costo_total_mano_obra,
    COALESCE(SUM(rot.cantidad * p.precio_compra), 0) AS costo_total_repuestos,
    (COALESCE(SUM(tot.costo_total_mano_obra), 0) + COALESCE(SUM(rot.cantidad * p.precio_compra), 0)) AS costo_operacional_total,
    COALESCE((SELECT SUM(det.valor_total_linea) FROM detalles_comprobante det JOIN comprobantes comp ON det.comprobante_id = comp.id WHERE comp.orden_trabajo_id = ot.id), 0) AS total_facturado,
    (COALESCE((SELECT SUM(det.valor_total_linea) FROM detalles_comprobante det JOIN comprobantes comp ON det.comprobante_id = comp.id WHERE comp.orden_trabajo_id = ot.id), 0) -
     (COALESCE(SUM(tot.costo_total_mano_obra), 0) + COALESCE(SUM(rot.cantidad * p.precio_compra), 0))) AS ganancia_neta
FROM ordenes_trabajo ot
JOIN vehiculos v ON ot.vehiculo_id = v.id
LEFT JOIN usuarios u ON ot.mecanico_asignado_id = u.id
LEFT JOIN tareas_orden_trabajo tot ON ot.id = tot.orden_trabajo_id
LEFT JOIN repuestos_orden_trabajo rot ON ot.id = rot.orden_trabajo_id
LEFT JOIN productos p ON rot.producto_id = p.id
WHERE ot.estado IN ('TERMINADA', 'FACTURADA')
GROUP BY ot.id;


-- ==========================================
-- 4. EVENTO PROGRAMADO (Limpieza de IoT)
-- ==========================================
-- Nota: Requiere que el evento scheduler esté activado en tu servidor MySQL:
-- SET GLOBAL event_scheduler = ON;

CREATE EVENT IF NOT EXISTS EVT_LIMPIAR_TELEMETRIA_VIEJA
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_TIMESTAMP
DO
    DELETE FROM telemetria_obd2
    WHERE fecha_registro < (NOW() - INTERVAL 90 DAY);