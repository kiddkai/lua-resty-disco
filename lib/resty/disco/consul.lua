-- Copyright (C) Zekai Zheng (kiddkai)

local http = require 'resty.http'
local json = require 'cjson'
local ngx = _G.ngx
local at = ngx.timer.at
local encode_args = ngx.encode_args
local ID_KEY = 'disco|id'

local _M = {
    _VERSION = '0.1',
    ID_KEY = ID_KEY
}

local mt = { __index = _M }

function _M.new(_, opts)
    local dict = opts.dict
    local id, err = dict:incr(ID_KEY, 1)

    if not id and err == "not found" then
        dict:add(ID_KEY, 0)
        dict:incr(ID_KEY, 1)
        id = 1
    end

    return setmetatable({
        id = id,
        dict = dict,
        host = opts.host,
        port = opts.port,
        service_name = opts.service_name,
        wait = opts.wait or 10000,
        passing = opts.passing or false,
        on_update = opts.on_update,
        on_error = opts.on_error,
        keys = {
            consul_index = 'disco|' .. tostring(id) .. '|consul_index',
            size = 'disco|' .. tostring(id) .. '|size',
            ip = 'disco|' .. tostring(id) .. '|ip|',
            port = 'disco|' .. tostring(id) .. '|port|'
        }
    }, mt)
end

local function fetch_health_check_status(host, port, service_name, opts)
    local httpc = http.new()
    httpc:set_timeout(opts.timeout or 500)
    httpc:connect(host, port)

    local err, res, body, ok
    res, err = httpc:request({
        path = '/v1/health/service/' .. service_name .. '?' .. encode_args(opts)
    })

    if not res then
        return nil, err
    end

    body, err = res:read_body()

    if not body then
        return nil, err
    end

    if res.status ~= 200 then
        return nil, body
    end

    if res.headers['connection'] == 'close' then
        ok, err = httpc:close()
    else
        ok, err = httpc:set_keepalive()
    end

    if not ok then
        return nil, err
    end

    return {
        index = res.headers['x-consul-index'],
        body = json.decode(body)
    }
end

local function to_ip_port(res)
    local body = res.body
    local ip_port = {}

    local check, service
    for i = 1, #body do
        check = body[i]
        service = check.Service

        table.insert(ip_port, {
            ip = service.Address,
            port = service.Port
        })
    end

    return ip_port
end

local function work(premature, consul)
    if premature then
        return
    end

    local dict = consul.dict
    local index = dict:get(consul.keys.consul_index)
    local opts = {
        wait = consul.wait .. 'ms',
        passing = consul.passing
    }

    if index then
        opts.index = index
    end

    local res, err = fetch_health_check_status(consul.host,
                                               consul.port,
                                               consul.service_name,
                                               opts)


    if not res then
        consul.on_error(err)
    else
        local ip_ports = to_ip_port(res)
        consul:set(ip_ports)
    end

    if res.index then
        dict:set(consul.keys.consul_index, res.index)
    end

    at(1, work, consul)
end

function _M.start_running(self)
    at(1, work, self)
end

function _M.set(self, ip_ports)
    local dict = self.dict
    local ip_port

    dict:set(self.keys.size, #ip_ports)

    for i = 1, #ip_ports do
        ip_port = ip_ports[i]
        dict:set(self.keys.ip .. tostring(i), ip_port[1])
        dict:set(self.keys.port .. tostring(i), ip_port[2])
    end

    self.on_update(ip_ports)
end

function _M.list(self)
    local dict = self.dict
    local size = dict:get(self.keys.size) or 0
    local res = {}

    for i = 1, size do
        table.insert(res, {
            dict:get(self.keys.ip .. tostring(i)),
            dict:get(self.keys.ip .. tostring(i))
        })
    end

    return res
end

return _M
