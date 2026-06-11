# 网站安全测试

### 相关概念区分

- **脆弱性测试（Vulnerability Testing/Scanning）**：自动化工具扫描已知漏洞签名，覆盖面广但深度有限
- **渗透测试（Penetration Testing）**：人工+工具结合，模拟真实攻击链，深度验证漏洞可利用性
- **代码安全审计（Code Security Audit）**：从源码层面分析安全隐患，属于白盒测试范畴

---

## 测试依据

以 [OWASP WSTG](https://owasp.org/) 为核心参考。

| 阶段 | 测试活动 | 技术 |
|------|----------|------|
| **需求/设计** | 安全需求审查、威胁建模 | — |
| **开发** | 静态代码分析、依赖检查 | SAST、SCA |
| **部署** | 动态扫描、渗透测试 | DAST |
| **运维** | 持续监控、定期扫描 | DAST |

WSTG 将测试分为 12 个类别：信息收集、配置与部署管理、身份管理、认证、授权、会话管理、输入验证、错误处理、弱加密、业务逻辑、客户端、API 测试。

### OWASP Top 10（2025）

[OWASP Top 10](https://owasp.org/Top10/) 是 Web 应用最关键的安全风险清单：

| 编号 | 风险 | 说明 |
|------|------|------|
| A01 | Broken Access Control | 越权访问、IDOR、权限提升 |
| A02 | Cryptographic Failures | 弱加密、明文传输、密钥管理不当 |
| A03 | Injection | SQL 注入、XSS、命令注入、LDAP 注入 |
| A04 | Insecure Design | 缺乏威胁建模、不安全的业务逻辑设计 |
| A05 | Security Misconfiguration | 默认配置、不必要的功能启用、缺少安全头 |
| A06 | Vulnerable and Outdated Components | 使用含已知漏洞的第三方组件 |
| A07 | Identification and Authentication Failures | 弱认证、会话管理缺陷 |
| A08 | Software and Data Integrity Failures | 不安全的反序列化、CI/CD 管道缺陷 |
| A09 | Security Logging and Monitoring Failures | 日志不足、告警缺失、响应迟缓 |
| A10 | Server-Side Request Forgery (SSRF) | 服务端请求伪造 |

---

## 测试类型与工具

**SAST（Static Application Security Testing，静态应用安全测试）**
- 静态代码扫描（如有源码）
  - [Semgrep](https://semgrep.dev/) — 开源，多语言（30+），规则灵活，扫描快（秒级），适合 PR 快速反馈
  - [CodeQL](https://codeql.github.com/) — GitHub 出品，语义分析深（污点追踪、数据流分析），适合定时深度扫描
  - 密钥泄露检测：[Gitleaks](https://github.com/gitleaks/gitleaks) — 检测代码中硬编码的 API Key、密码、Token

**SCA（Software Composition Analysis，软件成分分析）**
- 依赖漏洞扫描 — 检测第三方依赖中的已知 CVE
  - [Trivy](https://github.com/aquasecurity/trivy) — 开源，覆盖依赖 + 容器镜像 + IaC + Secret 扫描
  - [OWASP Dependency-Check](https://owasp.org/www-project-dependency-check/) — OWASP 出品，基于 NVD 数据库
  - 各语言内置：`npm audit` / `pip audit` / `cargo audit`
- 依赖更新与自动修复
  - [Dependabot](https://github.com/dependabot) — GitHub 内置，零配置自动检测依赖漏洞并发 PR 升级
  - [Renovate](https://github.com/renovatebot/renovate) — 比 Dependabot 更灵活的依赖更新与漏洞修复工具
- License 合规检查 — 检测依赖的开源许可证是否与项目兼容
  - [ScanCode](https://github.com/nexB/scancode-toolkit) — 开源，支持 2000+ 种 License 识别
  - 各语言内置：`npx license-checker` / `pip-licenses`

**DAST（Dynamic Application Security Testing，动态应用安全测试）**
- 全站爬取，发现所有可访问的页面和参数
- 自动发送 Payload，检测 OWASP Top 10 漏洞
- 工具：
  - [Nuclei](https://github.com/projectdiscovery/nuclei) — 基于模板的漏洞扫描，社区模板库丰富
  - [OWASP ZAP](https://www.zaproxy.org/) — 全功能开源 DAST 扫描器
  - [SQLMap](https://sqlmap.org/) — SQL 注入专项检测与利用

**人工渗透测试**
- 信息收集 — 端口扫描、指纹识别
- 漏洞验证 — 对自动化扫描结果进行人工确认
- 深度测试 — 业务逻辑漏洞、权限绕过、组合攻击链
- 工具：
  - [Nmap](https://nmap.org/) — 端口扫描与服务识别
  - [Burp Suite](https://portswigger.net/burp) — Web 应用测试代理，拦截/修改请求
  - [ffuf](https://github.com/ffuf/ffuf) — 目录与参数爆破

---

## 测试执行建议

| 测试类型 | 建议 | 说明 |
|----------|------|------|
| **SCA**（软件成分分析） | 推荐 | 投入低、回报高，工具免费且易集成 |
| **SAST**（静态应用安全测试） | 推荐 | 工具成熟，有源码即可执行 |
| **DAST**（动态应用安全测试） | 推荐 | 无需源码，覆盖面广，适合上线前扫描 |
| **密钥泄露检测** | 推荐 | 一行命令即可执行，防止凭证泄露 |
| **人工渗透测试** | 不推荐 | 需安全专家，成本高 |

---

## 测试前准备与输出

**测试前**
- 获取目标系统的书面授权
- 确定测试范围（域名、IP、端口、功能模块）
- 明确测试窗口与紧急联系人

**测试后**
- 编写测试报告：漏洞详情、复现步骤、风险等级（CVSS）、修复建议
- 按优先级排序，协助开发团队修复
- 回归验证，确认漏洞已修复
