#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Docker / 大数据平台管理器 - 本地转发脚本（零依赖，仅 Python 标准库）
作用：浏览器页面无法直接访问 Docker，本脚本把前端请求翻译成 docker/docker-compose 命令执行并回传结果。
只监听 127.0.0.1，不对外暴露，安全。

用法：
    python docker-relay.py [端口]        # 默认 8000
然后浏览器打开：
    http://127.0.0.1:8000/login         # 登录页（多用户系统）
    http://127.0.0.1:8000             # 通用 Docker 管理器（管理员）
    http://127.0.0.1:8000/bigdata     # 大数据平台管理器（管理员）
    http://127.0.0.1:8000/portal      # 普通用户门户（登录后）

多用户体系：
    - 首次启动自动创建管理员 admin（默认密码 admin123，请立即修改，或用环境变量 ADMIN_PASSWORD 指定）。
    - 管理员在 /users 页面创建普通用户账号并设置/重置密码。
    - 每个普通用户可独立启动一套大数据组件容器（项目名 bigdata-u<uid>），
      容器名、网络、宿主机端口、数据目录全部按用户隔离，互不影响。

大数据平台项目目录默认取本脚本的上一级目录（compose/dockerfile 所在），
可通过环境变量 BIGDATA_PROJECT_DIR 覆盖。
"""
import hashlib
import json
import os
import re
import secrets
import shlex
import shutil
import socket
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from http.cookies import SimpleCookie
from urllib.parse import urlparse, parse_qs

# 端口：python docker-relay.py [端口] [主机]
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
# 主机：默认 127.0.0.1（仅本机）；用 0.0.0.0 监听局域网。也可用环境变量 RELAY_HOST 覆盖。
HOST = os.environ.get("RELAY_HOST") or (sys.argv[2] if len(sys.argv) > 2 else "127.0.0.1")
# 访问令牌：可选。设置后所有 /api/ 与页面请求都需带 ?token=xxx 或头 X-Relay-Token。
# 用环境变量 RELAY_TOKEN 传入；不设则不校验（仅信任本机/可信局域网时使用）。
TOKEN = os.environ.get("RELAY_TOKEN") or ""
HERE = os.path.dirname(os.path.abspath(__file__))
INDEX = os.path.join(HERE, "docker-manager.html")
BIGDATA_INDEX = os.path.join(HERE, "bigdata-manager.html")
LOGIN_PAGE = os.path.join(HERE, "login.html")
PORTAL_PAGE = os.path.join(HERE, "user-portal.html")
ADMIN_USERS_PAGE = os.path.join(HERE, "admin-users.html")
TERMINAL_PAGE = os.path.join(HERE, "terminal.html")
VENDOR_DIR = os.path.join(HERE, "vendor")
PROJECT_DIR = os.environ.get("BIGDATA_PROJECT_DIR") or os.path.dirname(HERE)


# ============================================================
# 用户与会话（账号密码 + 角色权限）
# ============================================================
USERS_FILE = os.environ.get("BIGDATA_USERS_FILE") or os.path.join(HERE, "users.json")
USERS = {"next_uid": 1, "users": []}
USERS_LOCK = threading.RLock()
SESSIONS = {}            # sid -> {uid, username, role, expires}
SESSION_TTL = 12 * 3600  # 会话有效期 12 小时
PBKDF2_ITERS = 120000
USERNAME_RE = re.compile(r"^[a-zA-Z0-9_]{2,20}$")


def _hash_pw(password, salt_hex):
    return hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"),
                               bytes.fromhex(salt_hex), PBKDF2_ITERS).hex()


def load_users():
    global USERS
    try:
        with open(USERS_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, dict) and isinstance(data.get("users"), list):
            USERS = data
    except Exception:
        USERS = {"next_uid": 1, "users": []}


def save_users():
    tmp = USERS_FILE + ".tmp"
    with USERS_LOCK:
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(USERS, f, ensure_ascii=False, indent=2)
        os.replace(tmp, USERS_FILE)


def get_user(username):
    with USERS_LOCK:
        for u in USERS["users"]:
            if u.get("username") == username:
                return dict(u)
    return None


def create_user(username, password, role="user"):
    username = (username or "").strip()
    password = password or ""
    if not USERNAME_RE.fullmatch(username):
        return None, "用户名只能为 2-20 位字母/数字/下划线"
    if len(password) < 6:
        return None, "密码至少 6 位"
    if role not in ("user", "admin"):
        return None, "无效角色"
    if get_user(username):
        return None, "用户名已存在"
    with USERS_LOCK:
        uid = int(USERS.get("next_uid", 1))
        USERS["next_uid"] = uid + 1
        salt = secrets.token_hex(16)
        rec = {
            "uid": uid, "username": username, "role": role,
            "salt": salt, "hash": _hash_pw(password, salt),
            "port_base": USER_PORT_START + (uid - 1) * USER_PORTS_PER_USER,
            "created": time.strftime("%Y-%m-%d %H:%M:%S"),
            "disabled": False,
        }
        USERS["users"].append(rec)
    save_users()
    return rec, None


def verify_login(username, password):
    rec = get_user(username or "")
    if not rec:
        return None
    if rec.get("disabled"):
        return None
    if _hash_pw(password or "", rec.get("salt", "")) != rec.get("hash"):
        return None
    return rec


def new_session(rec):
    sid = secrets.token_hex(32)
    SESSIONS[sid] = {"uid": rec["uid"], "username": rec["username"],
                     "role": rec["role"], "expires": time.time() + SESSION_TTL}
    return sid


def session_user(sid):
    if not sid:
        return None
    s = SESSIONS.get(sid)
    if not s:
        return None
    if s["expires"] < time.time():
        SESSIONS.pop(sid, None)
        return None
    return s


def invalidate_sessions(uid=None, sid=None):
    for k in list(SESSIONS.keys()):
        if (uid is not None and SESSIONS[k]["uid"] == uid) or (sid is not None and k == sid):
            SESSIONS.pop(k, None)


def change_password(username, new_password):
    rec = get_user(username)
    if not rec:
        return False, "用户不存在"
    if len(new_password or "") < 6:
        return False, "密码至少 6 位"
    salt = secrets.token_hex(16)
    with USERS_LOCK:
        for u in USERS["users"]:
            if u["username"] == username:
                u["salt"] = salt
                u["hash"] = _hash_pw(new_password, salt)
    save_users()
    invalidate_sessions(uid=rec["uid"])
    return True, None


def bootstrap_admin():
    """首次启动：若无任何管理员，创建 admin（密码取 ADMIN_PASSWORD 或默认 admin123）。"""
    with USERS_LOCK:
        has_admin = any(u.get("role") == "admin" for u in USERS["users"])
    if has_admin:
        return
    pwd = os.environ.get("ADMIN_PASSWORD") or "admin123"
    rec, err = create_user("admin", pwd, "admin")
    if rec:
        print("  [初始化] 已创建管理员账号：admin / %s  ← 请立即登录并修改默认密码！" % pwd)
    else:
        print("  [初始化] 管理员创建失败：%s" % err)


# ============================================================
# 通用工具
# ============================================================
def run_cmd(args, timeout=60, cwd=None, env=None):
    try:
        p = subprocess.run(args, capture_output=True, timeout=timeout,
                           encoding="utf-8", errors="replace", cwd=cwd, env=env)
        return p.returncode == 0, p.stdout, p.stderr
    except FileNotFoundError:
        return False, "", "未找到 docker 命令，请确认已安装并加入 PATH"
    except subprocess.TimeoutExpired:
        return False, "", "命令执行超时"


def parse_ndjson(text):
    out = []
    for line in text.splitlines():
        line = line.strip()
        if line:
            try:
                out.append(json.loads(line))
            except Exception:
                pass
    return out


def get_lan_ips():
    """返回本机所有 IPv4 地址（用于绑定 0.0.0.0 时提示局域网访问 URL）。"""
    ips = []
    try:
        host = socket.gethostname()
        for info in socket.getaddrinfo(host, None, socket.AF_INET):
            ip = info[4][0]
            if ip not in ips and not ip.startswith("127."):
                ips.append(ip)
    except Exception:
        pass
    # 兜底：用 UDP connect 取主 IP
    if not ips:
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            ips.append(s.getsockname()[0])
            s.close()
        except Exception:
            pass
    return ips


# ============================================================
# 通用 Docker 管理
# ============================================================
def api_ping():
    ok, out, err = run_cmd(["docker", "version", "--format", "{{json .}}"])
    if not ok:
        return {"ok": False, "error": err.strip() or "Docker 不可用"}
    try:
        v = json.loads(out)
        return {
            "ok": True,
            "serverVersion": v.get("Server", {}).get("Version", "?"),
            "clientVersion": v.get("Client", {}).get("Version", "?"),
            "os": v.get("Server", {}).get("Os", "?"),
            "arch": v.get("Server", {}).get("Arch", "?"),
        }
    except Exception:
        return {"ok": True, "serverVersion": "?", "clientVersion": "?", "os": "?", "arch": "?"}


def api_containers():
    ok, out, err = run_cmd(["docker", "ps", "-a", "--format", "{{json .}}"])
    if not ok:
        return {"ok": False, "error": err.strip()}
    items = [{
        "id": c.get("ID", ""), "name": c.get("Names", ""), "image": c.get("Image", ""),
        "command": c.get("Command", ""), "status": c.get("Status", ""), "state": c.get("State", ""),
        "ports": c.get("Ports", ""), "created": c.get("CreatedAt", ""),
    } for c in parse_ndjson(out)]
    return {"ok": True, "containers": items}


def api_images():
    ok, out, err = run_cmd(["docker", "images", "--format", "{{json .}}"])
    if not ok:
        return {"ok": False, "error": err.strip()}
    items = [{
        "id": im.get("ID", ""), "repo": im.get("Repository", ""), "tag": im.get("Tag", ""),
        "size": im.get("Size", ""), "created": im.get("CreatedAt", ""),
    } for im in parse_ndjson(out)]
    return {"ok": True, "images": items}


def api_container_action(action, body):
    cid = (body or {}).get("id", "")
    if not cid:
        return {"ok": False, "error": "缺少容器 ID"}
    cmds = {
        "start": ["docker", "start", cid], "stop": ["docker", "stop", cid],
        "restart": ["docker", "restart", cid], "kill": ["docker", "kill", cid],
        "pause": ["docker", "pause", cid], "unpause": ["docker", "unpause", cid],
    }
    if action == "remove":
        args = ["docker", "rm"] + (["-f"] if (body or {}).get("force") else []) + [cid]
    else:
        args = cmds.get(action)
    if not args:
        return {"ok": False, "error": "未知操作"}
    ok, out, err = run_cmd(args)
    return {"ok": ok, "error": err.strip() if not ok else "", "output": out.strip()}


def api_run(body):
    b = body or {}
    image = (b.get("image") or "").strip()
    if not image:
        return {"ok": False, "error": "镜像不能为空"}
    args = ["docker", "create" if b.get("createOnly") else "run", "-d"]
    if b.get("name"):
        args += ["--name", b["name"].strip()]
    for p in b.get("ports") or []:
        if p.strip():
            args += ["-p", p.strip()]
    for e in b.get("env") or []:
        if e.strip():
            args += ["-e", e.strip()]
    for v in b.get("volumes") or []:
        if v.strip():
            args += ["-v", v.strip()]
    if b.get("restart"):
        args += ["--restart", b["restart"].strip()]
    if b.get("network"):
        args += ["--network", b["network"].strip()]
    if b.get("hostname"):
        args += ["--hostname", b["hostname"].strip()]
    args.append(image)
    cmd = (b.get("command") or "").strip()
    if cmd:
        try:
            args += shlex.split(cmd)
        except Exception:
            args += cmd.split()
    ok, out, err = run_cmd(args)
    return {"ok": ok, "error": err.strip() if not ok else "", "output": out.strip()}


def api_logs(body):
    cid = (body or {}).get("id", "")
    tail = int((body or {}).get("tail", 200) or 200)
    if not cid:
        return {"ok": False, "error": "缺少容器 ID"}
    ok, out, err = run_cmd(["docker", "logs", "--tail", str(tail), cid], timeout=30)
    return {"ok": ok, "error": err.strip() if not ok else "", "logs": out}


def api_inspect(body):
    cid = (body or {}).get("id", "")
    if not cid:
        return {"ok": False, "error": "缺少容器 ID"}
    ok, out, err = run_cmd(["docker", "inspect", cid])
    if not ok:
        return {"ok": False, "error": err.strip()}
    try:
        return {"ok": True, "data": json.loads(out)[0]}
    except Exception:
        return {"ok": True, "data": out}


def api_pull(body):
    ref = (body or {}).get("ref", "").strip()
    if not ref:
        return {"ok": False, "error": "镜像名不能为空"}
    ok, out, err = run_cmd(["docker", "pull", ref], timeout=300)
    return {"ok": ok, "error": err.strip() if not ok else "", "output": out.strip()[-2000:]}


def api_image_remove(body):
    iid = (body or {}).get("id", "")
    if not iid:
        return {"ok": False, "error": "缺少镜像 ID"}
    args = ["docker", "rmi"] + (["-f"] if (body or {}).get("force") else []) + [iid]
    ok, out, err = run_cmd(args)
    return {"ok": ok, "error": err.strip() if not ok else "", "output": out.strip()}


# ============================================================
# 大数据平台管理（复刻 bigdata-cli.sh 的功能）
# ============================================================
COMPONENTS = ["hadoop", "hadoop-ha", "zookeeper", "hbase", "hive",
              "kafka", "spark", "flink", "flume", "mysql", "client"]
SINGLE_COMPOSE = {c: "docker-compose.%s.yml" % c for c in COMPONENTS}
MULTI_COMPOSE = "docker-compose.5-node-cluster.yml"
SHARED_NETWORK = "bigdata-net"
BASE_IMAGE = "bigdata-base:latest"
BASE_DOCKERFILE = "dockerfile.base"


def get_compose_file(component, arch):
    return MULTI_COMPOSE if arch == "multi" else SINGLE_COMPOSE[component]


def get_image_name(component, arch):
    if arch == "multi":
        return "bigdata-all-in-one:latest"
    return "bigdata-hadoop:latest" if component == "hadoop-ha" else "bigdata-%s:latest" % component


def get_dockerfile(component, arch):
    if arch == "multi":
        return "dockerfile.all-in-one"
    return "dockerfile.hadoop" if component == "hadoop-ha" else "dockerfile.%s" % component


def ensure_shared_network():
    r = subprocess.run(["docker", "network", "inspect", SHARED_NETWORK],
                       capture_output=True, encoding="utf-8", errors="replace")
    if r.returncode == 0:
        return True, "公共网络已存在：%s" % SHARED_NETWORK
    c = subprocess.run(["docker", "network", "create", SHARED_NETWORK],
                       capture_output=True, encoding="utf-8", errors="replace")
    if c.returncode == 0:
        return True, "公共网络已创建：%s" % SHARED_NETWORK
    return False, "公共网络创建失败：%s" % (c.stderr.strip() or "unknown")


def check_base_dependency(dockerfile):
    """读取目标 Dockerfile 的直接父镜像，若直接继承 base 则检查其是否存在。"""
    path = os.path.join(PROJECT_DIR, dockerfile)
    parent = None
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                s = line.strip()
                if s.upper().startswith("FROM"):
                    parts = s.split()
                    if len(parts) >= 2:
                        parent = parts[1]
                    break
    except Exception:
        return True, None
    if parent != BASE_IMAGE:
        return True, None
    r = subprocess.run(["docker", "image", "inspect", BASE_IMAGE], capture_output=True)
    if r.returncode == 0:
        return True, None
    return False, "缺少基础镜像 %s，请先「构建基础镜像」" % BASE_IMAGE


def find_bash():
    for p in [r"C:\Program Files\Git\bin\bash.exe", r"C:\Program Files\Git\usr\bin\bash.exe"]:
        if os.path.exists(p):
            return p
    return None


# ---- 后台任务（流式输出） ----
TASKS = {}
TASK_LOCK = threading.Lock()
TASK_SEQ = [0]


def start_task(run_fn, owner="admin"):
    with TASK_LOCK:
        TASK_SEQ[0] += 1
        tid = str(TASK_SEQ[0])
    task = {"id": tid, "running": True, "code": None, "out": [], "owner": owner}
    TASKS[tid] = task

    def emit(s):
        task["out"].append(s)

    def worker():
        try:
            code = run_fn(emit)
            task["code"] = code
        except Exception as e:
            emit("\n[ERROR] %s\n" % e)
            task["code"] = -1
        finally:
            task["running"] = False
    threading.Thread(target=worker, daemon=True).start()
    return tid


def run_stream(args, emit, cwd=PROJECT_DIR, env=None):
    emit("$ " + " ".join(args) + "\n")
    p = subprocess.Popen(args, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                         text=True, encoding="utf-8", errors="replace", bufsize=1, env=env)
    for line in p.stdout:
        emit(line)
    p.wait()
    return p.returncode


def bash_env():
    env = dict(os.environ)
    env["MSYS_NO_PATHCONV"] = "1"
    env["MSYS2_ARG_CONV_EXCL"] = "*"
    return env


def build_run_fn(op, component, arch, tail):
    """根据操作生成一个 run_fn(emit)->exit_code。"""
    def single_command(args):
        return lambda emit: run_stream(args, emit)

    if op == "build-base":
        return single_command(["docker", "build", "-t", BASE_IMAGE, "-f", BASE_DOCKERFILE, "."])

    if op == "build":
        dockerfile = get_dockerfile(component, arch)
        image = get_image_name(component, arch)
        if not os.path.exists(os.path.join(PROJECT_DIR, dockerfile)):
            return lambda emit: (emit("[ERROR] Dockerfile 不存在：%s\n" % dockerfile), 1)[1]
        def _build(emit):
            ok, msg = check_base_dependency(dockerfile)
            if not ok:
                emit("[ERROR] %s\n" % msg)
                return 1
            if arch == "single":
                okn, msgn = ensure_shared_network()
                emit("[INFO] %s\n" % msgn)
                if not okn:
                    emit("[ERROR] %s\n" % msgn)
                    return 1
            return run_stream(["docker", "build", "-t", image, "-f", dockerfile, "."], emit)
        return _build

    if op == "delete":
        return single_command(["docker", "image", "rm", get_image_name(component, arch)])

    if op == "start":
        f = get_compose_file(component, arch)
        def _start(emit):
            if arch == "single":
                okn, msgn = ensure_shared_network()
                emit("[INFO] %s\n" % msgn)
                if not okn:
                    return 1
            return run_stream(["docker", "compose", "-f", f, "up", "-d"], emit)
        return _start

    if op == "stop":
        return single_command(["docker", "compose", "-f", get_compose_file(component, arch), "stop"])

    if op == "destroy":
        return single_command(["docker", "compose", "-f", get_compose_file(component, arch), "down"])

    if op == "clean":
        return single_command(["docker", "compose", "-f", get_compose_file(component, arch), "down", "-v"])

    if op == "restart":
        f = get_compose_file(component, arch)
        def _restart(emit):
            if arch == "single":
                okn, msgn = ensure_shared_network()
                emit("[INFO] %s\n" % msgn)
                if not okn:
                    return 1
            c1 = run_stream(["docker", "compose", "-f", f, "stop"], emit)
            c2 = run_stream(["docker", "compose", "-f", f, "up", "-d"], emit)
            return c2 if c2 != 0 else c1
        return _restart

    if op == "logs":
        return single_command(["docker", "compose", "-f", get_compose_file(component, arch),
                               "logs", "--tail", str(tail or 200)])

    if op == "test":
        if arch == "multi":
            script = "test/cluster-test.sh"
        else:
            script = "test/test-%s.sh" % component
        if not os.path.exists(os.path.join(PROJECT_DIR, script)):
            return lambda emit: (emit("[ERROR] 测试脚本不存在：%s\n" % script), 1)[1]
        bash = find_bash()
        if not bash:
            return lambda emit: (emit("[ERROR] 未找到 Git Bash，无法执行 .sh 测试脚本\n"), 1)[1]
        def _test(emit):
            return run_stream([bash, "./" + script.replace("\\", "/")], emit, cwd=PROJECT_DIR, env=bash_env())
        return _test

    if op == "supervisor":
        if arch != "multi":
            return lambda emit: (emit("[ERROR] Supervisor 状态仅适用于多架构集群\n"), 1)[1]
        f = get_compose_file(component, arch)
        def _supervisor(emit):
            r = subprocess.run(["docker", "compose", "-f", f, "ps", "-q"], cwd=PROJECT_DIR,
                               capture_output=True, text=True, encoding="utf-8", errors="replace")
            ids = [x for x in r.stdout.splitlines() if x.strip()]
            if not ids:
                emit("[WARNING] 集群暂无运行容器\n")
                return 0
            for cid in ids:
                name = subprocess.run(["docker", "inspect", "--format", "{{.Name}}", cid],
                                      capture_output=True, text=True, encoding="utf-8", errors="replace").stdout.strip().lstrip("/")
                emit("\n===== 容器：%s =====\n" % name)
                code = run_stream(["docker", "exec", cid, "supervisorctl", "status"], emit)
                emit("\n")
                if code != 0:
                    return code
            return 0
        return _supervisor

    if op == "clean-all":
        def _clean_all(emit):
            failed = False
            for f in list(SINGLE_COMPOSE.values()) + [MULTI_COMPOSE]:
                if not os.path.exists(os.path.join(PROJECT_DIR, f)):
                    emit("[WARNING] 跳过不存在的 Compose 文件：%s\n" % f)
                    continue
                emit("[INFO] 正在清理：%s\n" % f)
                if run_stream(["docker", "compose", "-f", f, "down", "-v"], emit) != 0:
                    failed = True
            r = subprocess.run(["docker", "network", "inspect", SHARED_NETWORK], capture_output=True)
            if r.returncode == 0:
                emit("[INFO] 正在删除公共网络：%s\n" % SHARED_NETWORK)
                if run_stream(["docker", "network", "rm", SHARED_NETWORK], emit) != 0:
                    emit("[ERROR] 公共网络删除失败，可能仍有外部容器连接\n")
                    failed = True
            return 1 if failed else 0
        return _clean_all

    if op == "clean-volumes":
        def _clean_vol(emit):
            r = subprocess.run(["docker", "volume", "ls", "-qf", "dangling=true"],
                               capture_output=True, text=True, encoding="utf-8", errors="replace")
            vols = [x for x in r.stdout.splitlines() if x.strip()]
            if not vols:
                emit("[INFO] 系统无悬空卷\n")
                return 0
            emit("[INFO] 待清理悬空卷 %d 个\n" % len(vols))
            code = run_stream(["docker", "volume", "rm"] + vols, emit)
            return code
        return _clean_vol

    return lambda emit: (emit("[ERROR] 未知操作：%s\n" % op), 1)[1]


def get_services(component, arch):
    """返回指定组件 compose 文件里定义的服务名列表（用于精确过滤容器）。"""
    f = get_compose_file(component, arch)
    r = subprocess.run(["docker", "compose", "-f", f, "config", "--services"],
                       cwd=PROJECT_DIR, capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    if r.returncode != 0:
        return []
    return [s.strip() for s in r.stdout.splitlines() if s.strip()]


# 容器内端口 -> (用途标签, 是否为可用浏览器打开的 Web 服务)
# 按「容器端口」标注，因为宿主机端口可能因系统保留区间被改写。
PORT_INFO = {
    22:     ("SSH", False),
    2181:   ("ZooKeeper", False),
    3306:   ("MySQL", False),
    4040:   ("Application UI", True),
    6123:   ("Flink RPC", False),
    7077:   ("Spark Master RPC", False),
    8020:   ("HDFS RPC", False),
    8080:   ("Web UI", True),
    8081:   ("Web UI", True),
    8082:   ("Web UI", True),
    8088:   ("YARN UI", True),
    9000:   ("HDFS", False),
    9083:   ("Metastore", False),
    9092:   ("Kafka", False),
    9864:   ("DataNode UI", True),
    9870:   ("NameNode UI", True),
    10000:  ("HiveServer2", False),
    10002:  ("Hive UI", True),
    16000:  ("HBase Master RPC", False),
    16010:  ("HBase UI", True),
    16020:  ("RegionServer", False),
    16030:  ("HBase UI", True),
    18080:  ("History Server", True),
    19888:  ("JobHistory UI", True),
}


def parse_publishers(entry):
    """从 compose ps 的 Publishers 提取宿主机/容器端口映射，去重 IPv4/IPv6 双栈记录。"""
    out, seen = [], set()
    for p in entry.get("Publishers") or []:
        try:
            host = int(p.get("PublishedPort") or 0)
            target = int(p.get("TargetPort") or 0)
        except (TypeError, ValueError):
            continue
        if host <= 0 or target <= 0:
            continue  # 仅 expose、未发布到宿主机
        key = (host, target)
        if key in seen:
            continue  # 0.0.0.0 与 :: 两条记录只保留一条
        seen.add(key)
        label, is_web = PORT_INFO.get(target, ("", False))
        out.append({
            "host": host, "target": target,
            "protocol": p.get("Protocol") or "tcp",
            "label": label, "web": is_web,
        })
    out.sort(key=lambda v: v["host"])
    return out


def api_bigdata_status(component, arch):
    f = get_compose_file(component, arch)
    if not os.path.exists(os.path.join(PROJECT_DIR, f)):
        return {"ok": False, "running": False, "output": "Compose 文件不存在：%s" % f}
    services = get_services(component, arch)
    r = subprocess.run(["docker", "compose", "-f", f, "ps", "-a", "--format", "json"],
                       cwd=PROJECT_DIR, capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    running = False
    containers = []
    if r.returncode == 0:
        # ps --format json 输出为 NDJSON（每行一个对象），需按行解析
        arr = parse_ndjson(r.stdout)
        # 各 compose 文件共用 project 名，ps 会混入其他组件的容器，需按 Service 精确过滤
        for x in arr:
            svc = x.get("Service", "")
            if services and svc not in services:
                continue
            containers.append({
                "name": x.get("Name", ""),
                "id": x.get("ID", ""),
                "service": svc,
                "state": x.get("State", ""),
                "status": x.get("Status", ""),
                "ports": parse_publishers(x),
            })
        running = any(c.get("state") == "running" for c in containers)
        if not containers and not arr:
            running = "running" in r.stdout.lower()
    r2 = subprocess.run(["docker", "compose", "-f", f, "ps"], cwd=PROJECT_DIR,
                        capture_output=True, text=True, encoding="utf-8", errors="replace")
    return {"ok": True, "running": running, "containers": containers,
            "output": (r2.stdout or r2.stderr).strip()}


def api_exec_shell(body):
    """在宿主机打开一个新终端窗口，执行 docker exec -it <容器> <shell> 进入容器。"""
    container = (body or {}).get("container", "").strip()
    shell = (body or {}).get("shell", "bash").strip() or "bash"
    if not container:
        return {"ok": False, "error": "缺少容器名"}
    if not re.fullmatch(r"[A-Za-z0-9_.\-]+", container):
        return {"ok": False, "error": "非法容器名"}
    if shell not in ("bash", "sh"):
        return {"ok": False, "error": "不支持的 shell（仅 bash / sh）"}
    r = subprocess.run(["docker", "inspect", "--format", "{{.State.Running}}", container],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    if r.returncode != 0 or r.stdout.strip() != "true":
        return {"ok": False, "error": "容器不存在或未运行，无法进入"}
    if os.name == "nt":
        # Windows：用 start 打开一个新 cmd 窗口（/k 保留窗口，退出容器后仍可继续操作）
        title = "docker exec - " + container
        cmdline = 'start "%s" cmd /k docker exec -it %s %s' % (title, container, shell)
        try:
            subprocess.Popen(cmdline, shell=True)
        except Exception as e:
            return {"ok": False, "error": "无法打开终端窗口：" + str(e)}
    else:
        opened = False
        for term in (["gnome-terminal", "--", "docker", "exec", "-it", container, shell],
                     ["x-terminal-emulator", "-e", "docker exec -it %s %s" % (container, shell)],
                     ["xterm", "-e", "docker exec -it %s %s" % (container, shell)]):
            try:
                subprocess.Popen(term)
                opened = True
                break
            except Exception:
                continue
        if not opened:
            return {"ok": False, "error": "未找到可用的终端模拟器"}
    return {"ok": True, "output": "已在新窗口打开终端：docker exec -it %s %s" % (container, shell)}


# ============================================================
# 用户专属容器栈（按用户隔离：项目名 / 容器名 / 网络 / 端口 / 数据目录）
# ============================================================
# 端口分配：每用户 200 个端口（块基 = 20000 + (uid-1)*200），
# 每组件预留 20 个槽位：新宿主机端口 = 块基 + 组件索引*20 + 槽位号。
USER_PORT_START = 20000
USER_PORTS_PER_USER = 200
PORTS_PER_COMP = 20
STACK_ROOT = os.path.join(PROJECT_DIR, "stacks")
COMP_INDEX = {c: i for i, c in enumerate(COMPONENTS)}
PORT_MAP_RE = re.compile(r'^(\s*)-\s*"?(\d{2,5}):(\d{2,5})"?(\s*#.*)?$')
CONTAINER_NAME_RE = re.compile(r'^(\s*container_name:\s*)([A-Za-z0-9_.\-]+)(.*)$')
CONFIG_BIND_RE = re.compile(r'^(\s*-\s+)(\./config/.+)$')


def user_project(rec):
    return "bigdata-u%d" % rec["uid"]


def user_network(rec):
    return "bigdata-u%d-net" % rec["uid"]


def ensure_network(name):
    r = subprocess.run(["docker", "network", "inspect", name],
                       capture_output=True, encoding="utf-8", errors="replace")
    if r.returncode == 0:
        return True, "网络已存在：%s" % name
    c = subprocess.run(["docker", "network", "create", name],
                       capture_output=True, encoding="utf-8", errors="replace")
    if c.returncode == 0:
        return True, "网络已创建：%s" % name
    return False, "网络创建失败：%s" % (c.stderr.strip() or "unknown")


def stack_dir(rec):
    return os.path.join(STACK_ROOT, rec["username"])


def stack_compose(rec, component):
    return os.path.join(stack_dir(rec), "docker-compose.%s.yml" % component)


def sync_client_examples(user_stack_dir):
    """把 examples/client/ 下后补的示例增量投放进用户 workspace（不覆盖学生代码）。

    镜像内 /opt/client-examples 是构建时的快照，早期 client-entrypoint.sh 还以
    /workspace/README.md 是否存在作为投放门槛；两者叠加会让「镜像构建之后新增的示例」
    （例如 kafka_producer.py / kafka_consumer.py）永远进不了已创建过的用户栈。
    这里按文件粒度补齐：已存在的文件一律跳过，学生自己写的代码不会被覆盖。
    """
    src_root = os.path.join(PROJECT_DIR, "examples", "client")
    dst_root = os.path.join(user_stack_dir, "workspace")
    if not os.path.isdir(src_root):
        return
    for root, _dirs, files in os.walk(src_root):
        rel = os.path.relpath(root, src_root)
        target = dst_root if rel == "." else os.path.join(dst_root, rel)
        os.makedirs(target, exist_ok=True)
        for fn in files:
            src, dst = os.path.join(root, fn), os.path.join(target, fn)
            if os.path.exists(dst):
                continue
            try:
                shutil.copy2(src, dst)
            except OSError:
                pass


def generate_user_compose(rec, component):
    """从原始组件 compose 生成用户专属副本。改写规则：
    1. container_name: X        -> u<uid>-X   （容器名全局唯一）
    2. bigdata-net              -> bigdata-u<uid>-net（独立外部网络，用户间不互通）
    3. ports 块宿主机端口         -> 用户端口块内的新端口（容器端口不动，配置不受影响）
    4. - ./config/...           -> - ../config/...（共享只读配置，仍指向项目 config/）
       - ./data/...             保持相对路径（落到 stacks/<用户>/data/，按用户隔离）
    """
    src = os.path.join(PROJECT_DIR, SINGLE_COMPOSE[component])
    if not os.path.exists(src):
        return None, "组件 Compose 文件不存在：%s" % SINGLE_COMPOSE[component]
    with open(src, "r", encoding="utf-8") as f:
        text = f.read()
    uid = rec["uid"]
    base = rec["port_base"] + COMP_INDEX.get(component, 0) * PORTS_PER_COMP
    out, slot = [], 0
    in_ports, ports_indent = False, 0
    for line in text.splitlines():
        m = CONTAINER_NAME_RE.match(line)
        if m and not m.group(2).startswith("u%d-" % uid):
            line = m.group(1) + "u%d-" % uid + m.group(2) + (m.group(3) or "")
        if "bigdata-net" in line:
            line = line.replace("bigdata-net", user_network(rec))
        stripped = line.strip()
        if in_ports:
            pm = PORT_MAP_RE.match(line)
            if pm:
                if component == "client":
                    # 用户端口块 200 个已被前 10 个组件占满；开发容器只通过
                    # docker exec 使用，一旦误写 ports 就会落到下一个用户的端口段。
                    return None, ("开发容器 client 不发布宿主机端口（用户端口段已分配满）；"
                                  "请改用 expose 或通过 docker exec 进入")
                if slot >= PORTS_PER_COMP:
                    return None, "组件 %s 发布端口超过 %d 个，无法分配" % (component, PORTS_PER_COMP)
                target = int(pm.group(3))
                new_host = base + slot
                slot += 1
                line = '%s- "%d:%d"%s' % (pm.group(1), new_host, target, pm.group(4) or "")
            elif stripped and not stripped.startswith("#"):
                indent = len(line) - len(line.lstrip())
                if indent <= ports_indent:
                    in_ports = False
        elif line.lstrip().startswith("ports:"):
            in_ports = True
            ports_indent = len(line) - len(line.lstrip())
        if not in_ports:
            bm = CONFIG_BIND_RE.match(line)
            if bm:
                line = bm.group(1) + "../../" + bm.group(2)
        out.append(line)
    os.makedirs(stack_dir(rec), exist_ok=True)
    if component == "client":
        sync_client_examples(stack_dir(rec))
    dst = stack_compose(rec, component)
    with open(dst, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out) + "\n")
    return dst, None


def compose_run(rec, args, emit=None, timeout=None):
    """以用户项目名执行 docker compose 子命令。"""
    cmd = ["docker", "compose"] + args
    if emit:
        return run_stream(cmd, emit, cwd=stack_dir(rec))
    ok, out, err = run_cmd(cmd, cwd=stack_dir(rec), timeout=timeout or 60)
    return (1 if not ok else 0), out, err


def stack_compose_args(rec, component):
    f = stack_compose(rec, component)
    if not os.path.exists(f):
        return None, "尚未创建用户栈，请先启动组件 %s" % component
    return ["-f", f, "-p", user_project(rec)], None


# 组件依赖：启动某组件前必须先启动其前置组件（同一用户的所有组件共享其专属网络，
# 服务名如 namenode / zoo1 / mysql 在网络内可按主机名解析）。
# "__HDFS__" 按 config/environment.conf 的 HADOOP_ENVIRONMENT 动态解析为 hadoop 或 hadoop-ha。
COMPONENT_DEPS = {
    "spark": ["__HDFS__"],
    "hive": ["__HDFS__", "mysql"],
    "hbase": ["__HDFS__", "zookeeper"],
    "kafka": ["zookeeper"],
    "flume": ["kafka"],
}


def read_hadoop_environment():
    path = os.path.join(PROJECT_DIR, "config", "environment.conf")
    try:
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                s = line.strip()
                if s and not s.startswith("#") and "=" in s:
                    k, v = s.split("=", 1)
                    if k.strip() == "HADOOP_ENVIRONMENT":
                        return v.strip().strip('"').strip("'").lower()
    except Exception:
        pass
    return "standard"


def component_deps(component):
    """返回按拓扑顺序排列的前置组件列表（不含 component 自身）。"""
    hdfs = "hadoop-ha" if read_hadoop_environment() == "ha" else "hadoop"

    def resolve(c, seen):
        if c in seen:
            return []
        seen.add(c)
        out = []
        for d in COMPONENT_DEPS.get(c, []):
            out += resolve(hdfs if d == "__HDFS__" else d, seen)
        return out + [c]
    return resolve(component, set())[:-1]


def stack_services(rec, args):
    """该用户组件 compose 文件定义的服务名（用于把同一项目下其他组件的容器过滤掉）。"""
    r = subprocess.run(["docker", "compose"] + args + ["config", "--services"],
                       cwd=stack_dir(rec), capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    if r.returncode != 0:
        return []
    return [s.strip() for s in r.stdout.splitlines() if s.strip()]


def stack_is_running(rec, component, args):
    r = subprocess.run(["docker", "compose"] + args + ["ps", "-a", "--format", "json"],
                       cwd=stack_dir(rec), capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    if r.returncode != 0:
        return False
    services = stack_services(rec, args)
    arr = [x for x in parse_ndjson(r.stdout)
           if not services or x.get("Service") in services]
    return bool(arr) and all(x.get("State") == "running" for x in arr)


def api_portal_stacks(rec):
    """当前用户全部组件栈状态（仅统计已生成过的栈）。"""
    stacks = {}
    for comp in COMPONENTS:
        args, err = stack_compose_args(rec, comp)
        if not args:
            stacks[comp] = {"created": False, "running": False, "containers": []}
            continue
        services = stack_services(rec, args)
        r = subprocess.run(["docker", "compose"] + args + ["ps", "-a", "--format", "json"],
                           cwd=stack_dir(rec), capture_output=True, text=True,
                           encoding="utf-8", errors="replace")
        containers = []
        if r.returncode == 0:
            for x in parse_ndjson(r.stdout):
                if services and x.get("Service", "") not in services:
                    continue  # 同项目下其他组件的容器，不属于本卡片
                containers.append({
                    "name": x.get("Name", ""), "id": x.get("ID", ""),
                    "service": x.get("Service", ""), "state": x.get("State", ""),
                    "status": x.get("Status", ""), "ports": parse_publishers(x),
                })
        stacks[comp] = {"created": True,
                        "running": any(c["state"] == "running" for c in containers),
                        "containers": containers}
    return {"ok": True, "stacks": stacks}


# ============================================================
# 用户容器内执行命令（Web 终端，等价于 docker exec，仅能进入本人容器）
# ============================================================
EXEC_PWD_MARK = "__BIGDATA_PWD_9c2f__"


def user_container_allowed(rec, container):
    """严格校验容器归属：必须由本人 compose 项目创建、且当前正在运行。

    三重校验：容器名前缀 u<uid>- ；com.docker.compose.project / .service 标签
    证明它由本人 compose 项目创建；inspect 返回的真实容器名与传入一致。
    防止普通用户 exec 到他人容器、宿主机主平台容器或手工伪造的同名容器。
    """
    if not container or not re.fullmatch(r"[A-Za-z0-9_.\-]+", container):
        return False, "非法容器名"
    if not container.startswith("u%d-" % rec["uid"]):
        return False, "只能进入自己实验环境的容器"
    fmt = ('{{index .Config.Labels "com.docker.compose.project"}}|'
           '{{index .Config.Labels "com.docker.compose.service"}}|'
           '{{.State.Running}}|{{.Name}}')
    try:
        p = subprocess.run(["docker", "inspect", "--format", fmt, container],
                           capture_output=True, text=True, encoding="utf-8",
                           errors="replace", timeout=15)
    except Exception as e:
        return False, "无法读取容器信息：" + str(e)
    if p.returncode != 0:
        return False, "容器不存在或已销毁"
    parts = (p.stdout or "").strip().split("|")
    if len(parts) < 4:
        return False, "该容器不属于你的实验环境"
    project, service, running, real_name = (x.strip() for x in parts[:4])
    if project != user_project(rec) or not service or service == "<no value>":
        return False, "该容器不属于你的实验环境"
    if running != "true":
        return False, "容器未运行，请先启动对应组件"
    if real_name.lstrip("/") != container:
        return False, "容器名不匹配"
    return True, ""


def api_portal_exec_container(rec, body):
    """在用户自己的容器内执行一条命令，返回输出、退出码与执行后的工作目录。

    每条命令是一次独立的 docker exec（非持久 TTY）；用 cd 恢复上次目录，
    并在输出末尾以标记回传 $PWD，前端据此保留 cd 状态。
    命令字符串作为 argv 交给容器内 shell，不经过宿主机 shell，不会注入宿主机。
    """
    container = (body.get("container") or "").strip()
    command = body.get("command") or ""
    cwd = (body.get("cwd") or "/").strip() or "/"
    if not cwd.startswith("/"):
        cwd = "/"
    try:
        timeout = int(body.get("timeout") or 30)
    except (TypeError, ValueError):
        timeout = 30
    timeout = max(5, min(timeout, 120))

    allowed, err = user_container_allowed(rec, container)
    if not allowed:
        return {"ok": False, "error": err}
    if not command.strip():
        return {"ok": False, "error": "命令不能为空"}
    if len(command) > 8000:
        return {"ok": False, "error": "命令过长（上限 8000 字符）"}

    script = ("cd -- %s 2>/dev/null || cd /\n" % shlex.quote(cwd)) + command + \
             "\n__bd_rc=$?\nprintf '\\n" + EXEC_PWD_MARK + "%s\\n' \"$PWD\"\nexit $__bd_rc"
    base = ["docker", "exec", "-i", container]
    p = None
    for shell in (["bash", "-lc", script], ["sh", "-c", script]):
        try:
            p = subprocess.run(base + shell, stdin=subprocess.DEVNULL,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               timeout=timeout, encoding="utf-8", errors="replace")
        except subprocess.TimeoutExpired:
            return {"ok": False, "error": "命令执行超时（%d 秒），已中断" % timeout, "cwd": cwd}
        except FileNotFoundError:
            return {"ok": False, "error": "未找到 docker 命令，请确认已安装并加入 PATH"}
        except Exception as e:
            return {"ok": False, "error": str(e)}
        out = p.stdout or ""
        # 极少数镜像没有 bash，回退到 sh 重试
        if p.returncode in (126, 127) and "bash" in out and \
                ("not found" in out or "No such file" in out):
            continue
        break

    out = (p.stdout or "").replace("\r\n", "\n")
    m = None
    for m in re.finditer(r"\n" + re.escape(EXEC_PWD_MARK) + r"([^\n]*)\n?", out):
        pass
    if m:
        cand = m.group(1).strip()
        if cand.startswith("/"):
            cwd = cand
        out = out[:m.start()]  # 去掉内部标记行
    return {"ok": True, "code": p.returncode, "output": out.rstrip("\n"),
            "cwd": cwd, "container": container}


# ============================================================
# 全交互终端：WebSocket（RFC 6455，纯标准库）+ 容器内 PTY
# ============================================================
import base64
import struct

WS_MAGIC_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
TERM_ROWS = 40
TERM_COLS = 120


class WSConnection:
    """极简 WebSocket 服务端帧编解码：客户端帧必须掩码，服务端回二进制帧。"""

    def __init__(self, handler, stop_evt):
        self.rfile = handler.rfile
        self.sock = handler.connection
        self.stop_evt = stop_evt
        self.lock = threading.Lock()
        self.buf = b""
        self.alive = True

    def _read_exact(self, n):
        # 注意：不要用 socket.settimeout + rfile.read1 组合。socket.makefile() 的
        # BufferedReader 一旦发生读超时就会永久进入 "cannot read from timed out object"
        # 状态，导致终端空闲半秒即被误关。这里保持阻塞读，会话结束时由
        # connection.shutdown() 唤醒本线程。
        while len(self.buf) < n:
            chunk = self.rfile.read1(65536) if hasattr(self.rfile, "read1") else self.rfile.read(1)
            if not chunk:
                raise ConnectionError("peer closed")
            self.buf += chunk
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def recv_message(self):
        """返回 (kind, data)：text / binary / close / ignore；自动应答 ping、拼接分片。"""
        parts, first_opcode = [], None
        while True:
            b1, b2 = self._read_exact(2)
            fin = bool(b1 & 0x80)
            opcode = b1 & 0x0F
            masked = bool(b2 & 0x80)
            length = b2 & 0x7F
            if length == 126:
                length = struct.unpack("!H", self._read_exact(2))[0]
            elif length == 127:
                length = struct.unpack("!Q", self._read_exact(8))[0]
            mask = self._read_exact(4) if masked else None
            data = self._read_exact(length) if length else b""
            if mask:
                data = bytes(c ^ mask[i & 3] for i, c in enumerate(data))
            if opcode == 0x8:          # close
                return "close", b""
            if opcode == 0x9:          # ping -> pong
                self.send(data, opcode=0xA)
                continue
            if opcode == 0xA:          # pong
                continue
            if opcode in (0x1, 0x2):
                if first_opcode is None:
                    first_opcode = opcode
                parts.append(data)
                if fin:
                    return ("text" if first_opcode == 0x1 else "binary", b"".join(parts))
            if fin and first_opcode is None:
                return "ignore", b""

    def send(self, data, opcode=0x2):
        if isinstance(data, str):
            data = data.encode("utf-8", "replace")
        header = bytearray([0x80 | opcode])
        n = len(data)
        if n < 126:
            header.append(n)
        elif n < 65536:
            header.append(126)
            header += struct.pack("!H", n)
        else:
            header.append(127)
            header += struct.pack("!Q", n)
        with self.lock:
            if self.alive:
                self.sock.sendall(bytes(header) + data)

    def close(self):
        try:
            self.send(b"", opcode=0x8)
        except Exception:
            pass
        self.alive = False


def run_interactive_term(handler, container):
    """把浏览器终端与容器内 PTY 双向桥接，直到任一侧关闭。

    docker exec -it 要求父进程 stdin 本身是 TTY（Python 服务不具备），因此改在容器内
    用 util-linux 的 script 创建伪终端：
        docker exec -i <容器> script -q -c "stty rows 40 cols 120; exec bash -l" /dev/null
    这样 bash / vim / top 都认为自己连着真终端。
    """
    key = handler.headers.get("Sec-WebSocket-Key", "")
    accept = base64.b64encode(
        hashlib.sha1((key + WS_MAGIC_GUID).encode("ascii")).digest()).decode("ascii")
    handler.close_connection = True
    handler.connection.sendall((
        "HTTP/1.1 101 Switching Protocols\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        "Sec-WebSocket-Accept: %s\r\n\r\n" % accept
    ).encode("ascii"))

    stop = threading.Event()
    ws = WSConnection(handler, stop)
    inner = "stty rows %d cols %d 2>/dev/null; exec bash -l" % (TERM_ROWS, TERM_COLS)
    cmd = ["docker", "exec", "-e", "TERM=xterm-256color", "-e", "LANG=C.UTF-8",
           "-i", container, "script", "-q", "-c", inner, "/dev/null"]
    try:
        proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, bufsize=0)
    except Exception as e:
        ws.send(("\r\n[ERROR] 无法启动容器终端：%s\r\n" % e).encode("utf-8"))
        ws.close()
        return

    def ws_to_pty():
        try:
            while ws.alive and not stop.is_set():
                kind, data = ws.recv_message()
                if kind == "close":
                    break
                if kind in ("text", "binary") and data:
                    proc.stdin.write(data)
                    proc.stdin.flush()
        except Exception:
            pass
        finally:
            stop.set()

    def pty_to_ws():
        try:
            while not stop.is_set():
                data = proc.stdout.read(4096)
                if not data:
                    break
                ws.send(data, opcode=0x2)
        except Exception:
            pass
        finally:
            stop.set()

    t1 = threading.Thread(target=ws_to_pty, daemon=True)
    t2 = threading.Thread(target=pty_to_ws, daemon=True)
    t1.start()
    t2.start()
    stop.wait()

    # 让 shell 正常退出，避免容器内残留交互式进程
    try:
        if proc.poll() is None:
            proc.stdin.write(b"exit\r")
            proc.stdin.flush()
    except Exception:
        pass
    try:
        proc.wait(timeout=3)
    except Exception:
        try:
            proc.kill()
        except Exception:
            pass
    ws.close()
    try:
        handler.connection.shutdown(socket.SHUT_RDWR)
    except Exception:
        pass


def build_portal_run_fn(rec, op, component, tail):
    """用户栈操作：start/stop/restart/destroy/clean/logs。"""
    def _fail(emit, msg):
        emit("[ERROR] %s\n" % msg)
        return 1

    if op == "start":
        def _start(emit):
            proj = user_project(rec)
            net = user_network(rec)
            # 自动按依赖顺序先启动前置组件（如 spark 需先启动 hadoop，否则其入口脚本
            # 会等待 HDFS 约 3 分钟），已全部运行则跳过。
            deps = component_deps(component)
            if deps:
                emit("[依赖] 组件 %s 需先启动：%s\n" % (component, " → ".join(deps)))
            for dep in deps:
                f, err = generate_user_compose(rec, dep)
                if not f:
                    return _fail(emit, err)
                dep_args = ["-f", f, "-p", proj]
                okn, msgn = ensure_network(net)
                if not okn:
                    return _fail(emit, msgn)
                if stack_is_running(rec, dep, dep_args):
                    emit("[依赖] %s 已在运行，跳过\n" % dep)
                    continue
                emit("[依赖] 正在启动 %s …\n" % dep)
                if run_stream(["docker", "compose"] + dep_args + ["up", "-d"],
                              emit, cwd=stack_dir(rec)) != 0:
                    return _fail(emit, "依赖组件 %s 启动失败，已中止 %s" % (dep, component))
            f, err = generate_user_compose(rec, component)
            if not f:
                return _fail(emit, err)
            args = ["-f", f, "-p", proj]
            okn, msgn = ensure_network(net)
            emit("[INFO] %s\n" % msgn)
            if not okn:
                return _fail(emit, msgn)
            emit("[INFO] 用户 %s 的 %s 栈：宿主机端口段 %d-%d\n" % (
                rec["username"], component, rec["port_base"], rec["port_base"] + USER_PORTS_PER_USER - 1))
            return run_stream(["docker", "compose"] + args + ["up", "-d"], emit, cwd=stack_dir(rec))
        return _start

    if op in ("stop", "destroy", "clean", "restart", "logs"):
        def _op(emit):
            args, err = stack_compose_args(rec, component)
            if not args:
                return _fail(emit, err)
            if op == "stop":
                return run_stream(["docker", "compose"] + args + ["stop"], emit, cwd=stack_dir(rec))
            if op == "destroy":
                return run_stream(["docker", "compose"] + args + ["down"], emit, cwd=stack_dir(rec))
            if op == "clean":
                return run_stream(["docker", "compose"] + args + ["down", "-v"], emit, cwd=stack_dir(rec))
            if op == "logs":
                return run_stream(["docker", "compose"] + args + ["logs", "--tail", str(tail or 200)],
                                  emit, cwd=stack_dir(rec))
            c1 = run_stream(["docker", "compose"] + args + ["stop"], emit, cwd=stack_dir(rec))
            c2 = run_stream(["docker", "compose"] + args + ["up", "-d"], emit, cwd=stack_dir(rec))
            return c2 if c2 != 0 else c1
        return _op

    return lambda emit: _fail(emit, "未知操作：%s" % op)


def destroy_user_stacks(rec, emit=None):
    """删除用户全部容器栈（down -v）、网络与 stacks/<用户>/ 目录。"""
    failed = []
    d = stack_dir(rec)
    if os.path.isdir(d):
        for fn in os.listdir(d):
            if not fn.startswith("docker-compose.") or not fn.endswith(".yml"):
                continue
            comp = fn[len("docker-compose."):-len(".yml")]
            args, _ = stack_compose_args(rec, comp)
            if not args:
                continue
            if emit:
                emit("[INFO] 销毁用户 %s 的 %s 栈\n" % (rec["username"], comp))
            cmd = ["docker", "compose"] + args + ["down", "-v"]
            if emit:
                code = run_stream(cmd, emit, cwd=d)
            else:
                ok, _, _err = run_cmd(cmd, cwd=d, timeout=120)
                code = 0 if ok else 1
            if code != 0:
                failed.append(comp)
    r = subprocess.run(["docker", "network", "inspect", user_network(rec)], capture_output=True)
    if r.returncode == 0:
        subprocess.run(["docker", "network", "rm", user_network(rec)], capture_output=True)
    if os.path.isdir(d):
        shutil.rmtree(d, ignore_errors=True)
    return failed


# ============================================================
# 管理员：用户管理接口
# ============================================================
def public_user(rec):
    return {"uid": rec["uid"], "username": rec["username"], "role": rec["role"],
            "port_base": rec["port_base"], "created": rec.get("created", ""),
            "disabled": bool(rec.get("disabled"))}


def api_admin_users_list():
    with USERS_LOCK:
        items = [public_user(u) for u in USERS["users"]]
    for it in items:
        d = os.path.join(STACK_ROOT, it["username"])
        it["stacks"] = sorted(fn[len("docker-compose."):-len(".yml")]
                              for fn in os.listdir(d)
                              if fn.startswith("docker-compose.") and fn.endswith(".yml")) \
            if os.path.isdir(d) else []
    return {"ok": True, "users": items}


def api_admin_user_create(body):
    b = body or {}
    rec, err = create_user(b.get("username", ""), b.get("password", ""), b.get("role", "user"))
    if not rec:
        return {"ok": False, "error": err}
    return {"ok": True, "user": public_user(rec)}


def api_admin_user_password(body):
    b = body or {}
    username = (b.get("username") or "").strip()
    if not get_user(username):
        return {"ok": False, "error": "用户不存在"}
    ok, err = change_password(username, b.get("password", ""))
    if not ok:
        return {"ok": False, "error": err}
    return {"ok": True, "output": "已重置 %s 的密码（其所有会话已失效）" % username}


def api_admin_user_disable(body):
    b = body or {}
    username = (b.get("username") or "").strip()
    rec = get_user(username)
    if not rec:
        return {"ok": False, "error": "用户不存在"}
    disabled = bool(b.get("disabled", True))
    if rec["role"] == "admin" and disabled:
        with USERS_LOCK:
            admins = [u for u in USERS["users"] if u["role"] == "admin" and not u.get("disabled")]
        if len(admins) <= 1:
            return {"ok": False, "error": "不能禁用唯一的管理员"}
    with USERS_LOCK:
        for u in USERS["users"]:
            if u["username"] == username:
                u["disabled"] = disabled
    save_users()
    if disabled:
        invalidate_sessions(uid=rec["uid"])
    return {"ok": True, "output": "%s 已%s" % (username, "禁用" if disabled else "启用")}


def api_admin_user_delete(body):
    b = body or {}
    username = (b.get("username") or "").strip()
    rec = get_user(username)
    if not rec:
        return {"ok": False, "error": "用户不存在"}
    if rec["role"] == "admin":
        with USERS_LOCK:
            admins = [u for u in USERS["users"] if u["role"] == "admin"]
        if len(admins) <= 1:
            return {"ok": False, "error": "不能删除唯一的管理员"}
    failed = []
    if b.get("destroy_stacks"):
        failed = destroy_user_stacks(rec)
    with USERS_LOCK:
        USERS["users"] = [u for u in USERS["users"] if u["username"] != username]
    save_users()
    invalidate_sessions(uid=rec["uid"])
    msg = "已删除用户 %s" % username
    if b.get("destroy_stacks"):
        msg += "（容器栈已销毁%s）" % ("，失败组件：" + ",".join(failed) if failed else "")
    return {"ok": True, "output": msg}
# ============================================================
# 路由表（通用 Docker 管理，仅管理员可用）
# ============================================================
ROUTES = {
    "ping": lambda b: api_ping(),
    "containers": lambda b: api_containers(),
    "images": lambda b: api_images(),
    "run": api_run, "pull": api_pull, "logs": api_logs, "inspect": api_inspect,
    "imageremove": api_image_remove,
    "start": lambda b: api_container_action("start", b),
    "stop": lambda b: api_container_action("stop", b),
    "restart": lambda b: api_container_action("restart", b),
    "kill": lambda b: api_container_action("kill", b),
    "pause": lambda b: api_container_action("pause", b),
    "unpause": lambda b: api_container_action("unpause", b),
    "remove": lambda b: api_container_action("remove", b),
}

TOKEN_ADMIN = {"uid": 0, "username": "(token)", "role": "admin"}


class Handler(BaseHTTPRequestHandler):
    # ---- 鉴权：会话 Cookie 优先；设置了 RELAY_TOKEN 且请求带正确 token 时视作管理员 ----
    def _sid(self):
        try:
            c = SimpleCookie(self.headers.get("Cookie", ""))
            if "sid" in c:
                return c["sid"].value
        except Exception:
            pass
        qs = parse_qs(urlparse(self.path).query)
        return (qs.get("sid") or [""])[0]

    def _current(self):
        """返回当前身份 dict 或 None。"""
        u = session_user(self._sid())
        if u:
            return u
        if TOKEN:
            t = self.headers.get("X-Relay-Token", "")
            if not t:
                qs = parse_qs(urlparse(self.path).query)
                t = (qs.get("token") or [""])[0]
            if t == TOKEN:
                return dict(TOKEN_ADMIN)
        return None

    def _require(self, role=None):
        """返回 (身份, 错误响应)。身份为 None 时已写好 401/403 响应。"""
        cur = self._current()
        if not cur:
            self._send(401, {"ok": False, "error": "未登录，请先访问 /login"})
            return None, True
        if role == "admin" and cur.get("role") != "admin":
            self._send(403, {"ok": False, "error": "需要管理员权限"})
            return None, True
        return cur, None

    def _send(self, code, obj, set_cookie=None):
        data = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        if set_cookie:
            self.send_header("Set-Cookie", set_cookie)
        self.end_headers()
        self.wfile.write(data)

    def _send_file(self, path):
        if os.path.exists(path):
            data = open(path, "rb").read()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(data)
        else:
            self._send(404, {"ok": False, "error": "页面文件不存在"})

    def _send_asset(self, path, content_type):
        if not os.path.exists(path):
            return self._send(404, {"ok": False, "error": "静态资源不存在"})
        with open(path, "rb") as f:
            data = f.read()
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "public, max-age=86400")
        self.end_headers()
        self.wfile.write(data)

    def _handle_term_ws(self, qs):
        """全交互终端 WebSocket 端点：复用逐命令终端的容器归属校验。"""
        if self.headers.get("Upgrade", "").lower() != "websocket":
            return self._send(400, {"ok": False, "error": "需要 WebSocket 升级请求"})
        if not self.headers.get("Sec-WebSocket-Key"):
            return self._send(400, {"ok": False, "error": "缺少 Sec-WebSocket-Key"})
        # 会话 Cookie 为 SameSite=Lax，跨站握手不会携带 sid，_require 会直接 401。
        cur, err = self._require()
        if err:
            return
        rec = get_user(cur["username"])
        if not rec:
            return self._send(401, {"ok": False, "error": "账号已不存在"})
        if rec.get("disabled"):
            return self._send(403, {"ok": False, "error": "账号已被禁用"})
        container = (qs.get("container") or [""])[0].strip()
        allowed, why = user_container_allowed(rec, container)
        if not allowed:
            return self._send(403, {"ok": False, "error": why})
        return run_interactive_term(self, container)

    def _read_body(self):
        try:
            n = int(self.headers.get("Content-Length", 0))
            if n:
                return json.loads(self.rfile.read(n).decode("utf-8"))
        except Exception:
            pass
        return {}

    def _task_result(self, tid, cur):
        task = TASKS.get(tid)
        if not task:
            return self._send(404, {"ok": False, "error": "任务不存在"})
        if cur.get("role") != "admin" and task.get("owner") != cur.get("uid"):
            return self._send(403, {"ok": False, "error": "无权查看该任务"})
        return self._send(200, {"ok": True, "running": task["running"],
                                "code": task["code"], "output": "".join(task["out"])})

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    # ---- GET ----
    def do_GET(self):
        u = urlparse(self.path)
        path = u.path
        qs = parse_qs(u.query)

        # 页面（鉴权由页面内 JS 调 /api/auth/me 后跳转完成）
        if path == "/login":
            return self._send_file(LOGIN_PAGE)
        if path == "/portal":
            return self._send_file(PORTAL_PAGE)
        if path == "/users":
            return self._send_file(ADMIN_USERS_PAGE)
        if path == "/terminal":
            return self._send_file(TERMINAL_PAGE)
        if path in ("/vendor/xterm.min.js", "/vendor/xterm.min.css"):
            ctype = ("application/javascript; charset=utf-8" if path.endswith(".js")
                     else "text/css; charset=utf-8")
            return self._send_asset(os.path.join(VENDOR_DIR, os.path.basename(path)), ctype)
        if path in ("/", "/index.html", "/docker-manager.html"):
            return self._send_file(INDEX)
        if path in ("/bigdata", "/bigdata.html"):
            return self._send_file(BIGDATA_INDEX)

        # ---- API ----
        if path == "/api/auth/me":
            cur = self._current()
            if not cur:
                return self._send(401, {"ok": False, "error": "未登录"})
            return self._send(200, {"ok": True, "username": cur["username"],
                                    "role": cur["role"], "uid": cur.get("uid")})

        if path == "/api/portal/term-ws":
            return self._handle_term_ws(qs)

        if path == "/api/portal/stacks":
            cur, err = self._require()
            if err:
                return
            rec = get_user(cur["username"])
            if not rec:
                return self._send(401, {"ok": False, "error": "账号已不存在"})
            return self._send(200, api_portal_stacks(rec))

        if path.startswith("/api/portal/task/"):
            cur, err = self._require()
            if err:
                return
            return self._task_result(path[len("/api/portal/task/"):], cur)

        if path.startswith("/api/bigdata/task/"):
            cur, err = self._require("admin")
            if err:
                return
            return self._task_result(path[len("/api/bigdata/task/"):], cur)

        if path == "/api/bigdata/status":
            cur, err = self._require("admin")
            if err:
                return
            component = (qs.get("component") or ["all"])[0]
            arch = (qs.get("arch") or ["single"])[0]
            return self._send(200, api_bigdata_status(component, arch))

        if path.startswith("/api/admin/"):
            cur, err = self._require("admin")
            if err:
                return
            if path == "/api/admin/users":
                return self._send(200, api_admin_users_list())
            return self._send(404, {"ok": False, "error": "未知接口: " + path})

        if path.startswith("/api/"):
            cur, err = self._require("admin")
            if err:
                return
            name = path[len("/api/"):]
            fn = ROUTES.get(name)
            if fn:
                return self._send(200, fn({}))
            return self._send(404, {"ok": False, "error": "未知接口: " + name})

        self._send(404, {"ok": False, "error": "not found"})

    # ---- POST ----
    def do_POST(self):
        u = urlparse(self.path)
        path = u.path

        # 登录（无需鉴权）
        if path == "/api/auth/login":
            body = self._read_body()
            username = (body.get("username") or "").strip()
            rec = verify_login(username, body.get("password") or "")
            if not rec:
                time.sleep(0.6)  # 失败延迟，减缓暴力破解
                return self._send(401, {"ok": False, "error": "用户名或密码错误（账号也可能被禁用）"})
            sid = new_session(rec)
            cookie = "sid=%s; Path=/; HttpOnly; Max-Age=%d; SameSite=Lax" % (sid, SESSION_TTL)
            return self._send(200, {"ok": True, "username": rec["username"],
                                    "role": rec["role"], "uid": rec["uid"]}, set_cookie=cookie)

        if path == "/api/auth/logout":
            sid = self._sid()
            invalidate_sessions(sid=sid)
            return self._send(200, {"ok": True,
                                    "output": "已退出登录"},
                              set_cookie="sid=; Path=/; Max-Age=0; SameSite=Lax")

        # 自助修改密码
        if path == "/api/auth/password":
            cur, err = self._require()
            if err:
                return
            body = self._read_body()
            rec = verify_login(cur["username"], body.get("old") or "")
            if not rec:
                return self._send(400, {"ok": False, "error": "原密码错误"})
            ok, msg = change_password(cur["username"], body.get("new") or "")
            if not ok:
                return self._send(400, {"ok": False, "error": msg})
            return self._send(200, {"ok": True, "output": "密码已修改，请重新登录"},
                              set_cookie="sid=; Path=/; Max-Age=0; SameSite=Lax")

        # 用户门户：操作自己的容器栈
        if path == "/api/portal/exec":
            cur, err = self._require()
            if err:
                return
            rec = get_user(cur["username"])
            if not rec:
                return self._send(401, {"ok": False, "error": "账号已不存在"})
            if rec.get("disabled"):
                return self._send(403, {"ok": False, "error": "账号已被禁用"})
            body = self._read_body()
            op = body.get("op", "")
            component = body.get("component", "")
            tail = body.get("tail", 200)
            if op not in ("start", "stop", "restart", "destroy", "clean", "logs"):
                return self._send(400, {"ok": False, "error": "未知操作：" + op})
            if component not in COMPONENTS:
                return self._send(400, {"ok": False, "error": "无效组件：" + component})
            tid = start_task(build_portal_run_fn(rec, op, component, tail), owner=rec["uid"])
            return self._send(200, {"ok": True, "task_id": tid})

        # 用户门户：在自己的容器内执行命令（Web 终端）
        if path == "/api/portal/exec-container":
            cur, err = self._require()
            if err:
                return
            rec = get_user(cur["username"])
            if not rec:
                return self._send(401, {"ok": False, "error": "账号已不存在"})
            if rec.get("disabled"):
                return self._send(403, {"ok": False, "error": "账号已被禁用"})
            return self._send(200, api_portal_exec_container(rec, self._read_body()))

        # 管理员：用户管理
        if path.startswith("/api/admin/users"):
            cur, err = self._require("admin")
            if err:
                return
            body = self._read_body()
            if path == "/api/admin/users":
                return self._send(200, api_admin_user_create(body))
            if path == "/api/admin/users/password":
                return self._send(200, api_admin_user_password(body))
            if path == "/api/admin/users/disable":
                return self._send(200, api_admin_user_disable(body))
            if path == "/api/admin/users/delete":
                return self._send(200, api_admin_user_delete(body))
            return self._send(404, {"ok": False, "error": "未知接口: " + path})

        # 管理员：大数据平台 / 通用 Docker 操作
        if path == "/api/bigdata/exec":
            cur, err = self._require("admin")
            if err:
                return
            body = self._read_body()
            op = body.get("op", "")
            component = body.get("component", "all")
            arch = body.get("arch", "single")
            tail = body.get("tail", 200)
            if op not in ("build-base", "build", "delete", "start", "stop", "destroy",
                          "restart", "clean", "logs", "test", "supervisor",
                          "clean-all", "clean-volumes"):
                return self._send(400, {"ok": False, "error": "未知操作：" + op})
            if arch not in ("single", "multi"):
                return self._send(400, {"ok": False, "error": "无效架构：" + arch})
            if arch == "single" and component not in COMPONENTS:
                return self._send(400, {"ok": False, "error": "无效组件：" + component})
            tid = start_task(build_run_fn(op, component, arch, tail), owner="admin")
            return self._send(200, {"ok": True, "task_id": tid})

        if path == "/api/bigdata/exec-shell":
            cur, err = self._require("admin")
            if err:
                return
            return self._send(200, api_exec_shell(self._read_body()))

        if path.startswith("/api/"):
            cur, err = self._require("admin")
            if err:
                return
            name = path[len("/api/"):]
            fn = ROUTES.get(name)
            if not fn:
                return self._send(404, {"ok": False, "error": "未知接口: " + name})
            try:
                self._send(200, fn(self._read_body()))
            except Exception as e:
                self._send(500, {"ok": False, "error": str(e)})
            return

        self._send(404, {"ok": False, "error": "not found"})

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    load_users()
    bootstrap_admin()
    print("Docker 管理器已启动（多用户版）")
    print("  登录页：  http://127.0.0.1:%d/login" % PORT)
    print("  本机：    http://127.0.0.1:%d" % PORT)
    print("  大数据：  http://127.0.0.1:%d/bigdata" % PORT)
    print("  用户门户：http://127.0.0.1:%d/portal" % PORT)
    if HOST == "0.0.0.0":
        print("  监听：    0.0.0.0（局域网可访问）")
        for ip in get_lan_ips():
            print("  局域网：  http://%s:%d/login" % (ip, PORT))
    else:
        print("  监听：    %s（仅本机）" % HOST)
    if TOKEN:
        print("  访问令牌：RELAY_TOKEN 已设置（带 X-Relay-Token 的请求视作管理员）")
    print("  项目目录：%s" % PROJECT_DIR)
    print("按 Ctrl+C 停止")
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n已停止")
        server.shutdown()
