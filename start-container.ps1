
[CmdletBinding()]
param (
    [ValidateSet("minio", "redis", 'postgre', 'etcd', 'nacos', 'rabbitmq')]
    $Mode,

    [ValidateSet("always", "unless-stopped", 'on-failure', 'on-failure:3', 'no')]
    $Restart = 'always'
)
    

# docker映射数据卷的根目录
$dockerDataPath = "C:/docker_data"



switch ($Mode) {

    'minio' {
        docker run -d --name minio-dev `
            -p 9000:9000 -p 9001:9001 `
            -v $dockerDataPath/minio:/bitnami/minio/data `
            -e MINIO_ROOT_USER=root `
            -e MINIO_ROOT_PASSWORD=12345678 `
            --restart = $Restart `
            bitnami/minio
    }
     
    'redis' {
        docker run -d --name redis-dev -p 6379:6379 redis
    }
    'postgre' {
        docker run --name postgre-dev -d -p 5432:5432 `
            -e POSTGRES_PASSWORD=123456 `
            -e TZ=Asia/Shanghai `
            -v $dockerDataPath/postgresql/data:/var/lib/postgresql/data `
            --restart = $Restart `
            postgres

        # 创建nestAdmin表
        # docker exec -it postgre-dev ` psql -U postgres `
        #     -c "CREATE DATABASE nestAdmin"
        
    }
    'etcd' {
        # ! 注意这里移除了etcd的认证，意味着本地谁都能访问，只适合本地开发环境使用
        docker run --name etcd-dev -d -p 2379:2379 `
            -p 2380:2380 `
            -e ETCD_ROOT_PASSWORD=123456 `
            -e ALLOW_NONE_AUTHENTICATION=yes `
            -e ETCD_ADVERTISE_CLIENT_URLS=http://etcd-server:2379 `
            --restart = $Restart `
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
        docker run --name nacos-dev -d -p 8848:8848 `
            -e MODE=standalone `
            --restart = $Restart `
            nacos/nacos-server
    }

    'rabbitmq' {
        docker run -d --name rabbitmq-dev `
            -p 5672:5672 -p 15672:15672 `
            --restart = $Restart `
            rabbitmq
    }

}
