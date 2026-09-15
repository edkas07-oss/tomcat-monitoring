# JMX Exporter Configuration Contract & MBean Mapping

This directory maintains the Prometheus JMX Exporter metric rules configuration for Apache Tomcat.
The runtime path adheres to the container contract: `/etc/tomcat-jmx-exporter/config.yml`.

TLS keystores and passwords are not stored in Git; they are mounted as read-only runtime secrets. The configuration references `${JMX_EXPORTER_KEYSTORE_PASSWORD}` as an environment variable without hardcoding passwords.

---

## 📊 Core Metric MBean Mapping Rules

The baseline maps key JVM and Tomcat MBeans to standard Prometheus metrics:
* **JVM Heap & Non-Heap Memory:** MBean `java.lang:type=Memory` mapped to `jvm_memory_bytes_used`, `jvm_memory_bytes_max`.
* **Garbage Collection STW Pauses:** MBean `java.lang:type=GarbageCollector,name=*` mapped to `jvm_gc_pause_seconds_sum` and `jvm_gc_pause_seconds_count`.
* **Old Generation Memory Pools:** MBean `java.lang:type=MemoryPool,name=*Old*` mapped to `jvm_memory_pool_used_bytes`.
* **Tomcat Thread Pool & Connections:** MBean `Catalina:type=ThreadPool,name=*` mapped to `tomcat_threads_busy_threads` and `tomcat_threads_current_threads`.
* **Tomcat Server Runtime:** MBean `Catalina:type=Server` mapped to `tomcat_server`.

---

## 🧪 Static Validation

Execute static syntax and configuration validation:

```bash
./scripts/validate.sh
```
