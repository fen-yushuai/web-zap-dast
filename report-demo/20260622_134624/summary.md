# DAST 扫描报告

- **日期**: 2026-06-22 13:47:56
- **目标**: http://host.docker.internal:8080
- **目录**: reports/20260622_134624

## Spider 爬取结果

传统 Spider:      8 URLs
ZAP 会话全部 URL: 11（含认证、重定向、资源）

## ZAP 扫描发现

Informational: 3
Low: 5
Medium: 3

完整报告: `zap-report.html` / `zap-report.json`

## 报告文件

| 文件 | 说明 |
|------|------|
| `zap-spider-urls.txt` | Spider 发现的 URL 列表 |
| `zap-sitemap.txt` | 站点树结构 |
| `zap-report.html` | ZAP 报告（HTML） |
| `zap-report.json` | ZAP 发现（JSON） |
| `zap-report.xml` | ZAP 发现（XML） |
