# Proyecto 03 — NYC Taxi Data Pipeline (Spark + Snowflake)

**Universidad San Francisco de Quito — Data Mining**

## Arquitectura

```
┌─────────────────────┐     ┌───────────────────────────────┐     ┌──────────────────────────┐
│  NYC TLC Parquet     │     │  Docker: spark-notebook       │     │  Snowflake               │
│  (2015–2025)         │────▶│  Jupyter + PySpark            │────▶│                          │
│  Yellow + Green      │     │  Puerto 8888 (Jupyter)        │     │  NYC_TAXI_P3.RAW         │
│                      │     │  Puerto 4040 (Spark UI)       │     │    ├─ TRIPS_RAW          │
└─────────────────────┘     └───────────────────────────────┘     │    ├─ TAXI_ZONE_LOOKUP   │
                                                                    │    └─ INGESTION_LOG      │
                                                                    │                          │
                                                                    │  NYC_TAXI_P3.ANALYTICS   │
                                                                    │    └─ OBT_TRIPS          │
                                                                    └──────────────────────────┘
```

**Flujo:** Parquet (2015–2025, Yellow/Green) → Spark (backfill mensual) → Snowflake RAW → enriquecimiento/unificación → ANALYTICS.OBT_TRIPS (One Big Table)

## Objetos en Snowflake

| Objeto | Nombre completo | Descripción |
|--------|----------------|-------------|
| Database | `NYC_TAXI_P3` | Base de datos del proyecto |
| Schema | `NYC_TAXI_P3.RAW` | Aterrizaje espejo del origen |
| Schema | `NYC_TAXI_P3.ANALYTICS` | Tabla analítica OBT |
| Table | `RAW.TRIPS_RAW` | Viajes yellow+green con metadatos de ingesta |
| Table | `RAW.TAXI_ZONE_LOOKUP` | Mapeo LocationID → zona/borough |
| Table | `RAW.INGESTION_LOG` | Auditoría de cada carga mensual |
| Table | `ANALYTICS.OBT_TRIPS` | One Big Table desnormalizada |

## Variables de ambiente

Definidas en `.env` (gitignored) y `.env.example` (committed):

| Variable | Propósito |
|----------|-----------|
| `SF_ACCOUNT` | Identificador de cuenta Snowflake |
| `SF_USER` | Usuario Snowflake |
| `SF_PASSWORD` | Contraseña Snowflake |
| `SF_WAREHOUSE` | Warehouse de cómputo |
| `SF_DATABASE` | Base de datos (`NYC_TAXI_P3`) |
| `SF_SCHEMA_RAW` | Esquema raw (`RAW`) |
| `SF_SCHEMA_ANALYTICS` | Esquema analytics (`ANALYTICS`) |
| `SF_ROLE` | Rol de Snowflake |
| `PARQUET_BASE_URL` | URL base de archivos Parquet |
| `TAXI_ZONE_URL` | URL del CSV de Taxi Zone Lookup |
| `YEAR_START` / `YEAR_END` | Rango de años a procesar |
| `MONTH_START` / `MONTH_END` | Rango de meses a procesar |
| `SERVICES` | Servicios a procesar (`yellow,green`) |
| `RUN_ID` | Identificador único de ejecución |
| `BATCH_SIZE` | Tamaño de lote |
| `ENABLE_VALIDATION` | Flag de validación |

## Diseño del esquema RAW

### `TRIPS_RAW`
Tabla unificada para Yellow y Green con todas las columnas de ambos esquemas:
- **Yellow:** `tpep_pickup_datetime`, `tpep_dropoff_datetime`
- **Green:** `lpep_pickup_datetime`, `lpep_dropoff_datetime`, `trip_type`, `ehail_fee`
- **Comunes:** `VendorID`, `passenger_count`, `trip_distance`, `PULocationID`, `DOLocationID`, tarifas
- **Metadatos de ingesta:** `run_id`, `service_type`, `source_year`, `source_month`, `ingested_at_utc`, `source_path`

### `INGESTION_LOG`
Registro de auditoría por cada mes/servicio cargado:
- `run_id`, `service_type`, `source_year`, `source_month`
- `rows_loaded`, `rows_in_source`, `status`, `error_message`
- `started_at_utc`, `finished_at_utc`

### Idempotencia (RAW)
Estrategia: **DELETE + INSERT** por clave natural `(service_type, source_year, source_month)`.
Antes de cargar un mes, se eliminan las filas existentes para ese mes/servicio.

## Diseño de la OBT (`ANALYTICS.OBT_TRIPS`)

**Grano:** 1 fila = 1 viaje.

| Categoría | Columnas |
|-----------|----------|
| **Tiempo** | `pickup_datetime`, `dropoff_datetime`, `pickup_date`, `pickup_hour`, `dropoff_date`, `dropoff_hour`, `day_of_week`, `month`, `year` |
| **Ubicación** | `pu_location_id`, `pu_zone`, `pu_borough`, `do_location_id`, `do_zone`, `do_borough` |
| **Servicio/Códigos** | `service_type`, `vendor_id`, `vendor_name`, `rate_code_id`, `rate_code_desc`, `payment_type`, `payment_type_desc`, `trip_type` |
| **Viaje** | `passenger_count`, `trip_distance`, `store_and_fwd_flag` |
| **Tarifas** | `fare_amount`, `extra`, `mta_tax`, `tip_amount`, `tolls_amount`, `improvement_surcharge`, `congestion_surcharge`, `airport_fee`, `total_amount` |
| **Derivadas** | `trip_duration_min`, `avg_speed_mph`, `tip_pct` |
| **Lineage** | `run_id`, `ingested_at_utc`, `source_service`, `source_year`, `source_month` |

### Derivadas — reglas de cálculo

| Columna | Fórmula | Manejo de nulos/ceros |
|---------|---------|----------------------|
| `trip_duration_min` | `DATEDIFF('minute', pickup_datetime, dropoff_datetime)` | NULL si algún datetime es NULL |
| `avg_speed_mph` | `trip_distance / (trip_duration_min / 60)` | NULL si duración ≤ 0 o distancia ≤ 0 |
| `tip_pct` | `(tip_amount / fare_amount) × 100` | NULL si fare_amount ≤ 0 |

### Idempotencia (OBT)
Estrategia: **mode=overwrite** — reconstrucción completa en cada ejecución.

## Calidad y auditoría

Validaciones aplicadas en `04_validaciones_y_exploracion.ipynb`:

| Regla | Qué se valida |
|-------|---------------|
| Nulos esenciales | `pickup_datetime`, `pu_location_id`, `service_type`, `total_amount`, `run_id` |
| Rangos lógicos | `trip_duration_min ≥ 0`, `trip_distance ≥ 0`, `total_amount ≥ 0` |
| Coherencia fechas | `dropoff_datetime ≥ pickup_datetime` |
| Outliers | Duración > 24h, distancia > 500 mi, velocidad > 100 mph, propina > 100% |
| Cobertura | Conteos por `service_type` / `year` / `month` |
| Auditoría | `INGESTION_LOG`: filas cargadas, status, tiempos por cada mes/servicio |

## Notebooks (orden de ejecución)

| # | Archivo | Propósito |
|---|---------|-----------|
| 1 | `01_ingest_raw.ipynb` | Descarga Parquet 2015–2025 (Yellow/Green), carga Taxi Zones, escribe a RAW con auditoría. Idempotente. |
| 2 | `02_enriquecimiento_y_unificacion.ipynb` | Explora RAW, muestra JOIN con zonas, unificación Yellow/Green, normalización de catálogos. |
| 3 | `03_construccion_obt.ipynb` | Construye `OBT_TRIPS` con derivadas y metadatos. Verifica idempotencia. |
| 4 | `04_validaciones_y_exploracion.ipynb` | Validaciones de calidad: nulos, rangos, coherencia, outliers, cobertura. |
| 5 | `05_data_analysis.ipynb` | 20 preguntas de negocio respondidas con Spark sobre la OBT. |

## Matriz de cobertura 2015–2025

> **Nota:** Completar esta tabla después de ejecutar notebook 01. Marcar ✅ (ok), ❌ (falta), ⚠️ (fallido).

| Año | Yellow | Green |
|-----|--------|-------|
| 2015 | | |
| 2016 | | |
| 2017 | | |
| 2018 | | |
| 2019 | | |
| 2020 | | |
| 2021 | | |
| 2022 | | |
| 2023 | | |
| 2024 | | |
| 2025 | | |

## Pasos para levantar la infraestructura

### Prerequisitos
- Docker y Docker Compose instalados
- Cuenta de Snowflake con las tablas creadas (ver sección "Objetos en Snowflake")

### 1. Configurar credenciales
```bash
# Copiar template y editar con credenciales reales
cp .env.example .env
# Editar .env con tu SF_ACCOUNT, SF_USER, SF_PASSWORD
```

### 2. Construir y levantar Docker
```bash
docker-compose build
docker-compose up -d
```

### 3. Acceder a Jupyter Lab
Abrir en navegador: **http://localhost:8888**
(Sin token — configurado con `--NotebookApp.token=''`)

### 4. Ejecutar notebooks en orden
1. `01_ingest_raw.ipynb` — Ingesta RAW (⚠️ toma tiempo, muchos GB)
2. `02_enriquecimiento_y_unificacion.ipynb` — Exploración y enriquecimiento
3. `03_construccion_obt.ipynb` — Construcción de OBT
4. `04_validaciones_y_exploracion.ipynb` — Validaciones de calidad
5. `05_data_analysis.ipynb` — 20 preguntas de negocio

### 5. Ver Spark UI
Abrir: **http://localhost:4040** (disponible mientras hay un Job activo)

### 6. Detener
```bash
docker-compose down
```

### Tip: probar con un solo mes primero
Editar `.env` temporalmente:
```
YEAR_START=2024
YEAR_END=2024
MONTH_START=1
MONTH_END=1
```

## Troubleshooting

| Problema | Solución |
|----------|----------|
| `ClassNotFoundException: snowflake` | Verificar que el Dockerfile descarga los JARs correctamente |
| Error de conexión Snowflake | Verificar `SF_ACCOUNT` (formato: `ORGID-ACCOUNTID`) |
| Parquet no disponible (HTTP 403/404) | Normal para meses futuros; se registra como `skipped` en `INGESTION_LOG` |
| Jupyter no abre | Verificar `docker-compose logs spark-notebook` |
| OutOfMemory en Spark | Reducir `BATCH_SIZE` o procesar menos meses a la vez |

## Estructura del proyecto

```
Proyecto-3/
├── .env                                    # Credenciales reales (gitignored)
├── .env.example                            # Template sin creds (committed)
├── .gitignore
├── docker-compose.yaml
├── Dockerfile
├── requirements.txt
├── setup_jars.sh
├── README.md
├── data/                                   # Parquets temporales (gitignored)
├── evidencias/                             # Capturas de pantalla
└── notebooks/
    ├── 01_ingest_raw.ipynb
    ├── 02_enriquecimiento_y_unificacion.ipynb
    ├── 03_construccion_obt.ipynb
    ├── 04_validaciones_y_exploracion.ipynb
    └── 05_data_analysis.ipynb
```

## Checklist de aceptación

- [ ] Docker Compose levanta Spark y Jupyter Notebook
- [ ] Todas las credenciales/parámetros provienen de variables de ambiente (.env)
- [ ] Cobertura 2015–2025 (Yellow/Green) cargada en RAW con matriz y conteos por lote
- [ ] `ANALYTICS.OBT_TRIPS` creada con columnas mínimas, derivadas y metadatos
- [ ] Idempotencia verificada reingestando al menos un mes
- [ ] Validaciones básicas documentadas (nulos, rangos, coherencia)
- [ ] 20 preguntas respondidas usando la OBT
- [ ] README claro: pasos, variables, esquema, decisiones, troubleshooting
