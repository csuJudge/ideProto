# ideProto

WebIDE（在线 IDE）的 tRPC 契约仓库。与 judgeProto 完全独立，互不引用。

消费方：oj_ide_svr（实现）、oj_gateway_svr（调用）。

## 服务划分

| service | 职责 | 为什么单独成一个 service |
|---|---|---|
| IDEServer | 项目与文件的增删改查、题目页导入查询 | 纯 CRUD 无状态，容器不可用时依然可用，前端不能置灰它 |
| IDERunServer | 编译、运行、运行历史、运行时能力探测 | 依赖容器沙箱，Docker/镜像异常时整组降级 |
| IDEDebugServer | 交互式单步调试 | 会话有状态、绑定长驻容器与其中的 gdb/MI 进程，是唯一可能单独拆进程部署的一块 |

语言编码沿用平台既有口径：0=C，1=C++，2=Java，3=Python。

## 目录

    ide/ide.proto          契约源文件
    ide/ide.pb.go          protoc-gen-go 产物（入库）
    ide/ide.trpc.go        trpc-cmdline 产物（入库）
    ide/ide_mock.go        mockgen 产物（入库）
    gen.sh                 一键重新生成

生成产物入库，与 judgeProto / agentProto / javaProto 一致，消费方无需安装 protoc。

## 改完 .proto 之后

    ./gen.sh

脚本内容就是这两条命令，环境要求 protoc v5.29.3 + protoc-gen-go v1.36.11 + trpc-cmdline v1.0.9 + mockgen v0.6.0（与 agentProto 产物的生成版本一致）：

    trpc create --rpconly -p ide/ide.proto -d . -o ide --nogomod --mock=false -f
    GOWORK=off mockgen -destination=ide/ide_mock.go -package=ide \
      -self_package=github.com/csuJudge/ideProto/ide --source=ide/ide.trpc.go
    go build ./... && go vet ./...

只生成库桩，**不生成 server 脚手架**（脚手架带 replace 与嵌套 module，是 funcProblemProto 里 out/stub/ 那堆垃圾的来源）。

## 发版三步

1. 确认 gen.sh 跑完且 go build ./... 通过；
2. git commit 并 push 到 main（本仓库必须保持**公开**：部署机 github 直连不通，依赖国内 goproxy 代取，私有会拉不到）；
3. 打 tag 并推送：

       git tag v0.0.1 && git push origin v0.0.1

消费方升级：在它的 go.mod 里把 github.com/csuJudge/ideProto 改成新 tag，然后 go mod tidy。

## 兼容性约定

- 字段号只增不改不复用；删字段留 reserved。
- 枚举 0 值一律留给 Unspecified。
- `ide_run.status` **与平台 `solution.result` 同码**，前端 `genResult()`（`pljp_frontend/src/assets/js/tool/common.js:49`）可直接复用：
  `1` 排队中（`<2` 即待判）· `2` 正在编译 · `3` 判断中（本场景=运行中）· `4` 正确（仅编译模式=编译通过）· `7` 时间超限 · `8` 内存超限 · `9` 输出超限 · `10` 运行错误 · `11` 编译错误。
  `5 格式错误`/`6 答案错误` 不使用（需要标准输出对照）。码表出处除前端那份，还有 `judge-daemon` 二进制里的 `WHERE s.result < 2`。
  v0.0.1 曾自造一套 0…8，v0.0.2 起废弃——当时无调用方，故未做兼容。
- 所有 Rsp 带 message + code，由网关转换成平台统一的 10000 成功码。
- 职责边界：`IDEServer` 与 `IDERunServer` 由 oj_ide_svr 实现，**它只往库里插入与查询**；
  `ide_run` 的状态与输出由 ide_judge 守护进程 UPDATE 回填。`IDEDebugServer` 由 ide_judge 实现
  （会话绑容器绑 gdb 进程），svr 侧只做转发。一期调试仅 C/C++。

## 变更记录

### v0.0.2

- 删除 `QueryRuntimeCapability` 及其 Req/Rsp：沙箱能力与工具链版本只有持有 Docker 的进程探得到，
  而 svr 不再碰 Docker。前端要显示的"沙箱可出网、禁校内网"等文案改由前端持有
- `status` 换成 `solution.result` 码表（见上）
- `StartDebugReq` 加 `input`：缺它被调试程序一 `scanf` 就死等
- 新增 `UpdateBreakpoints`：原来跑起来之后没有任何接口能改断点
- `DebugState` 加 `running`：Continue 之后"在跑还没停"这个状态原来表达不出来
- rpc 删除不留 reserved（proto3 的 reserved 只管字段号，服务方法名不存在复用问题）
