# ==============================================================================
# Linux Container Dockerfile for Postfix Enterprise SMTP Relay Bridge
# Architecture Reference: TM-ADR-0026 & TN-019
# ==============================================================================
ARG BASE_IMAGE=docker.io/library/alpine:latest
FROM ${BASE_IMAGE}

LABEL maintainer="Eddy Wiyatno" \
      description="Linux Container for Postfix Enterprise SMTP Relay Bridge"
