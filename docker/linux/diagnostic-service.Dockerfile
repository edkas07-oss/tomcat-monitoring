# ==============================================================================
# Linux Container Dockerfile for Tomcat Diagnostic Service
# Architecture Reference: TM-ADR-0026 & TN-019
# ==============================================================================
ARG BASE_IMAGE=docker.io/library/node:20-alpine
FROM ${BASE_IMAGE}

LABEL maintainer="Eddy Wiyatno" \
      description="Linux Container for Tomcat Diagnostic Service"
