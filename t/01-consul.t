use Test::Nginx::Socket;
use Cwd qw(cwd);

plan tests => repeat_each() * blocks() * 3;

our $pwd = cwd();
our $http_config = qq{
    lua_package_path '$pwd/lib/?.lua;$pwd/t/lib/?.lua;;';
    lua_shared_dict  disco 10m;
};

no_long_string();
run_tests();

__DATA__

=== TEST 1: list() will return empty list if there's nothing
--- http_config eval
"$::http_config"
. q{
    init_by_lua_block {
        local dict = ngx.shared['disco']
        local consul = require 'resty.disco.consul'

        c = consul:new({
            dict = dict,
            host = '127.0.0.1',
            service_name = 'test',
            port = 9999,
            passing = true,
            stale = true,
            wait = 1000,
            on_update = function() end,
            on_error = function() end
        })
    }
}
--- config
  location /t {
    content_by_lua_block {
        local json = require 'cjson'
        ngx.say(json.encode(c:list()))
    }
  }
--- request
GET /t
--- no_error_log
[error]
--- response_body
{}


=== TEST 2: it will try to call health check route to get services
--- http_config eval
"$::http_config"
. q{
    init_by_lua_block {
        local dict = ngx.shared['disco']
        local consul = require 'resty.disco.consul'

        c = consul:new({
            dict = dict,
            host = '127.0.0.1',
            service_name = 'test',
            port = 9999,
            passing = true,
            stale = true,
            wait = 1000,
            on_update = function() end,
            on_error = function() end
        })
    }

    init_worker_by_lua_block {
        c:start_running()
    }

    server {
        listen 9999;
        location = /v1/health/service/test {
            content_by_lua_block {
                local json = require 'cjson'
                ngx.say(json.encode({
                    {
                        Service = {
                            Address = '10.0.0.1',
                            Port = 1999
                        }
                    }
                }))
            }
        }
    }
}
--- config
  location /t {
    content_by_lua_block {
        local json = require 'cjson'
        ngx.sleep(1)
        ngx.say(json.encode(c:list()))
    }
  }
--- request
GET /t
--- no_error_log
[error]
--- response_body
{}
--- timeout: 5
