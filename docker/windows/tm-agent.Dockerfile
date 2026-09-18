# ==============================================================================
# Windows Container Dockerfile for Tomcat Monitoring Event Collector Agent (tm-agent)
# Architecture Reference: TM-ADR-0027 & TN-019
# ==============================================================================
ARG BASE_IMAGE=mcr.microsoft.com/windows/nanoserver:ltsc2022
FROM ${BASE_IMAGE}

LABEL maintainer="Eddy Wiyatno" \
      description="Windows Container for Tomcat Diagnostic Event Collector Agent"

# Copy networking helper DLL required by Go os/user.Current() on NanoServer
COPY netapi32.dll C:/Windows/System32/

WORKDIR C:/tm-home

COPY tm-agent.exe C:/tm-home/tm-agent.exe

VOLUME ["C:/tm-home/spool"]

ENTRYPOINT ["C:/tm-home/tm-agent.exe", "--spool-dir=C:/tm-home/spool"]
