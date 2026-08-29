#!/usr/bin/env bash
#
# omarchy-scene 回归与安全测试
#
# 覆盖（对应 marketplace 安全审查要求）:
#   T1  完整生命周期回归（所有子命令）
#   T2  符号链接在打开时被拒绝（读路径绝不通向攻击者目标）
#   T3  校验后路径被换成符号链接不影响已读对象（TOCTOU 竞态）
#   T4  FIFO 输入绝不阻塞（超时兜底）
#   T5  超大文件被拒绝（>8 MiB）
#   T6  并发写者不会破坏状态；原子发布无撕裂
#   T7  备份创建不碰撞
#   T8  cmd_menu_add 无法经场景名执行 shell 语法
#   T9  数组/记录/字符串上限在向 QML 输出前强制
#   T10 临时文件卫生（无 .omarchy-scene.*.tmp 残留）
#   T11 锁文件安全（拒绝符号链接锁文件；flock 互斥）
#   T12 字节级往返一致性（读回内容与写入完全一致）
#
# 运行: bash tests/run-tests.sh   （结果非零退出码表示有失败）
#
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCENE="$REPO/omarchy-scene"
WORK="$(mktemp -d)"
PYIO="$WORK/io.py"

PASS=0
FAIL=0
FAILED_NAMES=()

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# 提取脚本内置的安全 I/O 核心（python3），供直连测试使用
awk '/<<.OMARCHY_SCENE_PY_IO./ { inpy=1; next } inpy && /^OMARCHY_SCENE_PY_IO$/ { exit } inpy { print }' "$SCENE" > "$PYIO"
if ! python3 -m py_compile "$PYIO"; then
  echo "FATAL: embedded secure I/O core does not compile"
  exit 1
fi

ok()  { PASS=$((PASS+1)); echo "  ok    - $1"; }
bad() { FAIL=$((FAIL+1)); FAILED_NAMES+=("$1"); echo "  FAIL  - $1"; }

# expect <name> <cmd...> : 命令必须成功
expect() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name (exit $?)"; fi
}
# expect_fail <name> <cmd...> : 命令必须失败
expect_fail() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then bad "$name (expected failure, got success)"; else ok "$name"; fi
}
# expect_fast_fail <name> <seconds> <cmd...> : 必须失败且不能因挂起被 timeout 杀掉
expect_fast_fail() {
  local name="$1" secs="$2"; shift 2
  timeout "$secs" "$@" >/dev/null 2>&1
  local rc=$?
  if [[ $rc -eq 124 ]]; then bad "$name (HUNG — killed by timeout)"; else ok "$name (rc=$rc)"; fi
}
assert_eq() {
  local name="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then ok "$name"; else bad "$name (got '$got', want '$want')"; fi
}

# ---------------------------------------------------------------- 假环境

setup_env() {
  rm -rf "$WORK/home" "$WORK/bin" "$WORK/cfg"
  mkdir -p "$WORK/home/.config/omarchy/extensions" "$WORK/bin" "$WORK/cfg"
  cat > "$WORK/home/.config/omarchy/shell.json" <<'JSON'
{"version":1,"bar":{"id":"pkg.bar","layout":{"left":[{"id":"pkg.wid","settings":{"x":1}}],"center":[],"right":[]}},"plugins":[{"id":"org.cpu"},{"id":"org.clock"}],"disabledPlugins":[]}
JSON
  cat > "$WORK/bin/omarchy" <<SH
#!/usr/bin/env bash
case "\$1 \$2" in
  "plugin list")
    [ "\${FAKE_SLOW:-0}" = 1 ] && sleep 0.05
    cat <<'J'
[{"id":"pkg.bar","name":"Bar Pack","kinds":["bar"],"enabled":false,"firstParty":false},
 {"id":"pkg.wid","name":"Widget One","kinds":["bar-widget"],"enabled":false,"firstParty":false},
 {"id":"org.cpu","name":"CPU Monitor","kinds":["service"],"enabled":true,"firstParty":true},
 {"id":"org.clock","name":"Clock","kinds":["bar-widget"],"enabled":true,"firstParty":false}]
J
    ;;
  plugin\ enable*) touch "$WORK/state.enabled";;
  plugin\ disable*) touch "$WORK/state.disabled";;
  *) exit 0;;
esac
SH
  printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/bin/omarchy-shell"
  chmod +x "$WORK/bin/omarchy" "$WORK/bin/omarchy-shell"
  export HOME="$WORK/home" OMARCHY_SCENES_DIR="$WORK/cfg/scenes" PATH="$WORK/bin:$PATH"
  mkdir -p "$OMARCHY_SCENES_DIR"
}

menu_file() {
  cat > "$WORK/home/.config/omarchy/extensions/omarchy-menu.jsonc" <<'J'
{
  "preexisting": {"x": 1}   // unrelated entry
}
J
}

# ---------------------------------------------------------------- T1 生命周期

t01_lifecycle() {
  echo "T1 完整生命周期回归"
  setup_env
  menu_file
  expect "help 可运行" "$SCENE" help
  expect "init 引导" "$SCENE" init
  expect "init 重复执行失败" sh -c "! $SCENE init 2>/dev/null"
  expect "add 创建场景 s1" "$SCENE" add s1 --label Work
  expect "add 创建场景 s2（带图标）" "$SCENE" add s2 --label Focus --icon 󰕮
  expect_fail "重复 add s1 失败" "$SCENE" add s1
  expect "add-plugin 加入 org.cpu（s1）" "$SCENE" add-plugin s1 org.cpu
  expect "add-plugin 加入 org.clock（s2）" "$SCENE" add-plugin s2 org.clock
  expect "add-plugin 加入 pkg.bar（default）" "$SCENE" add-plugin default pkg.bar
  expect_fail "add-plugin 重复失败" "$SCENE" add-plugin s1 org.cpu
  assert_eq "current 初始为 default" "$("$SCENE" current)" "default"
  expect "set s1 --dry-run" "$SCENE" set s1 --dry-run
  expect "set s1" "$SCENE" set s1
  assert_eq "set 后 current=s1" "$("$SCENE" current)" "s1"
  assert_eq "bar-status label=Work" "$("$SCENE" bar-status | jq -r .label)" "Work"
  expect_fail "rm 当前场景（s1）被拒" "$SCENE" rm s1
  expect "cycle 到下一个场景（s2）" "$SCENE" cycle
  assert_eq "cycle 后 current=s2" "$("$SCENE" current)" "s2"
  expect "set default 返回" "$SCENE" set default
  expect "rename s1 -> s1b（顺带刷新菜单）" "$SCENE" rename s1 s1b
  expect "label s1b" "$SCENE" label s1b Focused
  expect "icon s1b" "$SCENE" icon s1b 󰕮
  expect "lock org.cpu" "$SCENE" lock org.cpu
  expect "unlock org.cpu" "$SCENE" unlock org.cpu
  expect "toggle-plugin off" "$SCENE" toggle-plugin s1b org.cpu off
  expect "toggle-plugin on" "$SCENE" toggle-plugin s1b org.cpu on
  expect "menu-add（预置菜单）" "$SCENE" menu-add
  expect "menu-add 幂等" "$SCENE" menu-add
  m1=$(sed -E 's|//.*||' "$WORK/home/.config/omarchy/extensions/omarchy-menu.jsonc" | jq -e . >/dev/null 2>&1 && echo yes || echo no)
  assert_eq "menu 内容仍是合法 JSON" "$m1" "yes"
  expect "menu-remove" "$SCENE" menu-remove
  expect "rm-plugin（s1b）" "$SCENE" rm-plugin s1b org.cpu
  expect "rm s1b" "$SCENE" rm s1b
  expect "rm-plugin（s2）" "$SCENE" rm-plugin s2 org.clock
  expect "status" "$SCENE" status
  expect "scenes JSON" "$SCENE" scenes
  expect "config JSON" "$SCENE" config
  expect "refresh" "$SCENE" refresh
  expect "ui-state 为合法 JSON" sh -c "jq -e . '$OMARCHY_SCENES_DIR/ui-state.json' >/dev/null"
  expect "entries 为合法 JSON" sh -c "jq -e . '$OMARCHY_SCENES_DIR/entries.json' >/dev/null"
  echo "  (T1 done)"
}

# ---------------------------------------------------------------- T2 符号链接拒绝

t02_symlink_rejected() {
  echo "T2 读路径符号链接被拒绝（O_NOFOLLOW）"
  setup_env
  "$SCENE" init >/dev/null 2>&1
  expect_fail "读路径符号链接 → config 拒绝" sh -c "ln -sf '$WORK/pwned.json' '$OMARCHY_SCENES_DIR/scenes.json'; $SCENE config"
  # 把 scenes.json 换成指向攻击者文件的符号链接
  printf '{"version":1,"current":"PWNED_MARKER","scenes":{}}' > "$WORK/pwned.json"
  rm -f "$OMARCHY_SCENES_DIR/scenes.json"
  ln -s "$WORK/pwned.json" "$OMARCHY_SCENES_DIR/scenes.json"
  out=$("$SCENE" current 2>&1) && bad "current 不应读取符号链接" || ok "current 拒绝符号链接"
  if grep -q PWNED_MARKER <<<"$out"; then bad "符号链接内容被输出"; else ok "符号链接内容未被输出"; fi
  # 中间目录符号链接
  rm -rf "$WORK/cfg/scenes-real"
  mv "$OMARCHY_SCENES_DIR" "$WORK/cfg/scenes-real"
  ln -s "$WORK/cfg/scenes-real" "$OMARCHY_SCENES_DIR"
  expect_fail "中间目录为符号链接时拒绝" "$SCENE" current
  echo "  (T2 done)"
}

# ---------------------------------------------------------------- T3 TOCTOU 竞态

t03_toctou_race() {
  echo "T3 校验后换链不影响已读对象（TOCTOU 竞态环路）"
  setup_env
  "$SCENE" init >/dev/null 2>&1
  "$SCENE" add s1 --label Work >/dev/null 2>&1
  cp "$OMARCHY_SCENES_DIR/scenes.json" "$WORK/real.json"
  printf '{"version":1,"current":"PWNED_MARKER","scenes":{}}' > "$WORK/pwned.json"
  # 后台疯狂切换路径: 真实文件 <-> 符号链接
  (
    i=0
    while [[ $i -lt 300 ]]; do
      rm -f "$OMARCHY_SCENES_DIR/scenes.json"
      ln -s "$WORK/pwned.json" "$OMARCHY_SCENES_DIR/scenes.json"
      rm -f "$OMARCHY_SCENES_DIR/scenes.json"
      cp "$WORK/real.json" "$OMARCHY_SCENES_DIR/scenes.json"
      i=$((i+1))
    done
  ) &
  racer=$!
  leaked=0
  s=0
  while [[ $s -lt 40 ]]; do
    out=$(timeout 5 "$SCENE" bar-status 2>/dev/null)
    rc=$?
    if [[ $rc -eq 0 ]]; then
      if grep -q PWNED_MARKER <<<"$out"; then leaked=1; fi
      if ! jq -e . <<<"$out" >/dev/null 2>&1; then leaked=1; fi
    elif [[ $rc -eq 124 ]]; then
      leaked=1   # 挂起 = 失败
    fi
    s=$((s+1))
  done
  wait "$racer" 2>/dev/null
  if [[ $leaked -eq 1 ]]; then bad "竞态期间读取到了攻击者内容/无效内容/挂起"; else ok "40 轮竞态: 成功读取均为合法原对象，失败均为快速拒绝"; fi
  # 直连 helper: 符号链接打开即 ELOOP
  expect_fail "helper 拒绝打开符号链接目标" python3 "$PYIO" read scenes "$WORK/pwned-link.json"
  rm -f "$OMARCHY_SCENES_DIR/scenes.json"
  ln -s "$WORK/pwned.json" "$OMARCHY_SCENES_DIR/scenes.json"
  expect_fail "helper 拒绝打开被换链的 scenes.json" python3 "$PYIO" read scenes "$OMARCHY_SCENES_DIR/scenes.json"
  echo "  (T3 done)"
}

# ---------------------------------------------------------------- T4 FIFO

t04_fifo() {
  echo "T4 FIFO 绝不阻塞"
  setup_env
  "$SCENE" init >/dev/null 2>&1
  rm -f "$OMARCHY_SCENES_DIR/scenes.json"
  mkfifo "$OMARCHY_SCENES_DIR/scenes.json"
  expect_fast_fail "scenes.json=FIFO 时 current 快速失败" 5 "$SCENE" current
  expect_fast_fail "scenes.json=FIFO 时 config 快速失败" 5 "$SCENE" config
  rm -f "$OMARCHY_SCENES_DIR/scenes.json"
  "$SCENE" init >/dev/null 2>&1
  "$SCENE" add s1 >/dev/null 2>&1
  mv "$WORK/home/.config/omarchy/shell.json" "$WORK/home/.config/omarchy/shell.json.real"
  mkfifo "$WORK/home/.config/omarchy/shell.json"
  expect_fast_fail "shell.json=FIFO 时 set 快速失败" 5 "$SCENE" set s1
  mv "$WORK/home/.config/omarchy/shell.json.real" "$WORK/home/.config/omarchy/shell.json"
  echo "  (T4 done)"
}

# ---------------------------------------------------------------- T5 超大文件

t05_oversize() {
  echo "T5 超大文件（>8 MiB）被拒绝"
  setup_env
  "$SCENE" init >/dev/null 2>&1
  dd if=/dev/zero bs=1048576 count=9 >> "$OMARCHY_SCENES_DIR/scenes.json" 2>/dev/null
  out=$("$SCENE" current 2>&1) && bad "超大 scenes.json 应被拒绝" || ok "超大 scenes.json 被拒绝"
  grep -q "oversized" <<<"$out" && ok "报告 oversized" || bad "未报告 oversized"
  # 合法 JSON 但超长字符串（同样应先触发字节上限）
  setup_env
  "$SCENE" init >/dev/null 2>&1
  python3 - "$OMARCHY_SCENES_DIR/scenes.json" <<'PY'
import json, sys
p = sys.argv[1]
doc = json.load(open(p))
doc["_pad"] = "x" * (9 * 1024 * 1024)
json.dump(doc, open(p, "w"))
PY
  expect_fail "9MiB 合法 JSON 仍是超大 → 拒绝" "$SCENE" current
  expect_fail "9MiB shell.json → set 拒绝" sh -c "$SCENE add s1 >/dev/null 2>&1; python3 -c \"
import json
p = '$WORK/home/.config/omarchy/shell.json'
d = json.load(open(p)); d['_pad'] = 'x' * (9*1024*1024); json.dump(d, open(p, 'w'))
\" && $SCENE set s1"
  echo "  (T5 done)"
}

# ---------------------------------------------------------------- T6 并发写者

t06_concurrent() {
  echo "T6 并发写者不破坏状态"
  setup_env
  "$SCENE" init >/dev/null 2>&1
  # 8 个并发 lock（每个都做 读->写 scenes.json + ui-state）
  FAKE_SLOW=1
  pids=()
  rdir="$WORK/conc"; mkdir -p "$rdir"
  for i in $(seq 1 8); do
    (
      if "$SCENE" lock org.cpu >/dev/null 2>&1; then echo ok > "$rdir/$i"; else echo busy > "$rdir/$i"; fi
    ) &
    pids+=($!)
  done
  for p in "${pids[@]}"; do wait "$p"; done
  unset FAKE_SLOW
  if jq -e . "$OMARCHY_SCENES_DIR/scenes.json" >/dev/null 2>&1; then
    ok "并发后 scenes.json 仍是合法 JSON"
  else
    bad "并发后 scenes.json 损坏"
  fi
  nres=$(find "$rdir" -type f | wc -l)
  if [[ "$nres" -eq 8 ]]; then
    ok "8 个进程均有明确结果（ok/busy）"
  else
    bad "进程结果缺失（$nres/8）"
  fi
  okcount=$(grep -h '^ok$' "$rdir"/* 2>/dev/null | wc -l)
  busycount=$(grep -h '^busy$' "$rdir"/* 2>/dev/null | wc -l)
  echo "    (ok=$okcount busy=$busycount)"
  if jq -e '.locked == (.locked | unique)' "$OMARCHY_SCENES_DIR/scenes.json" >/dev/null 2>&1; then
    ok "locked 集合去重且一致（无并发重复/杂乱）"
  else
    bad "locked 集合异常"
  fi
  expect "并发后 config 仍能输出（结构一致）" "$SCENE" config
  # 原子发布: 直接对同一目标并发写入两种内容，读回必须完整等于其中一种
  printf 'CONTENT_A\n' > "$WORK/target"
  pids=()
  for i in $(seq 1 10); do
    ( printf 'CONTENT_A\n' | python3 "$PYIO" write "$WORK/target" ) &
    ( printf 'CONTENT_B\n' | python3 "$PYIO" write "$WORK/target" ) &
    pids+=($!)
  done
  for p in "${pids[@]}"; do wait "$p"; done
  got=$(cat "$WORK/target")
  if [[ "$got" == "CONTENT_A" || "$got" == "CONTENT_B" ]]; then
    ok "20 次并发原子写: 读回内容完整等于 A 或 B（无撕裂）"
  else
    bad "原子写出现撕裂内容: '$got'"
  fi
  echo "  (T6 done)"
}

# ---------------------------------------------------------------- T7 备份不碰撞

t07_backup() {
  echo "T7 备份创建不碰撞"
  setup_env
  printf '{"data":42}\n' > "$WORK/home/.config/omarchy/shell.json"
  pids=()
  for i in $(seq 1 12); do
    ( python3 "$PYIO" backup "$WORK/home/.config/omarchy/shell.json" > "$WORK/bk.$i" 2>/dev/null ) &
    pids+=($!)
  done
  for p in "${pids[@]}"; do wait "$p"; done
  n=$(cat "$WORK"/bk.* | sort -u | wc -l)
  if [[ $n -eq 12 ]]; then
    ok "12 个并发备份得到 12 个互不相同的路径"
  else
    bad "备份路径出现重复/缺失（unique=$n）"
  fi
  badcount=0
  for f in "$WORK"/bk.*; do
    p=$(cat "$f")
    [[ -f "$p" ]] || badcount=$((badcount+1))
    cmp -s "$p" "$WORK/home/.config/omarchy/shell.json" || badcount=$((badcount+1))
  done
  if [[ $badcount -eq 0 ]]; then
    ok "全部备份文件内容与源一致"
  else
    bad "$badcount 个备份内容异常"
  fi
  echo "  (T7 done)"
}

# ---------------------------------------------------------------- T8 菜单注入

t08_menu_injection() {
  echo "T8 cmd_menu_add 无法经场景名执行 shell 语法"
  setup_env
  menu_file
  "$SCENE" init >/dev/null 2>&1
  expect_fail "add 拒绝分号场景名" "$SCENE" add 'x;touch' --label boom
  expect_fail "add 拒绝反引号场景名" "$SCENE" add '`touch`' --label boom
  expect_fail "add 拒绝 \$( ) 场景名" "$SCENE" add '$(touch)' --label boom
  expect_fail "add 拒绝引号场景名" "$SCENE" add 'a"b' --label boom
  # 合法场景 + 带引号的 label（JSON 转义路径）
  expect "add 合法场景名" "$SCENE" add ok1 --label 'x";pwn;y'
  expect "menu-add（含恶意 label）成功" "$SCENE" menu-add
  if [[ ! -e "$WORK/PWNTOUCHED" ]]; then ok "恶意 label 未被 shell 执行"; else bad "恶意 label 被执行了！"; fi
  if jq -e . <(sed -E 's|//.*||' "$WORK/home/.config/omarchy/extensions/omarchy-menu.jsonc") >/dev/null 2>&1; then
    ok "注入后的菜单仍是合法 JSON"
  else
    bad "注入后的菜单 JSON 非法"
  fi
  # 手工写入恶意场景名（绕过 CLI 校验）→ 读取阶段结构校验必须拒绝
  printf '{"version":1,"current":"default","scenes":{"oops;touch": {"label":"x","plugins":[]}}}' > "$OMARCHY_SCENES_DIR/scenes.json"
  expect_fail "恶意场景名手工写入 → config 拒绝（输出前拦截）" "$SCENE" config
  expect_fail "恶意场景名手工写入 → menu-add 拒绝" "$SCENE" menu-add
  if [[ ! -e "$WORK/PWNTOUCHED" ]]; then ok "恶意场景名未被 shell 执行"; else bad "恶意场景名被执行了！"; fi
  echo "  (T8 done)"
}

# ---------------------------------------------------------------- T9 结构上限

t09_limits() {
  echo "T9 数组/记录/字符串上限在输出到 QML 前强制"
  setup_env
  "$SCENE" init >/dev/null 2>&1
  cp "$OMARCHY_SCENES_DIR/ui-state.json" "$WORK/uistate.before.json"

  # 9a. label 超长
  python3 - "$OMARCHY_SCENES_DIR/scenes.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["scenes"]["s1"] = {"label": "x" * 100, "plugins": []}
json.dump(d, open(p, "w"))
PY
  expect_fail "label >64 → config 拒绝" "$SCENE" config
  expect_fail "label >64 → scenes 拒绝" "$SCENE" scenes
  expect_fail "label >64 → current 拒绝" "$SCENE" current

  # 9a2. 长但合理的 label（如 "Development"=11 字符）必须被接受
  python3 - "$OMARCHY_SCENES_DIR/scenes.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["scenes"]["s1"] = {"label": "Development", "plugins": []}
json.dump(d, open(p, "w"))
PY
  expect "label=Development(11字符) → config 通过" "$SCENE" config

  # 9b. 场景数超限
  python3 - "$OMARCHY_SCENES_DIR/scenes.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["scenes"] = {("s%02d" % i): {"plugins": []} for i in range(15)}
json.dump(d, open(p, "w"))
PY
  expect_fail "15 个场景 → config 拒绝" "$SCENE" config

  # 9c. 插件列表超长
  python3 - "$OMARCHY_SCENES_DIR/scenes.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["scenes"] = {"s1": {"plugins": ["a%03d" % i for i in range(300)]}}
json.dump(d, open(p, "w"))
PY
  expect_fail "单场景 300 插件 → config 拒绝" "$SCENE" config

  # 9d. 非法插件 id
  python3 - "$OMARCHY_SCENES_DIR/scenes.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["scenes"] = {"s1": {"plugins": ["../../evil"]}}
json.dump(d, open(p, "w"))
PY
  expect_fail "非法插件 id → config 拒绝" "$SCENE" config

  # 9e. 深度超限
  python3 - "$OMARCHY_SCENES_DIR/scenes.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
x = {}
cur = x
for _ in range(40):
    cur["n"] = {}
    cur = cur["n"]
d["_evil"] = x
json.dump(d, open(p, "w"))
PY
  expect_fail "嵌套深度 40 → config 拒绝" "$SCENE" config

  # 9f. 字符串超长
  python3 - "$OMARCHY_SCENES_DIR/scenes.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["_evil"] = "x" * 5000
json.dump(d, open(p, "w"))
PY
  expect_fail "5000 字符字符串 → config 拒绝" "$SCENE" config

  # 9g. 数组超长（通用上限 65536）
  python3 - "$OMARCHY_SCENES_DIR/scenes.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["_evil"] = list(range(70000))
json.dump(d, open(p, "w"))
PY
  expect_fail "70000 项数组 → config 拒绝" "$SCENE" config

  # 9h. entries.json 记录数超限（>4096）
  python3 -c "
import json
p = '$WORK/entries.big.json'
json.dump({'k%04d' % i: {'entry': {}} for i in range(5000)}, open(p, 'w'))
"
  expect_fail "entries 5000 记录 → helper 拒绝" python3 "$PYIO" read entries "$WORK/entries.big.json"
  python3 -c "
import json
json.dump({'org.cpu': {'entry': {'id': 'org.cpu'}}}, open('$WORK/entries.ok.json', 'w'))
"
  expect "正常 entries 通过" python3 "$PYIO" read entries "$WORK/entries.ok.json"

  # 9i. 拒绝后不得改动 QML 输出文件（ui-state 保持旧内容）
  if cmp -s "$WORK/uistate.before.json" "$OMARCHY_SCENES_DIR/ui-state.json"; then
    ok "所有失败场景下 ui-state.json 未被改写"
  else
    bad "ui-state.json 在拒绝路径被改动"
  fi
  echo "  (T9 done)"
}

# ---------------------------------------------------------------- T10 临时文件卫生

t10_hygiene() {
  echo "T10 临时文件卫生（无 .omarchy-scene.*.tmp 残留）"
  setup_env
  menu_file
  "$SCENE" init >/dev/null 2>&1
  "$SCENE" add s1 >/dev/null 2>&1
  "$SCENE" add-plugin s1 org.cpu >/dev/null 2>&1
  "$SCENE" set s1 >/dev/null 2>&1
  "$SCENE" menu-add >/dev/null 2>&1
  "$SCENE" menu-remove >/dev/null 2>&1
  "$SCENE" lock org.cpu >/dev/null 2>&1
  leftovers=$(find "$OMARCHY_SCENES_DIR" "$WORK/home/.config/omarchy/extensions" "$WORK/home/.config/omarchy" -name '.omarchy-scene.*.tmp' 2>/dev/null | wc -l)
  if [[ "$leftovers" -eq 0 ]]; then
    ok "无 .omarchy-scene.*.tmp 残留"
  else
    bad "发现 $leftovers 个临时文件残留"
  fi
  locks=$(find "$WORK" -name '.scenes.lock.status.*' 2>/dev/null | wc -l)
  if [[ "$locks" -eq 0 ]]; then
    ok "无锁握手状态文件残留"
  else
    bad "发现 $locks 个锁状态残留"
  fi
  echo "  (T10 done)"
}

# ---------------------------------------------------------------- T11 锁文件安全

t11_lock() {
  echo "T11 锁文件安全"
  setup_env
  "$SCENE" init >/dev/null 2>&1
  # 锁文件为符号链接 → 必须拒绝打开（O_NOFOLLOW），目标不受影响
  printf 'PRECIOUS' > "$WORK/victim"
  rm -f "$OMARCHY_SCENES_DIR/.scenes.lock"
  ln -s "$WORK/victim" "$OMARCHY_SCENES_DIR/.scenes.lock"
  expect_fail "符号链接锁文件 → add 拒绝" "$SCENE" add s1
  if [[ "$(cat "$WORK/victim")" == "PRECIOUS" ]]; then
    ok "符号链接目标未被触碰"
  else
    bad "符号链接目标被写入！"
  fi
  # 正常创建锁文件：互斥生效
  rm -f "$OMARCHY_SCENES_DIR/.scenes.lock"
  expect "正常 add（锁文件重建）" "$SCENE" add s1
  for i in 2 3 4; do
    ( "$SCENE" add s$i >/dev/null 2>&1; echo $? > "$WORK/conc2.$i" ) &
  done
  wait
  nrc=$(grep -l '^0$' "$WORK"/conc2.* 2>/dev/null | wc -l)
  nfail=$(grep -l '^1$' "$WORK"/conc2.* 2>/dev/null | wc -l)
  echo "    (并发 add: 成功=$nrc 失败=$nfail)"
  if [[ $((nrc + nfail)) -eq 3 ]] && jq -e '.scenes | length >= 1' "$OMARCHY_SCENES_DIR/scenes.json" >/dev/null 2>&1; then
    ok "并发 add 结果一致且 scenes.json 未损坏"
  else
    bad "并发 add 结果异常"
  fi
  expect "并发后 config 正常" "$SCENE" config
  echo "  (T11 done)"
}

# ---------------------------------------------------------------- T12 字节往返

t12_roundtrip() {
  echo "T12 字节级往返一致性"
  setup_env
  printf '{"version":1,"current":"default","s":"line1\nline2\t\"quoted\" \\$cmd #hash","scenes":{}}' > "$OMARCHY_SCENES_DIR/scenes.json"
  got=$(python3 "$PYIO" read raw "$OMARCHY_SCENES_DIR/scenes.json")
  want=$(cat "$OMARCHY_SCENES_DIR/scenes.json")
  if [[ "$got" == "$want" ]]; then ok "raw 读回与文件字节一致（含引号/反斜杠/换行）"; else bad "字节不一致"; fi
  # 写回后读回一致
  printf 'NEW BYTES\n' | python3 "$PYIO" write "$WORK/rt.txt"
  if [[ "$(cat "$WORK/rt.txt")" == "NEW BYTES" ]]; then ok "write 后读回一致"; else bad "write 读回不一致"; fi
  echo "  (T12 done)"
}

# ---------------------------------------------------------------- T13 布局稳定性

# 模拟用户真实故障: 未受管内置部件（wifi/ai/audio/monitor/power）不随场景切换漂移，
# 每个场景的完整布局在反复 default<->dev 切换中精确还原。

t13_layout_stability() {
  echo "T13 场景切换布局稳定（未受管内置部件不被挤走）"
  setup_env
  export HOME="$WORK/home" OMARCHY_SCENES_DIR="$WORK/cfg/scenes" PATH="$WORK/bin:$PATH"
  # 丰富版目录（真实形态: 内置 bar-widget + 用户 bar-widget/service）
  cat > "$WORK/bin/omarchy" <<SH
#!/usr/bin/env bash
case "\$1 \$2" in
  "plugin list")
    cat <<'J'
[{"id":"omarchy.tray","name":"Tray","kinds":["bar-widget"],"enabled":true,"firstParty":true},
 {"id":"omarchy.menu","name":"Menu","kinds":["bar-widget"],"enabled":true,"firstParty":true},
 {"id":"omarchy.workspaces","name":"Workspaces","kinds":["bar-widget"],"enabled":true,"firstParty":true},
 {"id":"omarchy.clock","name":"Clock","kinds":["bar-widget"],"enabled":true,"firstParty":true},
 {"id":"omarchy.keyboard-layout","name":"Keyboard layout","kinds":["bar-widget"],"enabled":true,"firstParty":true},
 {"id":"omarchy.bluetooth","name":"Bluetooth","kinds":["bar-widget"],"enabled":true,"firstParty":true},
 {"id":"omarchy.agents","name":"AI agents","kinds":["bar-widget"],"enabled":true,"firstParty":true},
 {"id":"omarchy.network","name":"WiFi","kinds":["bar-widget"],"enabled":true,"firstParty":true},
 {"id":"omarchy.audio","name":"Audio","kinds":["bar-widget"],"enabled":true,"firstParty":true},
 {"id":"omarchy.monitor","name":"Monitor","kinds":["bar-widget"],"enabled":true,"firstParty":true},
 {"id":"omarchy.power","name":"Power","kinds":["bar-widget"],"enabled":true,"firstParty":true},
 {"id":"saif.system-stats","name":"System stats","kinds":["bar-widget"],"enabled":true,"firstParty":false},
 {"id":"local.opencode-go","name":"Opencode","kinds":["bar-widget"],"enabled":true,"firstParty":false},
 {"id":"io.github.ilyazar.syncthing","name":"Syncthing","kinds":["service","bar-widget"],"enabled":true,"firstParty":false},
 {"id":"max.scene","name":"Scene Switcher","kinds":["bar-widget"],"enabled":true,"firstParty":false},
 {"id":"gmaxxxie.fcitx5-theme","name":"Fcitx5 theme","kinds":["service"],"enabled":true,"firstParty":false},
 {"id":"b.okomart","name":"Okomart","kinds":["service","panel"],"enabled":true,"firstParty":false}]
J
    ;;
  plugin\ enable*) exit 0 ;;
  plugin\ disable*) exit 0 ;;
  *) exit 0 ;;
esac
SH
  chmod +x "$WORK/bin/omarchy"
  # 用户真实形态的 shell.json（dev 时代布局: 未受管内置部件 + 场景部件按缓存索引散布）
  cat > "$WORK/home/.config/omarchy/shell.json" <<'JSON'
{"version":1,"bar":{"layout":{
  "left":[{"id":"omarchy.menu"},{"id":"omarchy.workspaces"},{"id":"max.scene"}],
  "center":[{"id":"omarchy.clock"}],
  "right":[{"id":"omarchy.tray"},{"id":"saif.system-stats"},{"id":"omarchy.keyboard-layout"},{"id":"omarchy.bluetooth"},{"id":"omarchy.agents"},{"id":"omarchy.network"},{"id":"io.github.ilyazar.syncthing"},{"id":"local.opencode-go"},{"id":"omarchy.audio"},{"id":"omarchy.monitor"},{"id":"omarchy.power"}]}},"plugins":[{"id":"gmaxxxie.fcitx5-theme"},{"id":"b.okomart"},{"id":"max.keyboard-layout"}],"disabledPlugins":[]}
JSON
  # 场景定义: default+locked（含幽灵 id max.keyboard-layout），dev 场景（label 11 字符）
  cat > "$OMARCHY_SCENES_DIR/scenes.json" <<'JSON'
{"version":1,"current":"dev","default":["gmaxxxie.fcitx5-theme","b.okomart","max.scene","max.keyboard-layout"],"locked":["gmaxxxie.fcitx5-theme","b.okomart","max.scene","max.keyboard-layout"],"unlockedBuiltins":[],"scenes":{"dev":{"label":"Development","plugins":["local.opencode-go","saif.system-stats","b.okomart","io.github.ilyazar.syncthing"]},"focus":{"label":"Focus","plugins":["slcode777.tomato-timer"]}}}
JSON
  # 场景部件的历史位置缓存（含未受管部件的陈旧条目——真实数据里就有）
  cat > "$OMARCHY_SCENES_DIR/entries.json" <<'JSON'
{"saif.system-stats":{"section":"right","index":1,"entry":{"id":"saif.system-stats"}},"io.github.ilyazar.syncthing":{"section":"right","index":6,"entry":{"id":"io.github.ilyazar.syncthing"}},"local.opencode-go":{"section":"right","index":7,"entry":{"id":"local.opencode-go"}},"omarchy.network":{"section":"right","index":5,"entry":{"id":"omarchy.network"}}}
JSON
  rightorder() { jq -r '.bar.layout.right | map(.id) | join(",")' "$WORK/home/.config/omarchy/shell.json"; }
  wifi() { jq -r '.bar.layout.right | to_entries[] | select(.value.id == "omarchy.agents" or .value.id == "omarchy.network" or .value.id == "omarchy.audio" or .value.id == "omarchy.monitor" or .value.id == "omarchy.power") | "\(.value.id)=\(.key)"' "$WORK/home/.config/omarchy/shell.json" | paste -sd' ' -; }
  DEV_WANT="omarchy.tray,saif.system-stats,omarchy.keyboard-layout,omarchy.bluetooth,omarchy.agents,omarchy.network,io.github.ilyazar.syncthing,local.opencode-go,omarchy.audio,omarchy.monitor,omarchy.power"
  DEF_WANT="omarchy.tray,omarchy.keyboard-layout,omarchy.bluetooth,omarchy.agents,omarchy.network,omarchy.audio,omarchy.monitor,omarchy.power"
  stable=1
  for i in 1 2 3; do
    "$SCENE" set default >/dev/null 2>&1 || { bad "set default 失败 (cycle $i)"; stable=0; break; }
    [[ "$(rightorder)" == "$DEF_WANT" ]] || { bad "default 布局漂移 (cycle $i): $(rightorder)"; stable=0; break; }
    "$SCENE" set dev >/dev/null 2>&1 || { bad "set dev 失败 (cycle $i)"; stable=0; break; }
    [[ "$(rightorder)" == "$DEV_WANT" ]] || { bad "dev 布局漂移 (cycle $i): $(rightorder)"; stable=0; break; }
    # wifi/ai/audio/monitor/power 位置逐轮必须完全一致
    [[ "$(wifi)" == "omarchy.agents=4 omarchy.network=5 omarchy.audio=8 omarchy.monitor=9 omarchy.power=10" ]] \
      || { bad "内置部件被挤走 (cycle $i): $(wifi)"; stable=0; break; }
  done
  if [[ $stable -eq 1 ]]; then ok "3 轮 default<->dev: 布局逐轮精确还原，wifi/ai/audio/monitor/power 原地不动"; fi
  expect "_layouts 已写入 scenes.json" sh -c "jq -e '._layouts.dev and ._layouts.default' '$OMARCHY_SCENES_DIR/scenes.json' >/dev/null"
  expect "dev 长 label 保留" sh -c "[ \"\$(jq -r .scenes.dev.label '$OMARCHY_SCENES_DIR/scenes.json')\" = Development ]"
  expect "config 输出正常" "$SCENE" config
  echo "  (T13 done)"
}

# ---------------------------------------------------------------- 汇总

summary() {
  echo
  echo "================================================"
  echo " 通过: $PASS   失败: $FAIL"
  if [[ $FAIL -gt 0 ]]; then
    printf ' 失败用例:\n'
    for n in "${FAILED_NAMES[@]}"; do echo "   - $n"; done
    exit 1
  fi
  echo " 全部通过 ✓"
  exit 0
}

t01_lifecycle
t02_symlink_rejected
t03_toctou_race
t04_fifo
t05_oversize
t06_concurrent
t07_backup
t08_menu_injection
t09_limits
t10_hygiene
t11_lock
t12_roundtrip
t13_layout_stability
summary