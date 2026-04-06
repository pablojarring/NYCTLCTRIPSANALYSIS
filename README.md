# Data Mining — PSet03: NYC TLC Trips con Spark y Snowflake

## Autores
Carlos Flores
Omar Gordillo
Pablo Jarrin
Alex Luna
Andrés Vega


## Tabla de contenidos
1. [Requisitos previos](#requisitos-previos)
2. [Variables de ambiente](#variables-de-ambiente)
3. [Levantar la infraestructura](#levantar-la-infraestructura)
4. [Ejecución de notebooks](#ejecución-de-notebooks)
5. [Diseño de esquemas en Snowflake](#diseño-de-esquemas-en-snowflake)
6. [One Big Table (OBT)](#one-big-table-obt)
7. [Calidad y auditoría](#calidad-y-auditoría)
8. [Matriz de cobertura 2015–2025](#matriz-de-cobertura-20152025)
9. [Manejo de problemas](#manejo-de-problemas)


## Requisitos previos

- Docker y Docker Compose instalados
- Cuenta activa en Snowflake
- Acceso a internet para descargar los archivos Parquet de NYC TLC


## Variables de ambiente

Copia `.env.example` a `.env` y completa con las credenciales reales.

```bash
cp .env.example .env
```

### `.env.example`

```dotenv
# ==============================
# Snowflake Configuration
# ==============================
SF_ACCOUNT=your_account
SF_USER=your_user
SF_PASSWORD=your_password
SF_WAREHOUSE=your_warehouse
SF_DATABASE=your_database
SF_SCHEMA_RAW=your_raw_schema
SF_SCHEMA_ANALYTICS=your_analytics_schema
SF_ROLE=your_role

# ==============================
# Data Sources
# ==============================
PARQUET_BASE_URL=https://d37ci6vzurychx.cloudfront.net/trip-data
TAXI_ZONE_URL=https://d37ci6vzurychx.cloudfront.net/misc/taxi_zone_lookup.csv

# ==============================
# Date Range Configuration
# ==============================
YEAR_START=2015
YEAR_END=2025
MONTH_START=1
MONTH_END=12

# ==============================
# Pipeline Settings
# ==============================
SERVICES=yellow,green
RUN_ID=backfill-YYYY-MM
BATCH_SIZE=500000
ENABLE_VALIDATION=true
```

## Levantar la infraestructura

```bash
# Clonar el repositorio
git clone <url-del-repo>
cd <nombre-del-repo>
# Crear el archivo .env con tus credenciales
cp .env.example .env
# Edita .env con los valores reales
# Levantar los servicios
docker compose up -d
# Verificar que los contenedores estén corriendo
docker compose ps
```

Una vez levantado, se accede a:
- **Jupyter:** [http://localhost:8888](http://localhost:8888)
- **Spark UI:** [http://localhost:4040](http://localhost:4040)


Para detener los servicios hay que hacer un:
```bash
docker compose down
```


## Ejecución de notebooks

Se ecjecutan los notebooks en orden desde Jupyter, una vez levantado el contenedor. Todos leen sus parámetros desde variables de ambiente. El orden es el siguiente:

1. 01_ingesta_parquet_raw.ipynb
Descarga y carga los archivos Parquet (2015–2025) de servicios Yellow y Green hacia el esquema raw en Snowflake. Procesa los datos mes a mes y registra conteos por lote junto con metadatos de auditoría. 

2. 02_enriquecimiento_y_unificacion.ipynb
Realiza el enriquecimiento de datos uniendo con el Taxi Zone Lookup.
Normaliza catálogos como payment_type, rate_code y vendor, y unifica los datasets Yellow y Green en una vista intermedia.

3. 03_construccion_obt.ipynb
Construye la tabla analytics.obt_trips, incorporando columnas derivadas y metadatos de lineage.
Incluye pruebas de idempotencia mediante la reingesta de un mes de prueba.

4. 04_validaciones_y_exploracion.ipynb
Ejecuta validaciones de calidad: detección de nulos, verificación de rangos, coherencia de fechas y conteos por mes/servicio.
Genera un reporte de calidad de datos.

5. 05_data_analysis.ipynb
Responde las 20 preguntas de negocio utilizando la tabla analytics.obt_trips mediante consultas en Spark SQL.


## Diseño de esquemas en Snowflake

### Esquema raw

Las tablas están particionadas lógicamente por tipo de servicio (yellow y green). Cada registro incluye los siguientes metadatos de ingesta:
	•	run_id: Identificador único de la corrida del pipeline.
	•	service_type: Tipo de servicio (yellow o green).
	•	source_year: Año del archivo Parquet de origen.
	•	source_month: Mes del archivo Parquet de origen.
	•	source_path: URL o ruta del archivo Parquet utilizado.
	•	ingested_at_utc: Timestamp de ingesta en formato UTC.

Idempotencia: Antes de insertar cada mes, se elimina el lote anterior con el mismo (service_type, source_year, source_month). Esto garantiza que reingestar un mes no duplique filas.


## One Big Table (OBT)

### OBT

La OBT desnormaliza todas las dimensiones (zonas, catálogos, derivadas) en una sola tabla para:

- Eliminar JOINs en tiempo de consulta, esto hace que haya menor latencia y menor riesgo de errores de cardinalidad.
- Facilitar la generación del prototipo, hacerlo más rápido, por analistas/BI.
- Servir como una especie de fuente de verdad para las 20 preguntas de negocio.

Indempotencia: Antes de insertar cualquier mes, se verifica y elimina el lote existente


### Limitaciones y como se manejaron

El enfoque presenta algunas limitaciones que han sido mitigadas de forma práctica. Por un lado, el mayor almacenamiento debido a la duplicación de datos se controla incluyendo únicamente las columnas realmente útiles. Además, los cambios en los catálogos, que podrían requerir la reconstrucción de la OBT, se manejan mediante notebooks reproducibles que permiten hacer rebuild por partición (por mes). El crecimiento en volumen se aborda mediante un particionado lógico por year y month, junto con tareas de mantenimiento periódico en Snowflake para asegurar un rendimiento adecuado.


## Calidad y auditoría

Se implementaron múltiples reglas de calidad para asegurar la consistencia de los datos durante la ingesta. Los registros con valores nulos en pickup_datetime o dropoff_datetime son descartados y registrados en la tabla de auditoría, mientras que aquellos donde dropoff_datetime es menor que pickup_datetime también se eliminan. De igual forma, se descartan registros con trip_distance negativa o con valores negativos en fare_amount o total_amount. En el caso de trip_duration_min, si el valor es menor a 0 o mayor a 1440 minutos (24 horas), el registro se conserva pero se marca como outlier. Además, los registros con pu_location_id o do_location_id nulos son descartados.

Para el control y trazabilidad del proceso, se mantiene una tabla de auditoría llamada raw.ingestion_audit, que registra información clave de cada corrida del pipeline. Esta incluye el identificador de la corrida (run_id), el tipo de servicio (service_type), el año y mes procesados (source_year, source_month), la cantidad de filas leídas desde los archivos Parquet (rows_read), las filas insertadas en la capa raw (rows_inserted), las filas descartadas por reglas de calidad (rows_discarded), la duración del proceso de carga en segundos (load_duration_sec) y el timestamp de la ingesta en UTC (ingested_at_utc).



## Matriz de cobertura 2015–2025

✅ = Cargado correctamente, ⚠️ = Parcial o con advertencias, ❌ = Falta o fallido

| Año  | Y-Ene | Y-Feb | Y-Mar | Y-Abr | Y-May | Y-Jun | Y-Jul | Y-Ago | Y-Sep | Y-Oct | Y-Nov | Y-Dic | G-Ene | G-Feb | G-Mar | G-Abr | G-May | G-Jun | G-Jul | G-Ago | G-Sep | G-Oct | G-Nov | G-Dic |
|------|-------|-------|-------|-------|-------|-------|-------|-------|-------|-------|-------|-------|-------|-------|-------|-------|-------|-------|-------|-------|-------|-------|-------|-------|
| 2015 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 2016 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 2017 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 2018 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 2019 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 2020 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 2021 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 2022 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 2023 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 2024 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 2025 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |



## Manejo de problemas

Se decidió dejar de utilizar PySpark y migrar a Snowpark, aprovechando su capacidad de ejecutar operaciones mediante query pushdown directamente en Snowflake. Sin embargo, este cambio generó algunas inconsistencias en el proceso de ingesta, por lo que fue necesario realizar ciertos ajustes manuales para asegurar la calidad y completitud de los datos.

### Reingestar meses específico

Tuvimos problemas al ingestar ciertos meses en especifico, por lo que tuvimos que reingestar manualmente cambiando nuestro enviroment para definir los parametros al rango especifico que queriamos reingestar, no hubo un manejo automatico de reingesta al detectar errores.


## Checklist de aceptación

- [x] Docker Compose levanta Spark y Jupyter Notebook. 
- [x] Todas las credenciales/parámetros provienen de variables de ambiente (.env). 
- [x] Cobertura 2015–2025 (Yellow/Green) cargada en raw con matriz y conteos por lote. 
- [x] analytics.obt_trips creada con columnas mínimas, derivadas y metadatos. 
- [x] Idempotencia verificada reingestando al menos un mes. 
- [x] Validaciones básicas documentadas (nulos, rangos, coherencia). 
- [x] 20 preguntas respondidas (texto) usando la OBT. 
- [x] README claro: pasos, variables, esquema, decisiones, troubleshooting. 

