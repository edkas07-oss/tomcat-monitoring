# ==============================================================================
# Windows Container Dockerfile for Mailpit
# Architecture Reference: TM-ADR-0026 & TN-019
# ==============================================================================
ARG BASE_IMAGE=mcr.microsoft.com/windows/nanoserver:ltsc2022
FROM ${BASE_IMAGE}

LABEL maintainer="Eddy Wiyatno" \
      description="Windows Container for Mailpit Testing SMTP Server & Web UI"

# Copy networking helper DLL required by Go os/user.Current() on NanoServer
COPY netapi32.dll C:/Windows/System32/

WORKDIR C:/mailpit

COPY mailpit.exe C:/mailpit/mailpit.exe

EXPOSE 8025 1025

VOLUME ["C:/data"]

ENTRYPOINT ["C:/mailpit/mailpit.exe", "--listen=0.0.0.0:8025", "--smtp=0.0.0.0:1025", "--db-file=C:/data/mailpit.db"]
