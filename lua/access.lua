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