#!/bin/sh
# Serve the empty metrics fixture with a Prometheus-compatible content type.
set -eu

readonly BODY_FILE=/www/metrics

while IFS= read -r request_line; do
    [ "${request_line}" = "$(printf '\r')" ] && break
done

readonly CONTENT_LENGTH="$(wc -c < "${BODY_FILE}" | tr -d ' ')"

printf 'HTTP/1.1 200 OK\r\n'
printf 'Content-Type: text/plain; version=0.0.4\r\n'
printf 'Content-Length: %s\r\n' "${CONTENT_LENGTH}"
printf 'Connection: close\r\n'
printf '\r\n'
cat "${BODY_FILE}"
