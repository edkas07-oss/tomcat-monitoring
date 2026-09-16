# ==============================================================================
# Linux Container Dockerfile for Tomcat JMX Exporter
# Architecture Reference: TM-ADR-0026 & TN-019
# ==============================================================================
ARG BASE_IMAGE=docker.io/library/tomcat:9.0
FROM ${BASE_IMAGE}

LABEL maintainer="Eddy Wiyatno" \
      description="Linux Container for Tomcat with JMX Exporter"
