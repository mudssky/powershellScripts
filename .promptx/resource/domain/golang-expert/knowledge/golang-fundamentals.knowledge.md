<knowledge id="golang-fundamentals">
  <domain>Go语言核心知识</domain>
  <version>1.21+</version>
  
  <section title="语言基础">
    ## Go语言特性
    
    ### 类型系统
    ```go
    // 基本类型
    var (
        b bool = true
        i int = 42
        f float64 = 3.14
        s string = "hello"
        r rune = '中' // Unicode码点
        by byte = 255 // uint8别名
    )
    
    // 复合类型
    type User struct {
        ID   int    `json:"id"`
        Name string `json:"name"`
    }
    
    // 接口类型
    type Writer interface {
        Write([]byte) (int, error)
    }
    
    // 函数类型
    type Handler func(http.ResponseWriter, *http.Request)
    
    // 通道类型
    var ch chan int = make(chan int, 10)
    ```
    
    ### 内存管理
    ```go
    // 栈分配 - 小对象，生命周期短
    func stackAllocation() {
        var x int = 42 // 分配在栈上
        fmt.Println(x)
    }
    
    // 堆分配 - 大对象，逃逸分析
    func heapAllocation() *int {
        x := 42
        return &x // x逃逸到堆上
    }
    
    // 内存池模式
    var bufferPool = sync.Pool{
        New: func() interface{} {
            return make([]byte, 1024)
        },
    }
    
    func useBuffer() {
        buf := bufferPool.Get().([]byte)
        defer bufferPool.Put(buf)
        // 使用buf
    }
    ```
  </section>
  
  <section title="并发编程">
    ## Goroutine和Channel
    
    ### Goroutine模式
    ```go
    // 基本goroutine
    go func() {
        fmt.Println("Hello from goroutine")
    }()
    
    // Worker Pool模式
    func workerPool(jobs <-chan Job, results chan<- Result) {
        for j := range jobs {
            results <- process(j)
        }
    }
    
    // Fan-out/Fan-in模式
    func fanOut(input <-chan int) (<-chan int, <-chan int) {
        out1 := make(chan int)
        out2 := make(chan int)
        
        go func() {
            defer close(out1)
            defer close(out2)
            for val := range input {
                out1 <- val
                out2 <- val
            }
        }()
        
        return out1, out2
    }
    ```
    
    ### 同步原语
    ```go
    // Mutex - 互斥锁
    type SafeCounter struct {
        mu    sync.Mutex
        value int
    }
    
    func (c *SafeCounter) Inc() {
        c.mu.Lock()
        defer c.mu.Unlock()
        c.value++
    }
    
    // RWMutex - 读写锁
    type SafeMap struct {
        mu   sync.RWMutex
        data map[string]int
    }
    
    func (m *SafeMap) Get(key string) int {
        m.mu.RLock()
        defer m.mu.RUnlock()
        return m.data[key]
    }
    
    // WaitGroup - 等待组
    func processItems(items []Item) {
        var wg sync.WaitGroup
        
        for _, item := range items {
            wg.Add(1)
            go func(item Item) {
                defer wg.Done()
                process(item)
            }(item)
        }
        
        wg.Wait()
    }
    
    // Once - 单次执行
    var once sync.Once
    var instance *Singleton
    
    func GetInstance() *Singleton {
        once.Do(func() {
            instance = &Singleton{}
        })
        return instance
    }
    ```
    
    ### Context模式
    ```go
    // 超时控制
    func doWork(ctx context.Context) error {
        ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
        defer cancel()
        
        select {
        case <-time.After(10 * time.Second):
            return errors.New("work took too long")
        case <-ctx.Done():
            return ctx.Err()
        }
    }
    
    // 值传递
    type key string
    const userKey key = "user"
    
    func withUser(ctx context.Context, user *User) context.Context {
        return context.WithValue(ctx, userKey, user)
    }
    
    func getUser(ctx context.Context) *User {
        if user, ok := ctx.Value(userKey).(*User); ok {
            return user
        }
        return nil
    }
    ```
  </section>
  
  <section title="错误处理">
    ## 错误处理模式
    
    ### 基本错误处理
    ```go
    // 自定义错误类型
    type ValidationError struct {
        Field   string
        Message string
    }
    
    func (e *ValidationError) Error() string {
        return fmt.Sprintf("validation failed for %s: %s", e.Field, e.Message)
    }
    
    // 错误包装
    func processFile(filename string) error {
        file, err := os.Open(filename)
        if err != nil {
            return fmt.Errorf("failed to open file %s: %w", filename, err)
        }
        defer file.Close()
        
        // 处理文件
        return nil
    }
    
    // 错误检查
    func handleError(err error) {
        var validationErr *ValidationError
        if errors.As(err, &validationErr) {
            log.Printf("Validation error: %s", validationErr.Message)
        } else if errors.Is(err, os.ErrNotExist) {
            log.Printf("File not found")
        } else {
            log.Printf("Unknown error: %v", err)
        }
    }
    ```
    
    ### Panic和Recover
    ```go
    // 安全的panic恢复
    func safeExecute(fn func()) (err error) {
        defer func() {
            if r := recover(); r != nil {
                err = fmt.Errorf("panic recovered: %v", r)
            }
        }()
        
        fn()
        return nil
    }
    
    // HTTP中间件错误恢复
    func recoverMiddleware(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
            defer func() {
                if err := recover(); err != nil {
                    log.Printf("Panic: %v", err)
                    http.Error(w, "Internal Server Error", 500)
                }
            }()
            next.ServeHTTP(w, r)
        })
    }
    ```
  </section>
  
  <section title="标准库">
    ## 核心包
    
    ### fmt包
    ```go
    // 格式化输出
    fmt.Printf("Name: %s, Age: %d\n", name, age)
    fmt.Sprintf("User: %+v", user) // 结构体详细输出
    fmt.Errorf("error occurred: %w", originalErr)
    
    // 自定义格式化
    type Point struct{ X, Y int }
    
    func (p Point) String() string {
        return fmt.Sprintf("(%d,%d)", p.X, p.Y)
    }
    ```
    
    ### io包
    ```go
    // 基本接口
    type Reader interface {
        Read([]byte) (int, error)
    }
    
    type Writer interface {
        Write([]byte) (int, error)
    }
    
    // 实用函数
    func copyData(dst io.Writer, src io.Reader) error {
        _, err := io.Copy(dst, src)
        return err
    }
    
    // 管道
    func pipeExample() {
        r, w := io.Pipe()
        
        go func() {
            defer w.Close()
            fmt.Fprint(w, "Hello, pipe!")
        }()
        
        data, _ := io.ReadAll(r)
        fmt.Println(string(data))
    }
    ```
    
    ### net/http包
    ```go
    // HTTP服务器
    func startServer() {
        mux := http.NewServeMux()
        mux.HandleFunc("/api/users", handleUsers)
        
        server := &http.Server{
            Addr:         ":8080",
            Handler:      mux,
            ReadTimeout:  15 * time.Second,
            WriteTimeout: 15 * time.Second,
        }
        
        log.Fatal(server.ListenAndServe())
    }
    
    // HTTP客户端
    func makeRequest(url string) (*http.Response, error) {
        client := &http.Client{
            Timeout: 30 * time.Second,
        }
        
        req, err := http.NewRequest("GET", url, nil)
        if err != nil {
            return nil, err
        }
        
        req.Header.Set("User-Agent", "MyApp/1.0")
        return client.Do(req)
    }
    ```
    
    ### encoding/json包
    ```go
    // JSON序列化
    type User struct {
        ID       int       `json:"id"`
        Name     string    `json:"name"`
        Email    string    `json:"email,omitempty"`
        Created  time.Time `json:"created"`
        Password string    `json:"-"` // 忽略字段
    }
    
    func (u User) MarshalJSON() ([]byte, error) {
        type Alias User
        return json.Marshal(&struct {
            *Alias
            Created string `json:"created"`
        }{
            Alias:   (*Alias)(&u),
            Created: u.Created.Format(time.RFC3339),
        })
    }
    ```
  </section>
  
  <section title="性能优化">
    ## 性能最佳实践
    
    ### 内存优化
    ```go
    // 预分配切片
    func processItems(items []Item) []Result {
        results := make([]Result, 0, len(items)) // 预分配容量
        for _, item := range items {
            results = append(results, process(item))
        }
        return results
    }
    
    // 字符串构建
    func buildString(parts []string) string {
        var builder strings.Builder
        builder.Grow(estimateSize(parts)) // 预分配
        
        for _, part := range parts {
            builder.WriteString(part)
        }
        return builder.String()
    }
    
    // 避免不必要的分配
    func processBytes(data []byte) {
        // 好：重用切片
        for i := range data {
            data[i] = transform(data[i])
        }
        
        // 坏：创建新切片
        // result := make([]byte, len(data))
        // for i, b := range data {
        //     result[i] = transform(b)
        // }
    }
    ```
    
    ### 并发优化
    ```go
    // 限制goroutine数量
    func processWithLimit(items []Item, limit int) {
        sem := make(chan struct{}, limit)
        var wg sync.WaitGroup
        
        for _, item := range items {
            wg.Add(1)
            go func(item Item) {
                defer wg.Done()
                sem <- struct{}{} // 获取信号量
                defer func() { <-sem }() // 释放信号量
                
                process(item)
            }(item)
        }
        
        wg.Wait()
    }
    
    // CPU密集型任务
    func parallelProcess(data []int) []int {
        numWorkers := runtime.NumCPU()
        chunkSize := len(data) / numWorkers
        
        var wg sync.WaitGroup
        results := make([]int, len(data))
        
        for i := 0; i < numWorkers; i++ {
            wg.Add(1)
            go func(start, end int) {
                defer wg.Done()
                for j := start; j < end; j++ {
                    results[j] = expensiveOperation(data[j])
                }
            }(i*chunkSize, (i+1)*chunkSize)
        }
        
        wg.Wait()
        return results
    }
    ```
  </section>
  
  <section title="设计模式">
    ## Go语言设计模式
    
    ### 单例模式
    ```go
    type Database struct {
        conn *sql.DB
    }
    
    var (
        db   *Database
        once sync.Once
    )
    
    func GetDatabase() *Database {
        once.Do(func() {
            db = &Database{
                conn: initConnection(),
            }
        })
        return db
    }
    ```
    
    ### 工厂模式
    ```go
    type Logger interface {
        Log(message string)
    }
    
    type FileLogger struct{ file *os.File }
    type ConsoleLogger struct{}
    
    func NewLogger(logType string) Logger {
        switch logType {
        case "file":
            return &FileLogger{file: openLogFile()}
        case "console":
            return &ConsoleLogger{}
        default:
            return &ConsoleLogger{}
        }
    }
    ```
    
    ### 装饰器模式
    ```go
    type Handler func(http.ResponseWriter, *http.Request)
    
    func withLogging(h Handler) Handler {
        return func(w http.ResponseWriter, r *http.Request) {
            start := time.Now()
            h(w, r)
            log.Printf("%s %s %v", r.Method, r.URL.Path, time.Since(start))
        }
    }
    
    func withAuth(h Handler) Handler {
        return func(w http.ResponseWriter, r *http.Request) {
            if !isAuthenticated(r) {
                http.Error(w, "Unauthorized", 401)
                return
            }
            h(w, r)
        }
    }
    ```
    
    ### 观察者模式
    ```go
    type Event struct {
        Type string
        Data interface{}
    }
    
    type Observer interface {
        Notify(event Event)
    }
    
    type EventBus struct {
        observers map[string][]Observer
        mu        sync.RWMutex
    }
    
    func (eb *EventBus) Subscribe(eventType string, observer Observer) {
        eb.mu.Lock()
        defer eb.mu.Unlock()
        eb.observers[eventType] = append(eb.observers[eventType], observer)
    }
    
    func (eb *EventBus) Publish(event Event) {
        eb.mu.RLock()
        observers := eb.observers[event.Type]
        eb.mu.RUnlock()
        
        for _, observer := range observers {
            go observer.Notify(event)
        }
    }
    ```
  </section>
</knowledge>