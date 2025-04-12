FROM postgres:17 AS builder

# 安装构建依赖
RUN apt-get update && \
    apt-get install -y build-essential postgresql-server-dev-17 git

# 编译pgvector
WORKDIR /tmp
RUN git clone --branch v0.8.0 https://github.com/pgvector/pgvector.git && \
    cd pgvector && \
    make && \
    make install

FROM postgres:17

# 复制编译好的pgvector库
COPY --from=builder /usr/lib/postgresql/17/lib/ /usr/lib/postgresql/17/lib/
COPY --from=builder /usr/share/postgresql/17/extension/ /usr/share/postgresql/17/extension/

# 设置环境变量
ENV POSTGRES_HOST_AUTH_METHOD=trust
ENV PGVECTOR_VERSION=0.8.0

# 添加元数据
LABEL maintainer="mudssky@gmail.com"
LABEL version="0.1"
LABEL description="PostgreSQL 17 with pgvector extension v0.8.0"

# 复制初始化脚本
COPY sql-init/pgvector-init.sql /docker-entrypoint-initdb.d/

# 健康检查
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD pg_isready -U postgres || exit 1

# 暴露端口
EXPOSE 5432