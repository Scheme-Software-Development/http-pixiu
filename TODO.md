# http-pixiu 待办优化

> 以下优化已评估，因代码结构或运行时兼容性问题尚未完成，记录于此供后续处理。

---

## P1 — 静态文件冗余 stat + 预压缩 .gz 优化（改动 2 & 3）

**目标**：缓存命中时跳过 `file-modification-time` 和 `.gz` 预压缩文件的 `stat` 检查。

**障碍**：`http-pixiu.sls` 中的 `serve-static-file` 有 **170 行、11 层嵌套**。
- `cache-lookup` 在最内层（`let cached → if cached`）
- `file-modification-time` 和 `.gz` 检查（`file-exists?` + `file-modification-time`）在最外层
- 要将缓存检查提前，需重构整个函数的括号层次

**尝试记录**：
- `StrReplaceFile` 大段替换 → 括号不匹配，解析失败
- Python 脚本精确提取 + 替换 → 末尾 `)` 数量计算错误（新增 `let content-type` 和 `let cached` 两层后，末尾需从 22 个 `)` 增至 24 个，手动计数极易出错）
- 独立文件 `tmp-serve-static.scm` 验证后再嵌入 → 同样因嵌套过深导致 `)` 差 2~3 个

**建议方案**：
1. 先把 `serve-static-file` 及辅助函数（`safe-path?`、`parse-range-header`、`generate-multipart-body` 等）从 `http-pixiu.sls` **提取到 `core/static.sls`**（该文件已存在但未被使用），降低单函数嵌套深度。
2. 在独立模块中重构：将 `cache-lookup` 提前到 `file-modification-time` 之前。
3. 在 `http-pixiu.sls` 中改为导入 `(http-pixiu core static)`。

---

## P2 — `env` alist 改为 record type（改动 6）

**目标**：把请求环境从 alist 改为 `define-record-type`，减少每次请求的 cons/GC，提升字段访问速度（从 `assq` O(n) 到直接字段访问）。

**涉及文件**：
- `core/handler.sls`：定义 record type，修改 `env-method`、`env-path` 等 accessor
- `http-pixiu.sls`：修改 `build-request-env`、`init-lifecycle` 中 env 的构造和扩展（`body-port`、`body-count`、`client-ip`）
- `core/router.sls`：修改 `router-dispatch` 中 `params` 的注入方式
- `core/middleware.sls`：修改所有 middleware 对 env 的读取和修改（session、logging、CORS 等）

**建议设计**：
```scheme
(define-record-type request-env
  (fields method uri path query protocol headers body client-ip extensions))
```
- 固定字段（method, path, headers, body 等）用 record 字段
- 动态字段（params, session, body-port 等）存入 `extensions` hashtable/alist
- `env-get` 先查 record 字段，再查 extensions

**工作量**：系统性重构，约 1~2 小时，需逐模块测试。

---

## P3 — 调试并启用 buffered-binary-input-port（改动 7）

**目标**：用 8KB 缓冲端口包装 socket input port，减少 header 解析阶段的 syscall 次数（从逐字节 read 变为批量 read）。

**现状**：
- `core/util/binary-read.sls` 中已实现 `make-buffered-binary-input-port`
- **单元测试通过**：`lookahead-u8`、`get-u8`、`get-bytevector-n!` 在 `open-bytevector-input-port` 上均正常
- **集成测试失败**：启用后 `test-integration-extended` **超时死锁**（120 秒无响应）

**可能原因**：
1. `ufo-socket` 的 `get-bytevector-some!` 在自定义端口的 `read!` 函数中被调用时，与 Chez 的线程调度/超时机制冲突
2. `make-custom-binary-input-port` 的 `read!` 返回 0 时被 Chez 视为 EOF；若 `ufo-socket` 超时后返回 0（而非 EOF），连接会被错误地提前关闭，但测试表现为超时而非报错，说明可能是死锁而非 EOF
3. `lookahead-u8` 对自定义端口的内部 unget 机制与手动缓冲层冲突

**备选方案**（不依赖 `make-custom-binary-input-port`）：
- 不在端口层面缓冲，而是修改 `step-forward-to`（`core/util/binary-read.sls`）做批量读取
- 难点：`step-forward-to` 语义是"读到目标字节即停"，批量读取可能 over-read（多读数据丢失）
- 解决：在模块级别维护一个小型 unread buffer，供后续解析器消费

---

## 杂项

- `core/static.sls` 在 `51841d9` 中被意外提交（原为未跟踪文件）。该文件包含 `serve-static-file` 的独立实现，但当前 `http-pixiu.sls` 中仍有内嵌版本，两者未统一。
