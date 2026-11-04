#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Docker / 大数据平台管理器 - 本地转发脚本（零依赖，仅 Python 标准库）
作用：浏览器页面无法直接访问 Docker，本脚本把前端请求翻译成 docker/docker-compose 命令执行并回传结果。
只监听 127.0.0.1，不对外暴露，安全。

用法：
    python docker-relay.py [端口]        # 默认 8000
然后浏览器打开：
    http://127.0.0.1:8000             # 通用 Docker 管理器
    http://127.0.0.1:8000/bigdata     # 大数据平台管理器

大数据平台项目目录默认取本脚本的上一级目录（compose/dockerfile 所在），
可通过环境变量 BIGDATA_PROJECT_DIR 覆盖。
"""
import json
import os
import re
import shlex
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
HERE = os.path.dirname(os.path.abspath(__file__))
INDEX = os.path.join(HERE, "docker-manager.html")
BIGDATA_INDEX = os.path.join(HERE, "bigdata-manager.html")
PROJECT_DIR = os.environ.get("BIGDATA_PROJECT_DIR") or os.path.dirname(HERE)


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
              "kafka", "spark", "flink", "flume", "mysql"]
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


def start_task(run_fn):
    with TASK_LOCK:
        TASK_SEQ[0] += 1
        tid = str(TASK_SEQ[0])
    task = {"id": tid, "running": True, "code": None, "out": []}
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
# 路由表
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


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, obj):
        data = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()
        self.wfile.write(data)

    def _send_file(self, path):
        if os.path.exists(path):
            data = open(path, "rb").read()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        else:
            self._send(404, {"ok": False, "error": "页面文件不存在"})

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        u = urlparse(self.path)
        path = u.path
        qs = parse_qs(u.query)

        if path in ("/", "/index.html", "/docker-manager.html"):
            return self._send_file(INDEX)
        if path in ("/bigdata", "/bigdata.html"):
            return self._send_file(BIGDATA_INDEX)

        if path.startswith("/api/bigdata/task/"):
            tid = path[len("/api/bigdata/task/"):]
            task = TASKS.get(tid)
            if not task:
                return self._send(404, {"ok": False, "error": "任务不存在"})
            return self._send(200, {"ok": True, "running": task["running"],
                                    "code": task["code"], "output": "".join(task["out"])})

        if path == "/api/bigdata/status":
            component = (qs.get("component") or ["all"])[0]
            arch = (qs.get("arch") or ["single"])[0]
            return self._send(200, api_bigdata_status(component, arch))

        if path.startswith("/api/"):
            name = path[len("/api/"):]
            fn = ROUTES.get(name)
            if fn:
                return self._send(200, fn({}))
            return self._send(404, {"ok": False, "error": "未知接口: " + name})

        self._send(404, {"ok": False, "error": "not found"})

    def do_POST(self):
        u = urlparse(self.path)
        path = u.path

        if path == "/api/bigdata/exec":
            body = {}
            try:
                n = int(self.headers.get("Content-Length", 0))
                if n:
                    body = json.loads(self.rfile.read(n).decode("utf-8"))
            except Exception:
                body = {}
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
            tid = start_task(build_run_fn(op, component, arch, tail))
            return self._send(200, {"ok": True, "task_id": tid})

        if path == "/api/bigdata/exec-shell":
            body = {}
            try:
                n = int(self.headers.get("Content-Length", 0))
                if n:
                    body = json.loads(self.rfile.read(n).decode("utf-8"))
            except Exception:
                body = {}
            return self._send(200, api_exec_shell(body))

        if not path.startswith("/api/"):
            return self._send(404, {"ok": False, "error": "not found"})

        name = path[len("/api/"):]
        fn = ROUTES.get(name)
        if not fn:
            return self._send(404, {"ok": False, "error": "未知接口: " + name})
        body = {}
        try:
            n = int(self.headers.get("Content-Length", 0))
            if n:
                body = json.loads(self.rfile.read(n).decode("utf-8"))
        except Exception:
            body = {}
        try:
            self._send(200, fn(body))
        except Exception as e:
            self._send(500, {"ok": False, "error": str(e)})

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    print("Docker 管理器已启动： http://127.0.0.1:%d" % PORT)
    print("大数据平台管理器： http://127.0.0.1:%d/bigdata" % PORT)
    print("项目目录： %s" % PROJECT_DIR)
    print("按 Ctrl+C 停止")
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n已停止")
        server.shutdown()
