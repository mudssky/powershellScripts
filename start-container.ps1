
<#
.SYNOPSIS
    Docker容器服务启动脚本

.DESCRIPTION
    该脚本用于快速启动各种常用的Docker容器服务，包括数据库、消息队列、
    监控工具等。支持自定义重启策略、数据目录和认证信息。

.PARAMETER ServiceName
    要启动的服务名称，支持的服务包括：
    - minio: 对象存储服务
    - redis: 内存数据库
    - postgre: PostgreSQL数据库
    - etcd: 分布式键值存储
    - nacos: 服务发现和配置管理
    - rabbitmq: 消息队列
    - mongodb: 文档数据库
    - one-api: API网关
    - mongodb-replica: MongoDB副本集
    - kokoro-fastapi: FastAPI服务
    - cadvisor: 容器监控
    - prometheus: 监控系统
    - noco: 无代码平台

.PARAMETER RestartPolicy
    容器重启策略，默认为'unless-stopped'。可选值：
    - always: 总是重启
    - unless-stopped: 除非手动停止否则重启
    - on-failure: 失败时重启
    - on-failure:3: 失败时最多重启3次
    - no: 不自动重启

.PARAMETER DataPath
    数据存储目录，默认为"C:/docker_data"

.PARAMETER DefaultUser
    默认用户名，默认为"root"

.PARAMETER DefaultPassword
    默认密码，默认为"12345678"

.EXAMPLE
    .\start-container.ps1 -ServiceName redis
    启动Redis容器服务

.EXAMPLE
    .\start-container.ps1 -ServiceName mongodb -RestartPolicy always -DataPath "D:/data"
    启动MongoDB服务并自定义重启策略和数据目录

.NOTES
    需要安装Docker
    脚本会自动创建必要的数据目录
    某些服务可能需要额外的配置文件
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateSet("minio", "redis", 'postgre', 'etcd', 'nacos', 'rabbitmq', 'mongodb', 'one-api', 'mongodb-replica', 'kokoro-fastapi', 'kokoro-fastapi-cpu', 'cadvisor', 'prometheus', 'noco', 'n8n')]
    [string]$ServiceName, # 更合理的参数名
    
    [ValidateSet("always", "unless-stopped", 'on-failure', 'on-failure:3', 'no')]
    [string]$RestartPolicy = 'unless-stopped', # 更明确的参数名
    
    [string]$DataPath = "C:/docker_data"  ,# 允许自定义数据目录
    [string]$DefaultUser = "root",  # 默认用户名
    [string]$DefaultPassword = "12345678"  # 默认密码
)
  

# 可以添加统一网络配置
# $networkName = "dev-net"
# if (-not (docker network ls -q -f name="$networkName")) {
#     docker network create $networkName
# }

# 使用数组存储日志配置参数
$commonParams = @(
    # 日志相关参数
    "--log-driver", "json-file",
    "--log-opt", "max-size=10m",
    "--log-opt", "max-file=3"
    # 网络配置
    # "--network","dev-net"
)
$pgHealthCheck = @(
    "--health-cmd", "pg_isready -U postgres",
    "--health-interval", "10s",
    "--health-timeout", "5s",
    "--health-retries", "3"
)


switch ($ServiceName) {

    'minio' {
        docker run -d --name minio-dev `
            $commonParams`
        -p 9000:9000 -p 9001:9001 `
            -v $DataPath/minio:/bitnami/minio/data `
            -e MINIO_ROOT_USER=$DefaultUser `
            -e MINIO_ROOT_PASSWORD=$DefaultPassword `
            --restart=$RestartPolicy `
            bitnami/minio
    }
     
    'redis' {
        docker run -d --name redis-dev `
            $commonParams`
        -p 6379:6379 --restart=$RestartPolicy redis 
    }
    'postgre' {
        docker run --name postgre-dev -d `
            $commonParams`
        -p 5432:5432 `
            $pgHealthCheck `
            -e POSTGRES_PASSWORD=$DefaultPassword `
            -e TZ=Asia/Shanghai `
            -v $DataPath/postgresql/data:/var/lib/postgresql/data `
            --restart=$RestartPolicy `
            postgres

        # 创建nestAdmin表
        # docker exec -it postgre-dev ` psql -U postgres `
        #     -c "CREATE DATABASE nestAdmin"
        
    }
    # 其他服务同样添加$commonParams参数
    'etcd' {
        docker run --name etcd-dev -d `
            $commonParams`
        -p 2379:2379 -p 2380:2380 `
            -e ETCD_ROOT_PASSWORD=$DefaultPassword `
            -e ALLOW_NONE_AUTHENTICATION=yes `
            -e ETCD_ADVERTISE_CLIENT_URLS=http://etcd-server:2379 `
            --restart=$RestartPolicy `
            bitnami/etcd

        # docker run --name etcd-dev -d -p 2379:2379 `
        #     -p 2380:2380 `
        #     -e ETCD_ROOT_PASSWORD=123456 `
        #     -e ETCDCTL_USER=root `
        #     -e ETCDCTL_PASSWORD=123456 `
        #     bitnami/etcd
       

        # docker login -u mudssky
        # 需要去docker个人页面获取token登录才能拉取
    }
    'nacos' {
        docker run --name nacos-dev -d `
            $commonParams`
        -p 8848:8848 `
            -e MODE=standalone `
            --restart=$RestartPolicy `
            nacos/nacos-server
    }

    'rabbitmq' {
        docker run -d --name rabbitmq-dev `
            $commonParams`
        -p 5672:5672 -p 15672:15672 `
            --restart=$RestartPolicy `
            rabbitmq
    }
    'mongodb' {
        docker run -d --name mongodb-dev `
            $commonParams `
            -p 27017:27017 `
            -v $DataPath/mongodb:/data/db `
            --restart=$RestartPolicy `
            mongo:8
    }
    
    'mongodb-replica' {
        $env:DOCKER_DATA_PATH = $DataPath
        $env:MONGO_USER = $DefaultUser
        $env:MONGO_PASSWORD = $DefaultPassword
        docker-compose  -p mongo-repl-dev -f dockerfiles/compose/mongo-repl.compose.yml up -d
    }
    ‘one-api’ {
        docker run -d  --name one-api-dev `
            $commonParams `
            -p 39010:3000 `
            -e TZ=Asia/Shanghai `
            -v $DataPath/one-api:/data `
            --restart=$RestartPolicy `
            justsong/one-api
    }
    # ai模型相关
    'kokoro-fastapi' {
        docker run -d --name kokoro-fastapi-dev `
            $commonParams `
            --gpus all -p 38880:8880 `
            --restart=$RestartPolicy `
            ghcr.io/remsky/kokoro-fastapi-gpu:latest
    }
    'kokoro-fastapi-cpu' {
        docker run -d --name kokoro-fastapi-dev `
            $commonParams `
            -p 38880:8880 `
            --restart=$RestartPolicy `
            ghcr.io/remsky/kokoro-fastapi-cpu:latest
    }
    'cadvisor' {
        docker run -d --name cadvisor-dev `
            $commonParams `
            -p 38181:8080 `
            --volume=/:/rootfs:ro `
            --volume=/var/run:/var/run:ro `
            --volume=/sys:/sys:ro `
            --volume=/var/lib/docker/:/var/lib/docker:ro `
            --volume=/dev/disk/:/dev/disk:ro `
            --privileged `
            --device=/dev/kmsg `
            --restart=$RestartPolicy `
            gcr.io/cadvisor/cadvisor:$VERSION
    }
    'prometheus' {
        docker run -d --name prometheus-dev `
            $commonParams `
            -p 39090:9090 `
            --restart=$RestartPolicy `
            prom/prometheus
    }
    'n8n' {
        docker run -d --name n8n-dev `
            $commonParams `
            -p 35678:5678 `
            -v $DataPath/n8n:/home/node/.n8n `
            --restart=$RestartPolicy `
            docker.n8n.io/n8nio/n8n
    }
    'noco' {
        docker run -d --name noco-dev `
            $commonParams `
            -p 35080:8080 `
            -v $DataPath/nocodb:/usr/app/data/ `
            --restart=$RestartPolicy `
            nocodb/nocodb:latest
    }
}
