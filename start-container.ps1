
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateSet("minio", "redis", 'postgre', 'etcd', 'nacos', 'rabbitmq', 'mongodb', ‘one-api', 'mongodb-replica' )]
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
        $env:DOCKER_DATA_PATH=$DataPath
        $env:MONGO_USER=$DefaultUser
        $env:MONGO_PASSWORD=$DefaultPassword
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
}
