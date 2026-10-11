# qsql

> **给数据库装一道「你说了算」的门。**
> 不开源发布 · 只提供下载 · 底层是原版 PostgreSQL，qsql 只做门禁层。

---

## 用户为什么要用它

数据库管理面板（phpMyAdmin / Adminer / Navicat / DBeaver）有个共同问题：
**挂在公网上就是一个密码换整个库** —— 密码泄露、弱口令、AI 帮你查库时手滑一条 `DELETE`，都没有第二道拦住。

qsql 不解数据库，只在它前面加一层**可验证的门**：

| 你遇到的状况 | qsql 怎么做 |
|---|---|
| 面板挂公网被扫、被爆破 | 只放行你指定的入口（暗门地址 + 门禁层），**服务器上不存私钥** |
| 同事/外包要临时看库 | 发个有时限的**MCP 令牌**，他看到的每一步都被审计 |
| **让 AI 直接查数据库** | MCP 接入 —— AI 和你走同一道门、同一份审计 |
| 有人疯狂导出、删表 | **一分钟内多次导出/删数据 → 冻结，只有私钥签名能解** |
| 备份包怕被解开 | `.qsql` 加密导出（AES-256-GCM + **ML-KEM-768 + ML-DSA-65**，抗量子） |
| 换机器就丢权限 | 首启生成 **Ed25519 私钥**，服务器只有公钥；换机用私钥重新绑定 |
| 要追责"谁动了数据" | 每次操作入审计：谁、何时、哪张表、几行、多少毫秒 |

### 谁该用 / 谁不该用

**适合**：自建 PostgreSQL 的管理员 · 用 AI 辅助运维的团队 · 需要加密备份与操作留证的个人/小团队 · 给别人开临时查库权限的场景。

**不适合**：只是想本机 SQLite 看一眼的 · 需要分布式多活的（那要用专门的分布式方案）· 完全不想管权限的。

---

## 特性

- **首启一次性初始化**：自动生成 Ed25519 私钥（只显示一次）→ 设登录密码（默认 64 位随机）→ 可选 TOTP → 可跳过的域名绑定
- **两种登录**：私钥签名扫码 / 接入密码（+ 动态码）
- **忘记密码**：用私钥重新生成，不依赖任何"找回"流程
- **高危动作锁定**：导出 / 删数据 / 改结构，一分钟内多次 → 冻结，须私钥签名解锁
- **敌我识别**：自家 IP、陌生 IP、未登录三档阈值；未登录尝试高危动作一次即锁
- **登录失败限速**：10 分钟内错 5 次 → 冻结 15 分钟
- **暗门地址**：`/psql/<16 位随机码>`，其它路径一律 404
- **AI 接入（MCP）**：给 AI 发令牌，工具 `qsql_query` / `qsql_tables` / `qsql_describe`；AI 的写操作同样触发锁定
- **加密导出**：`.qsql` 二进制包，抗量子签名，改一字节即验签失败

---

## 安装（官方下载器）

一行命令，自动下载并装好（需要 root）：

```bash
curl -fsSL https://psql.naling.net/dl/install.sh | sudo bash
```

> 下载走官方服务器：**每次下载会现场生成一个 20 位 PID（授权编号）并写入安装包**，
> 同时记录下载时间与来源。装好后在后台「设置 → 授权」能看到这套部署的 PID 与到期日。

装完会打印**你的专属后台地址**，形如：

```
管理后台地址：  http://<你的域名或IP>/psql/k3n8v2qp7m4xah9f
```

打开它 → 「你是首次用管理后台」→ 开始初始化。

### 拿到确切版本

```bash
V=0.2.0
curl -fsSLO https://psql.naling.net/dl/qsql-$V.zip     # 响应头 X-Qsql-Pid 就是你的 PID
unzip qsql-$V.zip -d /opt/ && sudo bash /opt/qsql/install.sh
```

### 授权说明

- 所有发布件都是 **评估版：一年内免费使用**
- 安装包自带 `license.json`（PID / 签发日 / 到期日），后台「设置」里随时可查
- 到期后：后台会显示授权到期页，列出**联系邮箱**和本机的 **PID 码**，把 PID 发来即可续期

### 放到 Nginx 后面（推荐）

```nginx
location = /qsql/auth {                 # 门禁：只认已登录会话
  internal;
  proxy_pass http://127.0.0.1:8077/auth;
  proxy_pass_request_body off;
  proxy_set_header Content-Length "";
  proxy_set_header X-Orig-Uri $request_uri;   # 高危动作靠它统计
}
location /adminer.php {                 # 数据库界面（可选后端）
  auth_request /qsql/auth;
  error_page 401 = @qsqldeny;
  include snippets/fastcgi-php.conf;
  fastcgi_pass unix:/run/php/php8.1-fpm.sock;
}
location @qsqldeny { return 302 /psql/denied; }
location /psql/ { proxy_pass http://127.0.0.1:8077; }   # qsql 自己的界面
location / { return 404; }                              # 扫 IP 什么都看不到
```

---

## AI 接入（MCP）

在面板「设置 → MCP 接入」生成令牌，然后给支持 MCP 的客户端加一段：

```json
{
  "mcpServers": {
    "qsql": {
      "command": "python3",
      "args": ["/opt/qsql/qsql-mcp.py"],
      "env": {
        "QSQL_PANEL": "https://<你的域名>/psql/<随机码>",
        "QSQL_MCP_TOKEN": "<面板生成的令牌>"
      }
    }
  }
}
```

**AI 不是特权通道**：它查库走审计，写操作计入高危动作，超频同样被冻结。

---

## 安全模型（一句话版）

- 服务器上**只有公钥**，私钥永远在你手里
- 密码 / 令牌**只存哈希**，明文不落盘
- 数据库端口**不对公网**（默认只放行白名单 IP）
- 高危动作**有频次上限**，超了要私钥才能解
- 导出包**加密 + 签名**，篡改必被拒

> 已知边界：APK 里内置的私钥是明文存放，拿到 APK 文件即可取出。
> 需要更强隔离时，请改用系统 Keystore 托管密钥的版本。

---

## 许可

**私有软件，不开源。** 允许下载与自用部署，不允许再分发、反编译或用于商业转售。
详细条款见 `LICENSE`。

---

## 常见问题

**Q：和 phpMyAdmin / Adminer 什么关系？**
qsql 是**门禁层**，数据库界面可以继续用它们（默认接 Adminer）。qsql 负责"谁能进、进了干什么、干过头怎么办"。

**Q：支持 MySQL 吗？**
门禁层与数据库无关；当前配套的集群视图与导出按 PostgreSQL 实现。

**Q：怎么看我的授权 / PID？**
后台「设置 → 授权」：版本、PID、签发日、到期日、剩余天数都在那儿。

**Q：到期了会怎样？**
后台进入到期提示页，显示联系邮箱与本机 PID 码，发邮件即可续期（数据不受影响）。

**Q：能从内网访问吗？**
可以，把内网 IP 加进白名单即可（改 `pg_hba.conf` + nftables 各一行）。
