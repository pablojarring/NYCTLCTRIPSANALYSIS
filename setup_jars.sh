#!/bin/bash
mkdir -p jars notebooks data
# Snowflake Spark connector + JDBC driver
wget -P jars/ https://repo1.maven.org/maven2/net/snowflake/spark-snowflake_2.12/2.16.0-spark_3.4/spark-snowflake_2.12-2.16.0-spark_3.4.jar
wget -P jars/ https://repo1.maven.org/maven2/net/snowflake/snowflake-jdbc/3.16.1/snowflake-jdbc-3.16.1.jar
echo "JARs downloaded. Run: docker-compose up"
