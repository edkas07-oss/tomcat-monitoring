# ==============================================================================
# Linux Container Dockerfile for Alertmanager
# Architecture Reference: TM-ADR-0026 & TN-019
# ==============================================================================
ARG BASE_IMAGE=quay.io/prometheus/alertmanager:v0.34.0
FROM ${BASE_IMAGE}

LABEL maintainer="Eddy Wiyatno" \
      description="Linux Container for Alertmanager"
