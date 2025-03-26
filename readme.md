用 Docker 部署 **OpenResty + Redis**  是最省事、最干净的方式。

下面是 **超详细教程** ，一步步来，直接跑。

---

✅ 1. **目录结构设计**

假设你项目目录是这样：

```bash
/openresty-docker
├── docker-compose.yml
├── nginx.conf
└── lua
    └── access.lua
```

---

✅ 2. **编写 docker-compose.yml**

部署 OpenResty + Redis 服务

```yaml
version: '3.8'

services:
  openresty:
    image: openresty/openresty:alpine  # 轻量版
    container_name: openresty
    ports:
      - "8080:80"  # 映射宿主机8080端口
    volumes:
      - ./nginx.conf:/usr/local/openresty/nginx/conf/nginx.conf
      - ./lua:/usr/local/openresty/nginx/lua
    depends_on:
      - redis
    restart: always

  redis:
    image: redis:7.2-alpine
    container_name: redis
    ports:
      - "6379:6379"
    volumes:
      - redis-data:/data
    restart: always

volumes:
  redis-data:
```

---

✅ 3. **Nginx 配置文件 nginx.conf**

```nginx
worker_processes  1;

events {
    worker_connections  1024;
}

http {
    lua_shared_dict limits 10m;

    server {
        listen 80;

        location /api/ {
            access_by_lua_file /usr/local/openresty/nginx/lua/access.lua;

            # 你的后端API地址，测试可以写个 httpbin.org
            proxy_pass http://httpbin.org/anything;
        }
    }
}
```

---

✅ 4. **Lua 脚本 access.lua**
路径：`./lua/access.lua`

```lua
local cjson = require "cjson"
local redis = require "resty.redis"

-- 获取 API Key（可以改成你自己的 Header）
local api_key = ngx.req.get_headers()["Authorization"]
if not api_key then
    ngx.status = 401
    ngx.say(cjson.encode({ code = 401, message = "Missing API Key" }))
    return ngx.exit(401)
end

-- 连接 Redis
local red = redis:new()
red:set_timeout(1000) -- 1秒超时

local ok, err = red:connect("redis", 6379)  -- redis 是 docker-compose 的服务名，自动DNS解析
if not ok then
    ngx.status = 500
    ngx.say(cjson.encode({ code = 500, message = "Redis connection failed: " .. (err or "") }))
    return ngx.exit(500)
end

-- 校验 key 是否存在
local user_info_key = "user:" .. api_key
local exists = red:exists(user_info_key)
if exists == 0 then
    ngx.status = 401
    ngx.say(cjson.encode({ code = 401, message = "Invalid API Key" }))
    return ngx.exit(401)
end

-- 限流逻辑（简单版漏桶）
local rate_limit_key = "ratelimit:" .. api_key
local limit = 5 -- 每秒最多5次
local current, err = red:get(rate_limit_key)

if current == ngx.null then
    red:set(rate_limit_key, 1)
    red:expire(rate_limit_key, 1)
else
    current = tonumber(current)
    if current >= limit then
        ngx.status = 429
        ngx.say(cjson.encode({ code = 429, message = "Rate limit exceeded" }))
        return ngx.exit(429)
    else
        red:incr(rate_limit_key)
    end
end

-- 记录每日请求次数
local today = os.date("%Y-%m-%d")
local count_key = "counter:" .. api_key .. ":" .. today
red:incr(count_key)
red:expire(count_key, 60 * 60 * 24 * 30)

-- 释放 Redis 连接
red:set_keepalive(10000, 100)
```

---

✅ 5. **启动服务**
在 `openresty-docker` 目录下运行：

```bash
docker-compose up -d
```

查看容器状态：

```bash
docker ps
```

---

✅ 6. **初始化 Redis 数据**
打开 Redis 客户端，插入一个合法 `API Key`，模拟用户：

```bash
docker exec -it redis redis-cli
set user:test-api-key "user1"
列出所有 key：
keys *           # 列出所有键
get user:test-api-key01    # 获取特定键的值
# 一次性查看所有键值对
docker exec -it redis redis-cli --scan | while read -r key; do
  echo "Key: $key"
  docker exec -it redis redis-cli get "$key"
  echo "---"
done
```


---

✅ 7. **测试 API**
通过 curl 测试，添加 `Authorization` 请求头：

```bash
curl -H "Authorization: test-api-key" http://localhost:8080/api/
```

#### 正常返回：

```json
{
  "args": {},
  "headers": {
    ...
  },
  ...
}
```

如果 `Authorization` 错误或缺失：

```json
{"code":401,"message":"Missing API Key"}
```

#### 如果超出限流：

```json
{"code":429,"message":"Rate limit exceeded"}
```

---

✅ 8. **后续优化**


| 方向             | 说明                                               |
| ------------------ | ---------------------------------------------------- |
| 不同用户不同限额 | Redis 里存 user:{api_key}:rate 动态限流            |
| IP 白名单/黑名单 | Redis 存 whitelist/blacklist 集合                  |
| 限流算法优化     | 实现令牌桶、滑动窗口等更精准算法（Lua灵活好实现）  |
| API Key 自动过期 | Redis 设置 expire 或独立定时清理                   |
| 日志/监控        | OpenResty 日志写入 Loki + Grafana，或接 Prometheus |

---

✅ 9. **快速停止/重启/清理**

```bash
docker-compose down         # 停止服务
docker-compose up -d        # 启动服务
docker-compose restart      # 重启服务
docker-compose down -v      # 停止并清理 volumes 数据（会删掉 redis 数据）
```


✅ 10. **完整目录和文件**

```bash
/openresty-docker
├── docker-compose.yml
├── nginx.conf
└── lua
    └── access.lua
```

✅ 10. **nginx重启相关命令** 
nginx -s reload
nginx -s stop && nginx
### 🚀 小结

✅ 11. **windows部署**
下载redis和openresty
openresty地址：
https://openresty.org/download/openresty-1.27.1.1-win64.zip
启动redis服务
配置openresty环境，启动nginx服务

这个方案：

- **轻量** ：2 个容器，资源占用少
- **灵活** ：Lua 脚本按你需求随便改
- **可扩展** ：可以接入业务系统，做计费、用户管理

---

### 如果要继续完善，可以加上：

- **HTTPS 支持**
- **日志分析**
- **用户动态注册和权限系统**

---

有现成 API Key 用户管理逻辑或者计费需求，发给我，咱直接加！

要完整 zip 包或者 GitHub 项目结构，我也可以直接给你整好！
