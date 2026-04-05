FROM jupyter/pyspark-notebook:spark-3.5.0

USER root

# Instalar dependencias básicas
RUN apt-get update && apt-get install -y curl wget && apt-get clean

# Snowflake JDBC driver (versión actualizada)
RUN curl -L -o /usr/local/spark/jars/snowflake-jdbc.jar \
    https://repo1.maven.org/maven2/net/snowflake/snowflake-jdbc/3.16.1/snowflake-jdbc-3.16.1.jar

# Spark Snowflake connector (versión actualizada)
RUN curl -L -o /usr/local/spark/jars/spark-snowflake.jar \
    https://repo1.maven.org/maven2/net/snowflake/spark-snowflake_2.12/2.16.0-spark_3.4/spark-snowflake_2.12-2.16.0-spark_3.4.jar

USER jovyan

COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir --default-timeout=100 -r /tmp/requirements.txt