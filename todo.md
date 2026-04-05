# Tareas Pendientes (TODO) - Proyecto 03 Data Mining

A continuación se detallan las fallas y faltantes observados en el repositorio según los requerimientos del proyecto (DM-PSet-3.pdf). Estos puntos deben completarse para obtener la calificación total.

## 1. Evidencias Visuales (Carpeta `evidencias/`)
La carpeta `evidencias/` se encuentra completamente vacía. Se requiere agregar las siguientes capturas de pantalla:
- [ ] Captura de Docker Compose corriendo (`docker-compose up`).
- [ ] Captura del servicio Jupyter Notebook ejecutándose y accesible en el puerto designado.
- [ ] Captura de la Spark UI (puerto 4040) con un Job activo.
- [ ] Captura de la conexión exitosa a Snowflake.
- [ ] Captura (snapshot) de la One Big Table (`ANALYTICS.OBT_TRIPS`) creada y con datos en Snowflake.
- [ ] Captura de los conteos por lote en la tabla de auditoría (`RAW.INGESTION_LOG`).

## 2. Ejecución de Ingesta y Cobertura (README.md)
El archivo README contiene secciones vacías que deben ser llenadas con resultados reales de la ejecución:
- [ ] **Matriz de cobertura 2015–2025:** Llenar la tabla indicando el estado de la ingesta para cada mes/año (✅ ok, ❌ falta, ⚠️ fallido) para Yellow y Green.
- [ ] **Resultados de Auditoría:** Proveer reportes de ejecución, conteos por lote o logs reales extraídos de la tabla `INGESTION_LOG`.

## 3. Calidad y Auditoría (Resultados empíricos)
Falta documentar los resultados de las validaciones aplicadas:
- [ ] Documentar cuántas filas fueron descartadas en el proceso de limpieza (por nulos esenciales, duraciones < 0, distancias < 0, etc.).
- [ ] Reportar el impacto de la creación de índices (si se implementaron) y los tiempos estimados de consultas típicas.
- [ ] Mostrar evidencia de la tabla de auditoría poblada con datos reales de la ingesta.

## 4. Respuestas a Preguntas de Negocio
El entregable exige que se respondan 20 preguntas de negocio utilizando la OBT.
- [ ] Incluir en el repositorio (puede ser en el README o en un archivo markdown dedicado, o claramente expuesto en el notebook `05_data_analysis.ipynb` en formato texto) las respuestas concretas a las 20 preguntas formuladas en el literal 10.5 del documento del proyecto.

## 5. Completar Checklist de Aceptación (README.md)
- [ ] Marcar con una "x" (`[x]`) todas las casillas del checklist de aceptación al final del `README.md` una vez que los puntos anteriores hayan sido completados.


## 6. Otros
- [ ] Leer las instrucciones
- [x] Decidir si el notebook 2 deberia limpiar de verdad los datos
- [x] Resolver problema de memoria
- [ ] Determinar si cambiar bloques de sql por spark
- [ ] Colocación de comandos para medición de tiempos (Comparacion Cluster con indices vs no Cluster)
- [ ] Agregar descarte de valores en proceso de limpieza
- [x] Asegurarse de ingesta completa