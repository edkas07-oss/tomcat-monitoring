# ==============================================================================
# Windows Container Dockerfile for Tomcat Diagnostic Service
# Architecture Reference: TM-ADR-0026 & TN-019
# ==============================================================================
ARG BASE_IMAGE=mcr.microsoft.com/windows/nanoserver:ltsc2022
FROM ${BASE_IMAGE}

LABEL maintainer="Eddy Wiyatno" \
      description="Windows Container for Tomcat Diagnostic Service"

# Copy networking helper DLL required on NanoServer
COPY netapi32.dll C:/Windows/System32/

# Copy Node.js runtime
WORKDIR C:/node
COPY node.exe C:/node/node.exe

# Copy Diagnostic Service codebase
WORKDIR C:/app
COPY package.json package-lock.json C:/app/
COPY node_modules C:/app/node_modules/
COPY src C:/app/src/
COPY config C:/app/config/
COPY migrations C:/app/migrations/

ENV NODE_ENV=production
EXPOSE 8443

ENTRYPOINT ["C:/node/node.exe", "C:/app/src/main.js", "--config", "C:/tm-home/config/diagnostic-service/application.json"]
