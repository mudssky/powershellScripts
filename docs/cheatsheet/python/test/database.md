### 1. 环境一致性：使用 Docker 容器 (Testcontainers)

不要用 SQLite 测试 PostgreSQL，也不要依赖本地安装好的 DB。

* **原则**：测试环境必须与生产环境同构（Prod-parity）。
* **做法**：
  * 使用 **Docker** 运行临时的 PostgreSQL 实例。
  * 推荐使用 python 库 **`testcontainers`**。它能在测试代码运行时自动拉起容器，测试结束后自动销毁，无需手动写 `docker-compose`。
* **好处**：隔离性好，无论谁在跑测试（本地开发或 CI/CD），环境都是 100% 干净且一致的。

### 2. 性能优化：全局建表 + 事务回滚 (Transaction Rollback)

数据库测试最大的瓶颈是 I/O。如果每个测试用例都 `Create Table` -> `Insert` -> `Drop Table`，速度会极慢。

* **原则**：**只建一次表，每个测试用例只做数据回滚。**
* **最佳实践架构**：
    1. **Session 级 Fixture**：启动 DB 容器，运行 Migration（或 `create_all`）建表。整个测试过程只做一次。
    2. **Function 级 Fixture**：
        * 在测试开始前：开启一个数据库**事务 (Transaction)**。
        * 运行测试逻辑（增删改查）。
        * 在测试结束后：**强制回滚 (Rollback)** 事务。
* **结果**：下一个测试用例拿到的永远是干净的空表（或只有基础种子数据的表），且无需重复建表，速度极快。

### 3. 数据管理：使用 Factory Boy (而非硬编码字典)

不要在测试代码里手写大量的 JSON 或字典数据来插入数据库。

* **原则**：让数据生成变得动态且可维护。
* **工具**：使用 **`factory_boy`** (配合 `SQLAlchemy` 或 `Django ORM`)。
* **做法**：定义一个 Factory 类，它能自动填充必填字段，并支持按需覆盖字段。

    ```python
    # 比如创建一个用户的测试数据
    user = UserFactory(username="test_user") 
    # 不需要关心的字段（如 email, created_at）会自动生成
    ```

* **好处**：当数据库表结构变更（比如增加一个非空列）时，你只需要修改 Factory 一个地方，而不用去修几百个测试用例。

### 4. 夹具分层：conftest.py 的组织

合理利用 pytest 的 scope（作用域）来管理资源。

| Fixture 名称 | Scope | 作用 |
| :--- | :--- | :--- |
| `db_container` | **Session** | 启动 Docker 容器，等待端口就绪。 |
| `db_engine` | **Session** | 创建连接引擎，执行 Alembic 迁移/建表。 |
| `db_session` | **Function** | **核心夹具**。连接到 engine，开启事务，yield session 给测试用例，最后 rollback。 |
| `basic_user` | **Function** | 调用 Factory 生成基础用户数据，供具体测试使用。 |

### 5. 专门测试迁移脚本 (Migration Testing)

既然你刚做了迁移，这一点尤为重要。

* **原则**：代码逻辑对是没用的，如果上线时 `alembic upgrade` 挂了就全完了。
* **做法**：编写一个专门的测试，在一个干净的库上从头跑到尾执行 `alembic upgrade head`，确保迁移脚本本身没有语法错误或逻辑冲突。

---

### 代码模板（基于 SQLAlchemy + Pytest）

这是一个符合上述最佳实践的 `tests/conftest.py` 模板：

```python
import pytest
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker
from testcontainers.postgres import PostgresContainer
from src.database import Base  # 假设这是你的 ORM Base

# 1. Session 级：启动容器 (环境一致性)
@pytest.fixture(scope="session")
def pg_container():
    with PostgresContainer("postgres:15-alpine") as postgres:
        yield postgres

# 2. Session 级：建表 (只做一次)
@pytest.fixture(scope="session")
def engine(pg_container):
    db_url = pg_container.get_connection_url()
    engine = create_engine(db_url)
    
    # 创建所有表结构
    Base.metadata.create_all(engine)
    return engine

# 3. Function 级：事务回滚 (性能核心)
@pytest.fixture(scope="function")
def db_session(engine):
    # 连接数据库
    connection = engine.connect()
    # 开启事务
    transaction = connection.begin()
    
    # 绑定 session 到这个连接
    Session = sessionmaker(bind=connection)
    session = Session()

    yield session  # 测试用例在这里运行

    # 测试结束后：回滚事务，关闭连接
    session.close()
    transaction.rollback()
    connection.close()

# 4. 自动注入：让业务代码使用测试的 session
# 这一步取决于你的依赖注入框架，如果是 FastAPI 可以 override_dependency
```

### 总结

1. **抛弃 SQLite**，拥抱 Docker/PostgreSQL。
2. **Session 级建表**，**Function 级回滚**。
3. 用 **Factory Boy** 造数据。
4. CI/CD 必须跑在真实数据库服务上。
