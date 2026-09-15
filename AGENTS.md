# Repository Instructions & Agent Guidelines

## Repository Purpose

This repository provides monitoring integration and delivery automation for **Apache Tomcat Containerization with Embedded Monitoring Instrumentation**.
Its responsibilities cover configuration, static validation, dashboards, alerting rules, integrations, CI/CD pipelines, Ansible automation, and multi-container deployment orchestration without taking ownership of generic Tomcat upstream source code or JMX Exporter binary lifecycles.

## Source of Truth & Architecture Governance

- Consult the Tomcat Monitoring architecture documentation and Engineering Journal for current-state architecture, scope, and technical notes.
- Refer to Architecture Decision Records (ADRs) as the definitive source for significant architectural decisions.
- Treat `tomcat` as the generic base runtime source and `tomcat-jmx-exporter` as the derived-image instrumentation contract.

## Repository Boundaries

- **In-Scope:** Declarative configurations for Prometheus, Alertmanager, Telegraf, Postfix Relay, Mailpit, Diagnostic Service, AI diagnostic rulepacks, validation scripts, CI/CD Jenkinsfile, Ansible roles, inventories, and deployment automation.
- **Out-of-Scope:** Generic Apache Tomcat core source code, custom Java application code, or building the JMX Exporter agent binary from source.
- Do not copy vendor code from upstream repositories; consume artifacts via established image and configuration contracts.
- Maintain a strict separation between reusable non-secret configurations and environment-specific secrets, TLS certificates, credentials, inventories, and runtime state.
- **Runtime Component Ownership Gate:** Before integrating new runtime containers, ensure explicit ownership, image lifecycle, and repository boundaries are defined. Components with their own build lifecycle (e.g. standalone Go daemons or Node.js microservices) reside in dedicated component repositories; `tomcat-monitoring` serves as the integration and delivery hub.

## Working Rules

- Inspect Git status, architecture contracts, ADRs, and technical notes before initiating changes.
- Implement only within the approved scope and preserve existing user configurations.
- Use `rg` or `rg --files` for search, and appropriate tool calls for file edits.
- Every component must maintain an automated validation interface that runs prior to CI/CD pipeline automation.

## Approval & Execution Guidelines

- Read-only inspection and code navigation can proceed freely.
- Structural repository changes, dependencies, and configuration refactoring require clear implementation planning.
- Persistent container creation, deployment targets, network bridges, storage volumes, certificate generation, inventory modification, and environment changes must be clearly verified.
- Cleanup or deletion of containers, images, volumes, configurations, or persistent data must target specific resources with zero risk of accidental data loss.

## Verification Standards

- Define validators and expected outcomes for each component configuration before integrating into CI/CD stages.
- Differentiate between static source validation, local component smoke tests, integration tests, deployment verification, and end-to-end monitoring verification.
- Local JMX Exporter tests alone do not prove Prometheus scraping, Telegraf health probing, alert routing, or diagnostic report dispatching.
- Always record target environment, artifact identity, test methodology, expected results, actual results, and verification evidence.
- Do not declare end-to-end success until the complete approved topology and both FIRING and RESOLVED alert lifecycles are fully tested.

## Git and External State

- Do not commit, push, create release tags, publish container images, or trigger remote deployment without explicit intent.
- Editing permissions do not automatically imply deployment to remote production environments.
- Treat container registries, CI servers, Ansible remote targets, certificate authorities, and external notification channels as external state managed through parameterized automation.

## Secrets and Sensitive Data Governance

- **Zero-Secret Policy in Git:** Never store passwords, bearer tokens, private keys, production certificates, credentials, webhook secrets, or sensitive production hostnames/IPs in Git, container images, command logs, or public documentation.
- Use runtime secret injection with strict file permissions (`0400` / `0444`) mounted to host-isolated locations (e.g. `~/.local/share/tomcat-monitoring/`).
- Stop execution immediately if a secret source is missing or if sensitive data is at risk of exposure in artifacts.

## Documentation Standards

- Record technical context, planning, implementation decisions, deviations, and verification evidence in structured technical notes.
- Document executed commands accurately with realistic, safe placeholders for sensitive parameters.
- Record both positive and negative test cases with explicit inputs and verified outputs.

## Stop Conditions

Stop and seek direction if:
- Repository boundaries or structural layout requirements are ambiguous.
- Required architecture decisions or target environments are unspecified.
- Destructive actions or rollback targets are unclear.
- Secret injection sources are undefined or insecure.
- Verification evidence is insufficient to validate the requested state.
