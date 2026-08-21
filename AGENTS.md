# Repository Instructions

## Repository Purpose

Repository ini memiliki monitoring integration dan delivery automation untuk
Apache Tomcat Containerization with Embedded Monitoring Instrumentation.
Tanggung jawabnya mencakup configuration, validation, dashboard, alerting,
integration, CI/CD, Ansible, dan deployment orchestration yang menghubungkan
komponen tanpa mengambil alih source generic Tomcat atau JMX Exporter artifact.

## Source of Truth

- Repository ini belum memiliki committed implementation layout. Jangan
  mengasumsikan struktur, tool, command, atau deployment target sebelum rencana
  disetujui.
- Gunakan dokumentasi Tomcat Monitoring pada
  `devops-handbook/docs/projects/tomcat-monitoring/` untuk current-state
  architecture, scope, dan Engineering Journal.
- Gunakan ADR Tomcat Monitoring pada `devops-handbook/docs/adr/tomcat-monitoring/`
  sebagai source keputusan arsitektur signifikan.
- Perlakukan repository `tomcat` sebagai source generic runtime dan
  `tomcat-jmx-exporter` sebagai source derived-image contract.

## Repository Boundaries

- Repository memiliki Prometheus, Telegraf, dashboard, alerting, external
  integration, validation, CI/CD, Ansible, dan deployment automation yang
  disetujui untuk monitoring solution.
- Repository tidak memiliki generic Tomcat implementation atau lifecycle JMX
  Exporter binary.
- Jangan menyalin source dari `tomcat` atau `tomcat-jmx-exporter`; konsumsi
  artifact melalui contract yang disepakati.
- Pisahkan reusable non-secret configuration dari environment-specific secret,
  certificate, credential, inventory, dan runtime state.

## Working Rules

- Mulai dengan memeriksa Git status, approved architecture, ADR, Engineering
  Journal, dan repository contracts terkait.
- Karena implementation layout belum tersedia, mulai hanya dari approved
  repository structure dan implementation plan; jangan membuat scaffold
  berdasarkan asumsi.
- Kerjakan hanya approved scope dan pertahankan unrelated user changes.
- Gunakan `rg` atau `rg --files` untuk pencarian dan `apply_patch` untuk edit
  manual.
- Setiap komponen harus memiliki validation interface yang dapat dijalankan
  sebelum automation CI/CD bergantung padanya.

## Approval Requirements

- Read-only inspection yang relevan dapat dilakukan tanpa approval tambahan.
- Struktur repository, dependency, source, dan configuration change memerlukan
  approved implementation plan dan explicit scope.
- Download, image build, integration test, dan temporary runtime memerlukan
  approved implementation atau verification scope.
- Persistent container, deployment target, network, storage, certificate
  source, inventory, rollback, dan environment change memerlukan target serta
  approval eksplisit.
- Cleanup atau penghapusan container, image, volume, artifact, configuration,
  dan data memerlukan exact target dan destructive-action approval.

## Verification

- Tentukan validator dan expected result untuk setiap component configuration
  sebelum membuat CI/CD stage yang menggunakannya.
- Bedakan source validation, local component test, integration test, deployment
  verification, dan end-to-end monitoring verification.
- Local JMX Exporter smoke test tidak membuktikan Prometheus scrape, Telegraf
  health check, alert flow, dashboard, atau external integration.
- Catat environment, artifact identity, method, expected result, actual result,
  dan evidence untuk setiap klaim teknis.
- Jangan menyatakan end-to-end berhasil sampai seluruh approved topology dan
  firing/resolved flow yang relevan benar-benar diuji.

## Git and External State

- Jangan commit, push, membuat tag atau release, memublikasikan image, atau
  deploy tanpa authorization terpisah.
- Izin mengedit tidak mengizinkan build, test, runtime change, cleanup, commit,
  atau push secara otomatis.
- Jangan reset, checkout, atau menimpa perubahan pengguna.
- Perlakukan registry, CI server, Ansible target, certificate store, monitoring
  runtime, TrueSight, dan notification channel sebagai external state dengan
  approval terpisah.

## Secrets and Sensitive Data

- Jangan menyimpan password, token, private key, production certificate,
  credential, webhook secret, atau sensitive inventory value di Git, image,
  command output, log, maupun Engineering Journal.
- Gunakan secret injection yang disetujui dan simpan hanya template atau
  placeholder pada repository.
- Hentikan pekerjaan jika target secret source belum ditetapkan atau sensitive
  material berisiko masuk artifact dan evidence.

## Documentation Handoff

- Catat kebutuhan, planning, authorization, implementation, deviation, dan
  verification evidence pada Engineering Journal Tomcat Monitoring.
- Buat atau tautkan ADR untuk keputusan arsitektur signifikan sebelum
  implementasinya dianggap accepted.
- Konsolidasikan topology, component contract, operational state, dan status
  yang telah berlaku ke project pages di DevOps Engineering Handbook.
- Promosikan prosedur dan troubleshooting reusable ke root How-to atau
  Troubleshooting; repository source tetap menjadi detail implementation.

## Stop Conditions

Berhenti dan minta direction jika approved structure atau repository boundary
belum jelas, required ADR atau implementation decision belum accepted, scope
perlu diperluas, deployment target atau rollback belum spesifik, destructive
target ambigu, user changes beririsan, secret source belum aman, dependency,
network, privilege, atau external access belum disetujui, atau evidence tidak
cukup untuk status yang diminta.
