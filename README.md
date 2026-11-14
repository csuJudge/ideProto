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
- ide_run.status 是 WebIDE 专用口径（0 排队…8 执行异常），**不复用** solution 的 result 码（那套 4=AC）。
- 所有 Rsp 带 message + code，由网关转换成平台统一的 10000 成功码。