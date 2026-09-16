# ==============================================================================
# Linux Container Dockerfile for Tomcat Monitoring Event Collector Agent (tm-agent)
# Architecture Reference: TM-ADR-0027 & TN-019
# ==============================================================================
ARG BASE_IMAGE=docker.io/library/alpine:3.20
FROM ${BASE_IMAGE}

LABEL maintainer="Eddy Wiyatno" \
      description="Linux Container for Tomcat Diagnostic Event Collector Agent"

RUN apk add --no-cache ca-certificates tzdata

COPY tm-agent /usr/local/bin/tm-agent
RUN chmod 0755 /usr/local/bin/tm-agent

VOLUME ["/var/spool/tomcat-monitoring"]

ENTRYPOINT ["/usr/local/bin/tm-agent"]
