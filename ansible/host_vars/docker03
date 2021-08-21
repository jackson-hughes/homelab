---
consul_services:
  - name: "prometheus"
    tags:
      - "prometheus"
      - "monitoring"
    port: "9090"
    checks:
      - name: "Metrics endpoint check"
        http: "http://localhost:9090/metrics"
        interval: "15s"
        timeout: "3s"
  - name: "grafana"
    tags:
      - "grafana"
      - "monitoring"
    port: "3000"
    checks:
      - name: "Metrics endpoint check"
        http: "http://localhost:3000/metrics"
        interval: "15s"
        timeout: "3s"
  - name: "plex media server"
    tags:
      - "plex"
      - "media"
    port: "32400"
    checks:
      - name: 
        http: "http://localhost:32400/web/index.html"
        interval: "15s"
        timeout: "3s"
