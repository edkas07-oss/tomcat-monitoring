# ==============================================================================
# Linux Container Dockerfile for Mailpit
# Architecture Reference: TM-ADR-0026 & TN-019
# ==============================================================================
ARG BASE_IMAGE=ghcr.io/axllent/mailpit:v1.31.0
FROM ${BASE_IMAGE}

LABEL maintainer="Eddy Wiyatno" \
      description="Linux Container for Mailpit"
