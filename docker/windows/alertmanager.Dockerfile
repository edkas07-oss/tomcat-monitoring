# ==============================================================================
# Windows Container Dockerfile for Alertmanager
# Architecture Reference: TM-ADR-0026 & TN-019
# ==============================================================================
ARG BASE_IMAGE=mcr.microsoft.com/windows/nanoserver:ltsc2022
FROM ${BASE_IMAGE}

LABEL maintainer="Eddy Wiyatno" \
      description="Windows Container for Alertmanager Notification & Routing Hub"

# Copy networking helper DLL required by Go os/user.Current() on NanoServer
COPY netapi32.dll C:/Windows/System32/

WORKDIR C:/alertmanager

COPY alertmanager.exe C:/alertmanager/alertmanager.exe
COPY amtool.exe C:/alertmanager/amtool.exe

EXPOSE 9093 9094

VOLUME ["C:/etc/alertmanager", "C:/alertmanager/data"]

ENTRYPOINT ["C:/alertmanager/alertmanager.exe", "--config.file=C:/etc/alertmanager/alertmanager.yml", "--storage.path=C:/alertmanager/data", "--web.listen-address=0.0.0.0:9093"]
