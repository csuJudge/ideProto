#!/usr/bin/env bash
#
# gen.sh — ideProto 一键重新生成（改完 .proto 后跑这个）
#
# 产出四件套里的三样桩 + mock：
#   ide/ide.pb.go  ide/ide.trpc.go  ide/ide_mock.go
# 供 oj_ide_svr 实现、oj_gateway_svr 调用。
#
# 用法：  ./gen.sh
#
# 说明：
#   - 只生成库桩，不生成 server 脚手架（脚手架是嵌套 module + replace，
#     funcProblemProto/objectiveProto 里 out/stub/ 的垃圾就是这么来的）。
#   - 每次 force 重新生成，可反复跑。

set -euo pipefail

MODULE="github.com/csuJudge/ideProto"
SVC="ide"
PROTO="ide/ide.proto"
GOBIN="${HOME}/go/bin"
TRPC="${GOBIN}/trpc"
MOCKGEN="${GOBIN}/mockgen"

command -v go >/dev/null 2>&1 || { echo "错误: PATH 里找不到 go"; exit 1; }
[ -x "${TRPC}" ]    || { echo "错误: 找不到 ${TRPC}"; exit 1; }
[ -x "${MOCKGEN}" ] || { echo "错误: 找不到 ${MOCKGEN}"; exit 1; }
[ -f "$(dirname "${BASH_SOURCE[0]}")/${PROTO}" ] || { echo "错误: 找不到 ${PROTO}"; exit 1; }

MOD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${MOD_ROOT}"

echo "==> [1/3] 生成桩 pb.go + trpc.go"
"${TRPC}" create --rpconly -p "${PROTO}" -d . -o "${SVC}" --nogomod --mock=false -f

PKG="$(awk '/^package /{print $2; exit}' "${SVC}/${SVC}.trpc.go")"
[ -n "${PKG}" ] || { echo "错误: 读不到 package 名（${SVC}/${SVC}.trpc.go）"; exit 1; }
echo "     package = ${PKG}"

echo "==> [2/3] 生成 mock"
GOWORK=off "${MOCKGEN}" \
  -destination="${SVC}/${SVC}_mock.go" \
  -package="${PKG}" \
  -self_package="${MODULE}/${SVC}" \
  --source="${SVC}/${SVC}.trpc.go"

echo "==> [3/3] 校验 (go build / go vet)"
GOWORK=off go mod tidy
GOWORK=off go build ./...
GOWORK=off go vet ./...

echo
echo "全部完成 ✅  产物在 ${MOD_ROOT}/${SVC}/"
echo "  下一步：git diff 确认改动范围，commit，push，打 tag"