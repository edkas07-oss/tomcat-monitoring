# ==============================================================================
# Windows Container Dockerfile for Prometheus
# Architecture Reference: TM-ADR-0026 & TN-019
# ==============================================================================
ARG BASE_IMAGE=mcr.microsoft.com/windows/nanoserver:ltsc2022
FROM ${BASE_IMAGE}

LABEL maintainer="Eddy Wiyatno" \
      description="Windows Container for Prometheus Monitoring TSDB"

# Copy networking helper DLL required by Go os/user.Current() on NanoServer
COPY netapi32.dll C:/Windows/System32/

WORKDIR C:/prometheus

COPY prometheus.exe C:/prometheus/prometheus.exe
COPY promtool.exe C:/prometheus/promtool.exe

EXPOSE 9090

VOLUME ["C:/etc/prometheus", "C:/prometheus/data"]

ENTRYPOINT ["C:/prometheus/prometheus.exe", "--config.file=C:/etc/prometheus/prometheus.yml", "--storage.tsdb.path=C:/prometheus/data", "--web.listen-address=0.0.0.0:9090", "--web.enable-lifecycle"]
