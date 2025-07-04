<knowledge id="golang-ecosystem">
  <domain>Go语言生态系统</domain>
  <version>2024</version>
  
  <section title="Web框架">
    ## 主流Web框架
    
    ### Gin框架
    ```go
    // 基本使用
    func main() {
        r := gin.Default()
        
        // 中间件
        r.Use(gin.Logger())
        r.Use(gin.Recovery())
        
        // 路由组
        api := r.Group("/api/v1")
        {
            api.GET("/users", getUsers)
            api.POST("/users", createUser)
            api.GET("/users/:id", getUser)
            api.PUT("/users/:id", updateUser)
            api.DELETE("/users/:id", deleteUser)
        }
        
        r.Run(":8080")
    }
    
    // 处理函数
    func getUsers(c *gin.Context) {
        page := c.DefaultQuery("page", "1")
        limit := c.DefaultQuery("limit", "10")
        
        users, err := userService.GetUsers(page, limit)
        if err != nil {
            c.JSON(500, gin.H{"error": err.Error()})
            return
        }
        
        c.JSON(200, gin.H{"data": users})
    }
    
    // 自定义中间件
    func AuthMiddleware() gin.HandlerFunc {
        return func(c *gin.Context) {
            token := c.GetHeader("Authorization")
            if token == "" {
                c.AbortWithStatusJSON(401, gin.H{"error": "unauthorized"})
                return
            }
            
            user, err := validateToken(token)
            if err != nil {
                c.AbortWithStatusJSON(401, gin.H{"error": "invalid token"})
                return
            }
            
            c.Set("user", user)
            c.Next()
        }
    }
    ```
    
    ### Echo框架
    ```go
    func main() {
        e := echo.New()
        
        // 中间件
        e.Use(middleware.Logger())
        e.Use(middleware.Recover())
        e.Use(middleware.CORS())
        
        // 路由
        e.GET("/", hello)
        e.POST("/users", createUser)
        
        e.Logger.Fatal(e.Start(":1323"))
    }
    
    func hello(c echo.Context) error {
        return c.String(http.StatusOK, "Hello, World!")
    }
    ```
    
    ### Fiber框架
    ```go
    func main() {
        app := fiber.New(fiber.Config{
            ErrorHandler: customErrorHandler,
        })
        
        // 中间件
        app.Use(logger.New())
        app.Use(cors.New())
        
        // 路由
        api := app.Group("/api")
        api.Get("/users", getUsers)
        api.Post("/users", createUser)
        
        log.Fatal(app.Listen(":3000"))
    }
    ```
  </section>
  
  <section title="数据库">
    ## 数据库操作
    
    ### GORM
    ```go
    // 模型定义
    type User struct {
        ID        uint           `gorm:"primaryKey"`
        CreatedAt time.Time
        UpdatedAt time.Time
        DeletedAt gorm.DeletedAt `gorm:"index"`
        Name      string         `gorm:"size:100;not null"`
        Email     string         `gorm:"uniqueIndex"`
        Posts     []Post         `gorm:"foreignKey:UserID"`
    }
    
    type Post struct {
        ID     uint   `gorm:"primaryKey"`
        Title  string `gorm:"size:200"`
        Body   string `gorm:"type:text"`
        UserID uint
        User   User `gorm:"constraint:OnUpdate:CASCADE,OnDelete:SET NULL;"`
    }
    
    // 数据库操作
    func initDB() *gorm.DB {
        dsn := "user:pass@tcp(127.0.0.1:3306)/dbname?charset=utf8mb4&parseTime=True&loc=Local"
        db, err := gorm.Open(mysql.Open(dsn), &gorm.Config{
            Logger: logger.Default.LogMode(logger.Info),
        })
        if err != nil {
            panic("failed to connect database")
        }
        
        // 自动迁移
        db.AutoMigrate(&User{}, &Post{})
        return db
    }
    
    // CRUD操作
    func createUser(db *gorm.DB, user *User) error {
        return db.Create(user).Error
    }
    
    func getUserByID(db *gorm.DB, id uint) (*User, error) {
        var user User
        err := db.Preload("Posts").First(&user, id).Error
        return &user, err
    }
    
    func updateUser(db *gorm.DB, user *User) error {
        return db.Save(user).Error
    }
    
    func deleteUser(db *gorm.DB, id uint) error {
        return db.Delete(&User{}, id).Error
    }
    
    // 复杂查询
    func getUsersWithPagination(db *gorm.DB, page, limit int) ([]User, error) {
        var users []User
        offset := (page - 1) * limit
        
        err := db.Preload("Posts").
            Offset(offset).
            Limit(limit).
            Find(&users).Error
            
        return users, err
    }
    ```
    
    ### 原生SQL
    ```go
    // database/sql包
    func initDB() *sql.DB {
        db, err := sql.Open("mysql", "user:password@/dbname")
        if err != nil {
            log.Fatal(err)
        }
        
        // 连接池配置
        db.SetMaxOpenConns(25)
        db.SetMaxIdleConns(25)
        db.SetConnMaxLifetime(5 * time.Minute)
        
        return db
    }
    
    // 查询操作
    func getUser(db *sql.DB, id int) (*User, error) {
        query := "SELECT id, name, email FROM users WHERE id = ?"
        row := db.QueryRow(query, id)
        
        var user User
        err := row.Scan(&user.ID, &user.Name, &user.Email)
        if err != nil {
            return nil, err
        }
        
        return &user, nil
    }
    
    // 事务操作
    func transferMoney(db *sql.DB, fromID, toID int, amount float64) error {
        tx, err := db.Begin()
        if err != nil {
            return err
        }
        defer tx.Rollback()
        
        // 扣款
        _, err = tx.Exec("UPDATE accounts SET balance = balance - ? WHERE id = ?", amount, fromID)
        if err != nil {
            return err
        }
        
        // 入账
        _, err = tx.Exec("UPDATE accounts SET balance = balance + ? WHERE id = ?", amount, toID)
        if err != nil {
            return err
        }
        
        return tx.Commit()
    }
    ```
    
    ### Redis
    ```go
    // go-redis客户端
    func initRedis() *redis.Client {
        rdb := redis.NewClient(&redis.Options{
            Addr:     "localhost:6379",
            Password: "",
            DB:       0,
        })
        
        // 测试连接
        ctx := context.Background()
        _, err := rdb.Ping(ctx).Result()
        if err != nil {
            log.Fatal(err)
        }
        
        return rdb
    }
    
    // 缓存操作
    func setCache(rdb *redis.Client, key string, value interface{}, expiration time.Duration) error {
        ctx := context.Background()
        return rdb.Set(ctx, key, value, expiration).Err()
    }
    
    func getCache(rdb *redis.Client, key string) (string, error) {
        ctx := context.Background()
        return rdb.Get(ctx, key).Result()
    }
    
    // 分布式锁
    func acquireLock(rdb *redis.Client, key string, expiration time.Duration) (bool, error) {
        ctx := context.Background()
        result := rdb.SetNX(ctx, key, "locked", expiration)
        return result.Val(), result.Err()
    }
    ```
  </section>
  
  <section title="微服务">
    ## 微服务框架
    
    ### gRPC
    ```protobuf
    // user.proto
    syntax = "proto3";
    
    package user;
    option go_package = "./proto";
    
    service UserService {
        rpc GetUser(GetUserRequest) returns (GetUserResponse);
        rpc CreateUser(CreateUserRequest) returns (CreateUserResponse);
        rpc ListUsers(ListUsersRequest) returns (stream User);
    }
    
    message User {
        int32 id = 1;
        string name = 2;
        string email = 3;
    }
    
    message GetUserRequest {
        int32 id = 1;
    }
    
    message GetUserResponse {
        User user = 1;
    }
    ```
    
    ```go
    // gRPC服务端
    type server struct {
        pb.UnimplementedUserServiceServer
    }
    
    func (s *server) GetUser(ctx context.Context, req *pb.GetUserRequest) (*pb.GetUserResponse, error) {
        user := &pb.User{
            Id:    req.Id,
            Name:  "John Doe",
            Email: "john@example.com",
        }
        
        return &pb.GetUserResponse{User: user}, nil
    }
    
    func main() {
        lis, err := net.Listen("tcp", ":50051")
        if err != nil {
            log.Fatalf("failed to listen: %v", err)
        }
        
        s := grpc.NewServer()
        pb.RegisterUserServiceServer(s, &server{})
        
        log.Printf("server listening at %v", lis.Addr())
        if err := s.Serve(lis); err != nil {
            log.Fatalf("failed to serve: %v", err)
        }
    }
    
    // gRPC客户端
    func main() {
        conn, err := grpc.Dial("localhost:50051", grpc.WithInsecure())
        if err != nil {
            log.Fatalf("did not connect: %v", err)
        }
        defer conn.Close()
        
        c := pb.NewUserServiceClient(conn)
        
        ctx, cancel := context.WithTimeout(context.Background(), time.Second)
        defer cancel()
        
        r, err := c.GetUser(ctx, &pb.GetUserRequest{Id: 1})
        if err != nil {
            log.Fatalf("could not get user: %v", err)
        }
        
        log.Printf("User: %v", r.GetUser())
    }
    ```
    
    ### Go-kit
    ```go
    // 服务定义
    type StringService interface {
        Uppercase(string) (string, error)
        Count(string) int
    }
    
    type stringService struct{}
    
    func (stringService) Uppercase(s string) (string, error) {
        if s == "" {
            return "", ErrEmpty
        }
        return strings.ToUpper(s), nil
    }
    
    func (stringService) Count(s string) int {
        return len(s)
    }
    
    var ErrEmpty = errors.New("empty string")
    
    // 中间件
    func loggingMiddleware(logger log.Logger) ServiceMiddleware {
        return func(next StringService) StringService {
            return logmw{logger, next}
        }
    }
    
    type logmw struct {
        logger log.Logger
        StringService
    }
    
    func (mw logmw) Uppercase(s string) (output string, err error) {
        defer func(begin time.Time) {
            mw.logger.Log(
                "method", "uppercase",
                "input", s,
                "output", output,
                "err", err,
                "took", time.Since(begin),
            )
        }(time.Now())
        
        output, err = mw.StringService.Uppercase(s)
        return
    }
    ```
  </section>
  
  <section title="消息队列">
    ## 消息队列
    
    ### NATS
    ```go
    // 发布订阅
    func main() {
        nc, err := nats.Connect(nats.DefaultURL)
        if err != nil {
            log.Fatal(err)
        }
        defer nc.Close()
        
        // 订阅
        sub, err := nc.Subscribe("updates", func(m *nats.Msg) {
            fmt.Printf("Received: %s\n", string(m.Data))
        })
        if err != nil {
            log.Fatal(err)
        }
        defer sub.Unsubscribe()
        
        // 发布
        nc.Publish("updates", []byte("Hello NATS!"))
        
        // 请求响应
        msg, err := nc.Request("help", []byte("help me"), time.Second)
        if err != nil {
            log.Fatal(err)
        }
        fmt.Printf("Reply: %s\n", msg.Data)
    }
    ```
    
    ### RabbitMQ
    ```go
    // 生产者
    func publishMessage(message string) error {
        conn, err := amqp.Dial("amqp://guest:guest@localhost:5672/")
        if err != nil {
            return err
        }
        defer conn.Close()
        
        ch, err := conn.Channel()
        if err != nil {
            return err
        }
        defer ch.Close()
        
        q, err := ch.QueueDeclare(
            "hello", // name
            false,   // durable
            false,   // delete when unused
            false,   // exclusive
            false,   // no-wait
            nil,     // arguments
        )
        if err != nil {
            return err
        }
        
        return ch.Publish(
            "",     // exchange
            q.Name, // routing key
            false,  // mandatory
            false,  // immediate
            amqp.Publishing{
                ContentType: "text/plain",
                Body:        []byte(message),
            })
    }
    
    // 消费者
    func consumeMessages() error {
        conn, err := amqp.Dial("amqp://guest:guest@localhost:5672/")
        if err != nil {
            return err
        }
        defer conn.Close()
        
        ch, err := conn.Channel()
        if err != nil {
            return err
        }
        defer ch.Close()
        
        msgs, err := ch.Consume(
            "hello", // queue
            "",      // consumer
            true,    // auto-ack
            false,   // exclusive
            false,   // no-local
            false,   // no-wait
            nil,     // args
        )
        if err != nil {
            return err
        }
        
        forever := make(chan bool)
        
        go func() {
            for d := range msgs {
                log.Printf("Received: %s", d.Body)
            }
        }()
        
        <-forever
        return nil
    }
    ```
  </section>
  
  <section title="配置管理">
    ## 配置管理
    
    ### Viper
    ```go
    // 配置文件config.yaml
    /*
    database:
      host: localhost
      port: 5432
      user: postgres
      password: secret
      dbname: myapp
    
    server:
      port: 8080
      host: 0.0.0.0
    
    redis:
      addr: localhost:6379
      password: ""
      db: 0
    */
    
    type Config struct {
        Database DatabaseConfig `mapstructure:"database"`
        Server   ServerConfig   `mapstructure:"server"`
        Redis    RedisConfig    `mapstructure:"redis"`
    }
    
    type DatabaseConfig struct {
        Host     string `mapstructure:"host"`
        Port     int    `mapstructure:"port"`
        User     string `mapstructure:"user"`
        Password string `mapstructure:"password"`
        DBName   string `mapstructure:"dbname"`
    }
    
    func loadConfig() (*Config, error) {
        viper.SetConfigName("config")
        viper.SetConfigType("yaml")
        viper.AddConfigPath(".")
        viper.AddConfigPath("./config")
        
        // 环境变量
        viper.AutomaticEnv()
        viper.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))
        
        // 默认值
        viper.SetDefault("server.port", 8080)
        viper.SetDefault("server.host", "localhost")
        
        if err := viper.ReadInConfig(); err != nil {
            return nil, err
        }
        
        var config Config
        if err := viper.Unmarshal(&config); err != nil {
            return nil, err
        }
        
        return &config, nil
    }
    ```
  </section>
  
  <section title="日志">
    ## 日志框架
    
    ### Logrus
    ```go
    func initLogger() *logrus.Logger {
        logger := logrus.New()
        
        // 设置日志级别
        logger.SetLevel(logrus.InfoLevel)
        
        // 设置输出格式
        logger.SetFormatter(&logrus.JSONFormatter{
            TimestampFormat: time.RFC3339,
        })
        
        // 设置输出目标
        file, err := os.OpenFile("app.log", os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0666)
        if err == nil {
            logger.SetOutput(io.MultiWriter(os.Stdout, file))
        } else {
            logger.Info("Failed to log to file, using default stderr")
        }
        
        return logger
    }
    
    func useLogger(logger *logrus.Logger) {
        // 结构化日志
        logger.WithFields(logrus.Fields{
            "user_id": 123,
            "action":  "login",
        }).Info("User logged in")
        
        // 错误日志
        err := errors.New("database connection failed")
        logger.WithError(err).Error("Failed to connect to database")
    }
    ```
    
    ### Zap
    ```go
    func initZapLogger() *zap.Logger {
        config := zap.NewProductionConfig()
        config.OutputPaths = []string{"stdout", "app.log"}
        
        logger, err := config.Build()
        if err != nil {
            panic(err)
        }
        
        return logger
    }
    
    func useZapLogger(logger *zap.Logger) {
        defer logger.Sync()
        
        // 结构化日志
        logger.Info("User logged in",
            zap.Int("user_id", 123),
            zap.String("action", "login"),
            zap.Duration("duration", time.Millisecond*200),
        )
        
        // 错误日志
        logger.Error("Failed to process request",
            zap.Error(errors.New("invalid input")),
            zap.String("request_id", "req-123"),
        )
    }
    ```
  </section>
  
  <section title="测试工具">
    ## 测试框架
    
    ### Testify
    ```go
    func TestUserService(t *testing.T) {
        // 使用assert
        user := &User{Name: "John", Email: "john@example.com"}
        assert.NotNil(t, user)
        assert.Equal(t, "John", user.Name)
        assert.Contains(t, user.Email, "@")
        
        // 使用require（失败时停止测试）
        require.NotNil(t, user)
        require.NoError(t, validateUser(user))
    }
    
    // 测试套件
    type UserServiceTestSuite struct {
        suite.Suite
        service *UserService
        db      *sql.DB
    }
    
    func (suite *UserServiceTestSuite) SetupTest() {
        suite.db = setupTestDB()
        suite.service = NewUserService(suite.db)
    }
    
    func (suite *UserServiceTestSuite) TearDownTest() {
        suite.db.Close()
    }
    
    func (suite *UserServiceTestSuite) TestCreateUser() {
        user := &User{Name: "Test", Email: "test@example.com"}
        err := suite.service.CreateUser(user)
        suite.NoError(err)
        suite.NotZero(user.ID)
    }
    
    func TestUserServiceTestSuite(t *testing.T) {
        suite.Run(t, new(UserServiceTestSuite))
    }
    ```
    
    ### GoMock
    ```go
    //go:generate mockgen -source=user.go -destination=mocks/user_mock.go
    
    type UserRepository interface {
        GetUser(id int) (*User, error)
        SaveUser(user *User) error
    }
    
    func TestUserService_GetUser(t *testing.T) {
        ctrl := gomock.NewController(t)
        defer ctrl.Finish()
        
        mockRepo := mocks.NewMockUserRepository(ctrl)
        service := NewUserService(mockRepo)
        
        expectedUser := &User{ID: 1, Name: "John"}
        mockRepo.EXPECT().GetUser(1).Return(expectedUser, nil)
        
        user, err := service.GetUser(1)
        assert.NoError(t, err)
        assert.Equal(t, expectedUser, user)
    }
    ```
  </section>
</knowledge>