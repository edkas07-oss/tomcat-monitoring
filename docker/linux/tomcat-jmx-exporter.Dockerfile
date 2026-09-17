# ==============================================================================
# Linux Container Dockerfile for Tomcat JMX Exporter
# Architecture Reference: TM-ADR-0026 & TN-019
# ==============================================================================
ARG BASE_IMAGE=docker.io/library/tomcat:9.0
FROM ${BASE_IMAGE}

ARG JMX_EXPORTER_VERSION=1.6.0
ARG JMX_EXPORTER_SHA256=a95983fd96e865d2bcdf911cc500e7c82808c27ab9fd226bf96732b6c3d8c46e

LABEL maintainer="Eddy Wiyatno" \
      description="Linux Container for Tomcat with JMX Exporter"

ENV JMX_EXPORTER_PORT=9404 \
    JMX_EXPORTER_CONFIG=/etc/tomcat-jmx-exporter/config.yml \
    JMX_EXPORTER_KEYSTORE=/run/secrets/tomcat-jmx-exporter/keystore.p12 \
    JMX_EXPORTER_KEYSTORE_PASSWORD_FILE=/run/secrets/tomcat-jmx-exporter/keystore-password

ADD https://github.com/prometheus/jmx_exporter/releases/download/${JMX_EXPORTER_VERSION}/jmx_prometheus_javaagent-${JMX_EXPORTER_VERSION}.jar /opt/jmx-exporter/jmx_prometheus_javaagent.jar
RUN chmod 0444 /opt/jmx-exporter/jmx_prometheus_javaagent.jar

COPY entrypoint.sh /jmx-exporter-entrypoint.sh
RUN chmod 0555 /jmx-exporter-entrypoint.sh

EXPOSE 8080 9404

ENTRYPOINT ["/jmx-exporter-entrypoint.sh"]
CMD ["catalina.sh", "run"]
