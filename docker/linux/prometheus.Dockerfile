# ==============================================================================
# Linux Container Dockerfile for Prometheus
# Architecture Reference: TM-ADR-0026 & TN-019
# ==============================================================================
ARG BASE_IMAGE=docker.io/prom/prometheus:v3.13.2
FROM ${BASE_IMAGE}

LABEL maintainer="Eddy Wiyatno" \
      description="Linux Container for Prometheus Monitoring TSDB"
