# ==============================================================================
# Linux Container Dockerfile for Tomcat Diagnostic Service
# Architecture Reference: TM-ADR-0026 & TN-019
# ==============================================================================
ARG BASE_IMAGE=docker.io/library/node:20-alpine
FROM ${BASE_IMAGE}

LABEL maintainer="Eddy Wiyatno" \
      description="Linux Container for Tomcat Diagnostic Service"

WORKDIR /app
COPY package*.json /app/
RUN npm ci --omit=dev --ignore-scripts --no-audit --no-fund 2>/dev/null || npm install --omit=dev --no-audit --no-fund 2>/dev/null || true

COPY src /app/src
COPY config /app/config
COPY migrations /app/migrations

USER node
EXPOSE 8443

CMD ["node", "src/main.js", "--config", "/run/tomcat-diagnostic/application.json"]
