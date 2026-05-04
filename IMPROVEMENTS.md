# http-pixiu 改进计划

> 按优先级排序，逐条解决。不要提交 git。

---

## P0 — 关键 Bug（阻塞基础功能）

### 1. GET/HEAD 请求被误报 400
**文件**: `core/protocol/request-parse.sls`
**问题**: 解析协程在读到 header 后的空行时，无条件尝试读取 `Content-Length` 并读 body。GET/HEAD/DELETE 等请求没有 body，导致直接报 400。
**修复方向**: 区分有无 body 的请求方法；GET/HEAD 不应强制要求 Content-Length，也不应阻塞读 body。

### 2. 任务超时完全失效
**文件**: `core/protocol/request-queue.sls`
**问题**: `expire-duration` 被忽略，`expire-timestamp` 直接用了创建时间，且时间戳计算混用毫秒和纳秒。
**修复方向**: `expire-timestamp = creation-time + expire-duration`，统一单位。

### 3. 路径遍历防护有漏洞
**文件**: `http-pixiu.sls` (safe-path?)
**问题**: 检查 `..` 时要求后面必须有字符，漏掉了末尾 `..`；没有做路径归一化。
**修复方向**: 归一化路径并确保解析后的路径仍在 `private-static-path` 下。

### 4. 异常被误标为 404
**文件**: `http-pixiu.sls` (init-lifecycle)
**问题**: `ufo-try/except` 捕获所有异常，数字异常当状态码返回，其余一律返回 404。
**修复方向**: 数字异常 → 该数字状态码；文件不存在 → 404；权限错误 → 403；其他 → 500。

### 5. `server-log-port` 未导出
**文件**: `core/server.sls`
**问题**: 定义了 `server-log-port` 但没有在 `(export ...)` 里列出。
**修复方向**: 补到 exports 里。

### 6. Date 头格式非法
**文件**: `core/util/date.sls`
**问题**: 没有补零（如 `9` 而不是 `09`），用了系统时区名而不是 `GMT`。
**修复方向**: 补零 + 固定 `GMT`。

### 7. socket accept 失败时忙等
**文件**: `http-pixiu.sls`
**问题**: accept 异常后直接进入下一轮循环，没有退避，可能烧 CPU。
**修复方向**: accept 失败时短暂休眠再重试。

---

## P1 — HTTP 协议特性

### 8. 支持 Keep-Alive / 连接复用
**文件**: `http-pixiu.sls`, `core/protocol/response-construct.sls`
**问题**: 响应固定发 `Connection: close`，一个连接只处理一个请求。
**修复方向**: 根据请求头的 `Connection` 和 HTTP 版本决定是否保持连接；支持一个连接处理多个请求。

### 9. HEAD 方法
**文件**: `core/protocol/method.sls`, `http-pixiu.sls`
**问题**: 未定义 HEAD 方法。
**修复方向**: 补充 HEAD；HEAD 响应与 GET 一致但不含 body。

### 10. 静态文件目录 fallback (index.html)
**文件**: `http-pixiu.sls`
**问题**: 请求 `/` 时尝试打开 `./static/`（目录）作为文件，返回 404。
**修复方向**: URI 以 `/` 结尾或打开的是目录时，尝试返回 `./static/index.html`。

### 11. 静态文件路径参数化
**文件**: `http-pixiu.sls`
**问题**: `private-static-path` 是硬编码常量。
**修复方向**: 改为 `start-server` 的可选参数。

---

## P2 — 安全与性能

### 12. 静态文件流式传输
**文件**: `http-pixiu.sls`
**问题**: `get-bytevector-all` 整文件读内存，大文件会 OOM。
**修复方向**: 分块读取并直接写入 socket，不驻留完整文件内容。

### 13. 逐字节 I/O 优化
**文件**: `core/util/binary-read.sls`, `core/util/io.sls`
**问题**: `step-forward-to` 逐字节 read/put，大 header 时极慢。
**修复方向**: 使用 buffered read 或批量读取。

### 14. 缓存头 (Last-Modified / ETag)
**文件**: `http-pixiu.sls`
**问题**: 没有缓存相关头，每次全量传输。
**修复方向**: 给静态文件响应加上 `Last-Modified`，支持 `If-Modified-Since` 返回 304。

### 15. Range 请求
**文件**: `http-pixiu.sls`
**问题**: 不支持断点续传。
**修复方向**: 解析 `Range` 头，返回 206 Partial Content。

---

## P3 — 代码质量与扩展性

### 16. 全局 `shutdown-flag` 隔离
**文件**: `http-pixiu.sls`
**问题**: 模块级变量，多实例互相干扰。
**修复方向**: 将 shutdown 状态放入 `server` 记录中。

### 17. 优雅关闭
**文件**: `http-pixiu.sls`
**问题**: `stop-server` 睡 2 秒就结束，不等待在途请求。
**修复方向**: 跟踪活跃连接，等 worker 完成或超时。

### 18. Handler API 改进
**文件**: `http-pixiu.sls`
**问题**: handler 返回 bool + 自己写 port，contract 奇怪。
**修复方向**: handler 返回 `(values status headers body)`，框架统一写响应。

### 19. 中间件/路由
**文件**: 新增
**问题**: 无。
**修复方向**: 未来可加入简单路由表和中间件链。

### 20. MIME 表扩充
**文件**: `core/mime.sls`
**问题**: 缺少 webp、wasm、avif、视频/音频类型。
**修复方向**: 补充常见现代类型。

---

## 执行顺序

按以下顺序逐个解决：
1. P0-1: 修复 GET/HEAD 请求解析
2. P0-5: 导出 server-log-port
3. P0-6: 修复 Date 头格式
4. P0-3 + P0-4: 修复路径遍历 + 错误码映射
5. P0-2: 修复任务超时
6. P0-7: accept 失败退避
7. P1-8: Keep-Alive
8. P1-9: HEAD 方法
9. P1-10: index.html fallback
10. P1-11: 静态路径参数化
11. P2-12: 流式传输静态文件
12. ... 后续按需继续
