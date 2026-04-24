#!/usr/bin/env python3
import sys
import os
import xml.etree.ElementTree as ET
from PyQt5.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QSplitter, QListWidget, QListWidgetItem, QTableWidget,
    QTableWidgetItem, QHeaderView, QComboBox, QLineEdit,
    QLabel, QPushButton, QMessageBox, QGroupBox,
    QAbstractItemView, QDialog, QFormLayout, QDialogButtonBox,
    QInputDialog, QSpinBox, QTextEdit
)
from PyQt5.QtCore import Qt, QSize
from PyQt5.QtGui import QColor, QFont

from config_data import DESCRIPTIONS, PRESET_ITEMS, CORE_ITEMS

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG_DIR = os.path.join(PROJECT_ROOT, "config")
WORK_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "output")

COMPONENTS = {
    "hadoop": {
        "label": "Hadoop",
        "subdir": "hadoop",
        "files": ["core-site.xml", "hdfs-site.xml", "mapred-site.xml", "yarn-site.xml", "workers"],
    },
    "hadoop-ha": {
        "label": "Hadoop HA",
        "subdir": "hadoop-ha",
        "files": ["core-site.xml", "hdfs-site.xml", "mapred-site.xml", "yarn-site.xml", "workers"],
    },
    "zookeeper": {
        "label": "ZooKeeper",
        "subdir": "zookeeper",
        "files": ["zoo.cfg"],
    },
    "hbase": {
        "label": "HBase",
        "subdir": "hbase",
        "files": ["hbase-site.xml", "regionservers"],
    },
    "hive": {
        "label": "Hive",
        "subdir": "hive",
        "files": ["hive-site.xml"],
    },
    "kafka": {
        "label": "Kafka",
        "subdir": "kafka",
        "files": ["server.properties", "server2.properties", "server3.properties"],
    },
    "spark": {
        "label": "Spark",
        "subdir": "spark",
        "files": ["spark-defaults.conf", "spark-env.sh", "slaves"],
    },
    "flink": {
        "label": "Flink",
        "subdir": "flink",
        "files": ["flink-conf.yaml", "workers"],
    },
    "flume": {
        "label": "Flume",
        "subdir": "flume",
        "files": ["flume-kafka.conf"],
    },
    "mysql": {
        "label": "MySQL",
        "subdir": "mysql",
        "files": ["my.cnf"],
    },
}

FILE_TYPE_MAP = {
    ".xml": "xml",
    ".properties": "properties",
    ".sh": "shell",
    ".conf": "key_value",
    ".cfg": "key_value",
    ".cnf": "ini",
    ".yaml": "yaml",
    ".yml": "yaml",
}

SPARK_CONF_FILES = {"spark-defaults.conf"}

KNOWN_ENUMS = {
    "hbase.cluster.distributed": ["true", "false"],
    "dfs.permissions.enabled": ["true", "false"],
    "dfs.ha.automatic-failover.enabled": ["true", "false"],
    "spark.eventLog.enabled": ["true", "false"],
    "spark.dynamicAllocation.enabled": ["true", "false"],
    "spark.shuffle.service.enabled": ["true", "false"],
    "spark.speculation": ["true", "false"],
    "hive.exec.dynamic.partition": ["true", "false"],
    "hive.exec.dynamic.partition.mode": ["strict", "nonstrict"],
    "hive.server2.enable.doAs": ["true", "false"],
    "hive.stats.autogather": ["true", "false"],
    "hive.stats.column.autogather": ["true", "false"],
    "hive.compute.query.using.stats": ["true", "false"],
    "hive.support.concurrency": ["true", "false"],
    "hive.server2.tez.initialize.default.sessions": ["true", "false"],
    "hive.metastore.event.db.notification.api.auth": ["true", "false"],
    "hive.auto.convert.join": ["true", "false"],
    "hive.exec.parallel": ["true", "false"],
    "hive.map.aggr": ["true", "false"],
    "hive.groupby.skewindata": ["true", "false"],
    "hive.merge.mapfiles": ["true", "false"],
    "hive.merge.mapredfiles": ["true", "false"],
    "delete.topic.enable": ["true", "false"],
    "auto.create.topics.enable": ["true", "false"],
    "spark.serializer": [
        "org.apache.spark.serializer.KryoSerializer",
        "org.apache.spark.serializer.JavaSerializer",
    ],
    "state.backend": ["hashmap", "rocksdb", "memory", "fs"],
    "high-availability": ["none", "zookeeper"],
    "classloader.resolve-order": ["parent-first", "child-first"],
    "web.submit.enable": ["true", "false"],
    "hbase.unsafe.stream.capability.enforce": ["true", "false"],
    "hive.execution.engine": ["mr", "tez", "spark"],
    "hadoop.security.authentication": ["simple", "kerberos"],
    "hadoop.security.authorization": ["true", "false"],
    "mapreduce.framework.name": ["yarn", "local", "classic"],
    "hive.server2.authentication": ["NONE", "KERBEROS", "LDAP", "CUSTOM"],
    "hive.server2.transport.mode": ["binary", "http"],
    "hive.metastore.db.type": ["mysql", "postgres", "derby"],
    "yarn.resourcemanager.ha.enabled": ["true", "false"],
    "yarn.resourcemanager.recovery.enabled": ["true", "false"],
    "yarn.nodemanager.vmem-check-enabled": ["true", "false"],
    "yarn.nodemanager.pmem-check-enabled": ["true", "false"],
    "yarn.log-aggregation-enable": ["true", "false"],
    "innodb_file_per_table": ["ON", "OFF"],
    "slow_query_log": ["ON", "OFF"],
    "log.cleanup.policy": ["delete", "compact"],
    "execution.checkpointing.mode": ["EXACTLY_ONCE", "AT_LEAST_ONCE"],
    "restart-strategy": ["fixed-delay", "failure-rate", "none"],
    "spark.scheduler.mode": ["FIFO", "FAIR"],
}


def detect_file_type(filename):
    _, ext = os.path.splitext(filename)
    if filename in SPARK_CONF_FILES:
        return "spark_conf"
    if ext in FILE_TYPE_MAP:
        return FILE_TYPE_MAP[ext]
    if filename in ("workers", "regionservers", "slaves"):
        return "plain_list"
    return "key_value"


def _create_template(filepath, file_type):
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    if file_type == "xml":
        with open(filepath, "w", encoding="utf-8") as f:
            f.write('<?xml version="1.0" encoding="UTF-8"?>\n')
            f.write("<configuration>\n")
            f.write("</configuration>\n")
    elif file_type == "properties":
        with open(filepath, "w", encoding="utf-8") as f:
            pass
    elif file_type == "shell":
        with open(filepath, "w", encoding="utf-8") as f:
            f.write("#!/bin/bash\n")
    elif file_type == "spark_conf":
        with open(filepath, "w", encoding="utf-8") as f:
            pass
    elif file_type == "ini":
        with open(filepath, "w", encoding="utf-8") as f:
            f.write("[mysqld]\n")
    elif file_type in ("yaml", "yml"):
        with open(filepath, "w", encoding="utf-8") as f:
            pass
    elif file_type == "plain_list":
        with open(filepath, "w", encoding="utf-8") as f:
            pass
    elif file_type == "plain_text":
        with open(filepath, "w", encoding="utf-8") as f:
            pass
    elif file_type == "key_value":
        with open(filepath, "w", encoding="utf-8") as f:
            pass


def _ensure_workspace_file(component, filename, file_type=None):
    comp_info = COMPONENTS[component]
    subdir = comp_info["subdir"]
    work_path = os.path.join(WORK_DIR, subdir, filename)
    if os.path.isfile(work_path):
        return work_path
    if not file_type:
        file_type = detect_file_type(filename)
    config_path = os.path.join(CONFIG_DIR, subdir, filename)
    if os.path.isfile(config_path):
        import shutil
        os.makedirs(os.path.dirname(work_path), exist_ok=True)
        shutil.copy2(config_path, work_path)
        return work_path
    _create_template(work_path, file_type)
    return work_path


def parse_xml(filepath):
    tree = ET.parse(filepath)
    root = tree.getroot()
    items = []
    for prop in root.findall("property"):
        name_elem = prop.find("name")
        value_elem = prop.find("value")
        desc_elem = prop.find("description")
        name = name_elem.text.strip() if name_elem is not None and name_elem.text else ""
        value = value_elem.text.strip() if value_elem is not None and value_elem.text else ""
        desc = desc_elem.text.strip() if desc_elem is not None and desc_elem.text else ""
        items.append({"name": name, "value": value, "description": desc})
    return items


def build_xml(items, original_filepath):
    tree = ET.parse(original_filepath)
    root = tree.getroot()
    existing = {}
    for prop in root.findall("property"):
        name_elem = prop.find("name")
        if name_elem is not None and name_elem.text:
            existing[name_elem.text.strip()] = prop
    item_map = {it["name"]: it["value"] for it in items}
    for name in list(existing.keys()):
        if name not in item_map:
            root.remove(existing[name])
    for item in items:
        name = item["name"]
        value = item["value"]
        if name in existing:
            value_elem = existing[name].find("value")
            if value_elem is not None:
                value_elem.text = value
            else:
                ET.SubElement(existing[name], "value").text = value
        else:
            prop = ET.SubElement(root, "property")
            ET.SubElement(prop, "name").text = name
            ET.SubElement(prop, "value").text = value
    return tree


def parse_key_value_file(filepath, seps=("=", ":")):
    items = []
    with open(filepath, "r", encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            for sep in seps:
                if sep in stripped:
                    key, _, val = stripped.partition(sep)
                    items.append({"name": key.strip(), "value": val.strip(), "description": "", "sep": sep})
                    break
    return items


def build_key_value_file(items, original_filepath):
    with open(original_filepath, "r", encoding="utf-8") as f:
        original_lines = f.readlines()
    item_map = {it["name"]: it for it in items}
    new_items_added = set()
    new_lines = []
    for line in original_lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            new_lines.append(line)
            continue
        sep = None
        key = None
        for s in (":", "="):
            if s in stripped:
                key, _, _ = stripped.partition(s)
                key = key.strip()
                sep = s
                break
        if key and key in item_map:
            new_items_added.add(key)
            indent = line[:len(line) - len(line.lstrip())]
            new_lines.append(f"{indent}{key}{sep}{item_map[key]['value']}\n")
        else:
            new_lines.append(line)
    for it in items:
        if it["name"] not in new_items_added:
            sep = it.get("sep", "=")
            new_lines.append(f"{it['name']}{sep}{it['value']}\n")
    return "".join(new_lines)


def parse_properties(filepath):
    return parse_key_value_file(filepath, seps=("=",))


def build_properties(items, original_filepath):
    return build_key_value_file(items, original_filepath)


def parse_shell(filepath):
    items = []
    with open(filepath, "r", encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            had_export = False
            if stripped.startswith("export "):
                had_export = True
                stripped = stripped[len("export "):]
            if "=" in stripped:
                key, _, val = stripped.partition("=")
                items.append({"name": key.strip(), "value": val.strip(), "description": "", "export": had_export})
    return items


def build_shell(items, original_filepath):
    with open(original_filepath, "r", encoding="utf-8") as f:
        original_lines = f.readlines()
    item_map = {it["name"]: it for it in items}
    new_items_added = set()
    new_lines = []
    for line in original_lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            new_lines.append(line)
            continue
        check = stripped
        had_export = False
        if check.startswith("export "):
            had_export = True
            check = check[len("export "):]
        if "=" in check:
            key, _, _ = check.partition("=")
            key = key.strip()
            if key in item_map:
                new_items_added.add(key)
                prefix = "export " if item_map[key].get("export", had_export) else ""
                new_lines.append(f"{prefix}{key}={item_map[key]['value']}\n")
            else:
                new_lines.append(line)
        else:
            new_lines.append(line)
    for it in items:
        if it["name"] not in new_items_added:
            prefix = "export " if it.get("export", True) else ""
            new_lines.append(f"{prefix}{it['name']}={it['value']}\n")
    return "".join(new_lines)


def parse_spark_conf(filepath):
    items = []
    with open(filepath, "r", encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            parts = stripped.split(None, 1)
            if len(parts) >= 2:
                items.append({"name": parts[0], "value": parts[1], "description": ""})
            elif len(parts) == 1:
                items.append({"name": parts[0], "value": "", "description": ""})
    return items


def build_spark_conf(items, original_filepath):
    with open(original_filepath, "r", encoding="utf-8") as f:
        original_lines = f.readlines()
    item_map = {it["name"]: it["value"] for it in items}
    new_items_added = set()
    new_lines = []
    for line in original_lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            new_lines.append(line)
            continue
        parts = stripped.split(None, 1)
        if len(parts) >= 1:
            key = parts[0]
            if key in item_map:
                new_items_added.add(key)
                indent = line[:len(line) - len(line.lstrip())]
                new_lines.append(f"{indent}{key:<40s}{item_map[key]}\n")
            else:
                new_lines.append(line)
        else:
            new_lines.append(line)
    for it in items:
        if it["name"] not in new_items_added:
            new_lines.append(f"{it['name']:<40s}{it['value']}\n")
    return "".join(new_lines)


def parse_ini(filepath):
    items = []
    current_section = ""
    with open(filepath, "r", encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            if stripped.startswith("[") and stripped.endswith("]"):
                current_section = stripped[1:-1].strip()
                continue
            if "=" in stripped:
                key, _, val = stripped.partition("=")
                items.append({
                    "name": key.strip(), "value": val.strip(),
                    "description": "", "section": current_section,
                })
            elif stripped:
                items.append({
                    "name": stripped, "value": "",
                    "description": "", "section": current_section, "flag": True,
                })
    return items


def build_ini(items, original_filepath):
    with open(original_filepath, "r", encoding="utf-8") as f:
        original_lines = f.readlines()
    item_map = {}
    for it in items:
        sec = it.get("section", "")
        key = it.get("name", "")
        item_map[(sec, key)] = it
    new_lines = []
    current_section = ""
    for line in original_lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            new_lines.append(line)
            continue
        if stripped.startswith("[") and stripped.endswith("]"):
            current_section = stripped[1:-1].strip()
            new_lines.append(line)
            continue
        if "=" in stripped:
            key, _, _ = stripped.partition("=")
            key = key.strip()
            lookup = (current_section, key)
            if lookup in item_map:
                indent = line[:len(line) - len(line.lstrip())]
                new_lines.append(f"{indent}{key} = {item_map[lookup]['value']}\n")
            else:
                new_lines.append(line)
        else:
            new_lines.append(line)
    return "".join(new_lines)


def parse_yaml_simple(filepath):
    items = []
    with open(filepath, "r", encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            if ":" in stripped:
                key, _, val = stripped.partition(":")
                items.append({"name": key.strip(), "value": val.strip(), "description": ""})
    return items


def build_yaml_simple(items, original_filepath):
    with open(original_filepath, "r", encoding="utf-8") as f:
        original_lines = f.readlines()
    item_map = {it["name"]: it["value"] for it in items}
    new_items_added = set()
    new_lines = []
    for line in original_lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            new_lines.append(line)
            continue
        if ":" in stripped:
            key, _, _ = stripped.partition(":")
            key = key.strip()
            if key in item_map:
                new_items_added.add(key)
                indent = line[:len(line) - len(line.lstrip())]
                new_lines.append(f"{indent}{key}: {item_map[key]}\n")
            else:
                new_lines.append(line)
        else:
            new_lines.append(line)
    for it in items:
        if it["name"] not in new_items_added:
            new_lines.append(f"{it['name']}: {it['value']}\n")
    return "".join(new_lines)


def parse_plain_list(filepath):
    items = []
    with open(filepath, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                items.append({"name": line, "value": "", "description": ""})
    return items


def build_plain_list(items, original_filepath):
    with open(original_filepath, "r", encoding="utf-8") as f:
        original_lines = f.readlines()
    header_lines = []
    for line in original_lines:
        stripped = line.strip()
        if stripped.startswith("#") or not stripped:
            header_lines.append(line)
    result = list(header_lines)
    for it in items:
        result.append(it["name"] + "\n")
    return "".join(result)


def parse_plain_text(filepath):
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()
    return [{"name": "__text__", "value": content, "description": ""}]


def build_plain_text(items, original_filepath):
    for it in items:
        if it["name"] == "__text__":
            return it["value"]
    return ""


PARSERS = {
    "xml": parse_xml,
    "properties": parse_properties,
    "key_value": parse_key_value_file,
    "shell": parse_shell,
    "spark_conf": parse_spark_conf,
    "ini": parse_ini,
    "yaml": parse_yaml_simple,
    "plain_list": parse_plain_list,
    "plain_text": parse_plain_text,
}

BUILDERS = {
    "xml": build_xml,
    "properties": build_properties,
    "key_value": build_key_value_file,
    "shell": build_shell,
    "spark_conf": build_spark_conf,
    "ini": build_ini,
    "yaml": build_yaml_simple,
    "plain_list": build_plain_list,
    "plain_text": build_plain_text,
}

TYPE_LABELS = {
    "xml": "XML配置", "properties": "Properties配置",
    "key_value": "键值对配置", "shell": "Shell环境变量",
    "spark_conf": "Spark配置", "ini": "INI配置",
    "yaml": "YAML配置", "plain_list": "列表配置",
    "plain_text": "纯文本文件",
}

ALL_FILE_TYPES = [
    ("xml", "XML配置 (.xml)"),
    ("properties", "Properties配置 (.properties)"),
    ("key_value", "键值对配置 (.conf/.cfg)"),
    ("spark_conf", "Spark配置 (空格分隔)"),
    ("shell", "Shell环境变量 (.sh)"),
    ("ini", "INI配置 (.cnf/.ini)"),
    ("yaml", "YAML配置 (.yaml/.yml)"),
    ("plain_list", "列表配置 (workers/slaves等)"),
    ("plain_text", "纯文本文件 (自由编辑)"),
]


def _is_core_item(name):
    return name in CORE_ITEMS


class AddComponentDialog(QDialog):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("新增组件")
        self.setMinimumWidth(420)
        layout = QVBoxLayout(self)
        form = QFormLayout()

        self.key_edit = QLineEdit()
        self.key_edit.setPlaceholderText("英文标识，如: clickhouse，用于目录名")
        form.addRow("组件标识:", self.key_edit)

        self.label_edit = QLineEdit()
        self.label_edit.setPlaceholderText("显示名称，如: ClickHouse")
        form.addRow("组件名称:", self.label_edit)

        self.subdir_edit = QLineEdit()
        self.subdir_edit.setPlaceholderText("工作目录下的子目录名，默认与标识相同")
        form.addRow("配置目录:", self.subdir_edit)

        layout.addLayout(form)

        buttons = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        buttons.accepted.connect(self._validate_and_accept)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)

    def _validate_and_accept(self):
        key = self.key_edit.text().strip()
        if not key:
            QMessageBox.warning(self, "提示", "组件标识不能为空")
            return
        if key in COMPONENTS:
            QMessageBox.warning(self, "提示", f"组件标识 '{key}' 已存在")
            return
        if not self.label_edit.text().strip():
            QMessageBox.warning(self, "提示", "组件名称不能为空")
            return
        self.accept()

    def get_data(self):
        key = self.key_edit.text().strip()
        label = self.label_edit.text().strip()
        subdir = self.subdir_edit.text().strip() or key
        return {"key": key, "label": label, "subdir": subdir, "files": []}


class AddFileDialog(QDialog):
    def __init__(self, component_key, parent=None):
        super().__init__(parent)
        self.component_key = component_key
        self.setWindowTitle("新增配置文件")
        self.setMinimumWidth(480)
        layout = QVBoxLayout(self)
        form = QFormLayout()

        self.filename_edit = QLineEdit()
        self.filename_edit.setPlaceholderText("文件名，如: server.xml, application.yml")
        form.addRow("文件名:", self.filename_edit)

        self.type_combo = QComboBox()
        for type_key, type_label in ALL_FILE_TYPES:
            self.type_combo.addItem(type_label, type_key)
        self.type_combo.currentIndexChanged.connect(self._on_type_changed)
        form.addRow("文件类型:", self.type_combo)

        self.auto_detect_label = QLabel("")
        self.auto_detect_label.setStyleSheet("color: #888; font-size: 11px;")
        form.addRow("自动检测:", self.auto_detect_label)

        layout.addLayout(form)

        buttons = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        buttons.accepted.connect(self._validate_and_accept)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)

        self._on_type_changed(0)

    def _on_type_changed(self, idx):
        fname = self.filename_edit.text().strip()
        if fname:
            detected = detect_file_type(fname)
            for i, (tk, _) in enumerate(ALL_FILE_TYPES):
                if tk == detected:
                    self.auto_detect_label.setText(f"根据文件名检测为: {ALL_FILE_TYPES[i][1]}")
                    return
        self.auto_detect_label.setText("输入文件名后自动检测类型")

    def _validate_and_accept(self):
        fname = self.filename_edit.text().strip()
        if not fname:
            QMessageBox.warning(self, "提示", "文件名不能为空")
            return
        comp_info = COMPONENTS.get(self.component_key, {})
        if fname in comp_info.get("files", []):
            QMessageBox.warning(self, "提示", f"文件 '{fname}' 已存在于该组件中")
            return
        self.accept()

    def get_data(self):
        fname = self.filename_edit.text().strip()
        file_type = self.type_combo.currentData()
        return {"filename": fname, "file_type": file_type}


class AddItemDialog(QDialog):
    def __init__(self, file_type, component=None, filename=None, existing_names=None, parent=None):
        super().__init__(parent)
        self.file_type = file_type
        self.component = component
        self.filename = filename
        self.existing_names = existing_names or []
        self.setWindowTitle("新增配置项")
        self.setMinimumWidth(560)
        layout = QVBoxLayout(self)

        form = QFormLayout()

        if file_type == "plain_list":
            self.name_combo = QComboBox()
            self.name_combo.setEditable(True)
            self.name_combo.setPlaceholderText("输入主机名，如: datanode3")
            self._populate_plain_list_hints()
            self.name_combo.currentTextChanged.connect(self._on_plain_list_name_changed)
            form.addRow("主机名/条目:", self.name_combo)
        else:
            self.name_combo = QComboBox()
            self.name_combo.setEditable(True)
            self.name_combo.setPlaceholderText("选择或输入配置项名称（★ 为核心配置项）")
            self._populate_name_hints()
            self.name_combo.currentTextChanged.connect(self._on_name_changed)
            form.addRow("配置项名称:", self.name_combo)

            self.desc_preview = QLabel("")
            self.desc_preview.setWordWrap(True)
            self.desc_preview.setStyleSheet(
                "color: #666; font-size: 11px; padding: 4px 8px; "
                "background: #f8f9fa; border-radius: 3px; min-height: 20px;"
            )
            self.desc_preview.setMinimumHeight(24)
            form.addRow("配置说明:", self.desc_preview)

            self.value_edit = QLineEdit()
            self.value_edit.setPlaceholderText("输入配置值")
            form.addRow("配置值:", self.value_edit)

        if file_type == "xml":
            self.desc_edit = QLineEdit()
            self.desc_edit.setPlaceholderText("可选，将写入XML的description标签")
            form.addRow("XML说明:", self.desc_edit)

        if file_type == "shell":
            self.export_check = QComboBox()
            self.export_check.addItems(["是 (export)", "否"])
            self.export_check.setCurrentIndex(0)
            form.addRow("使用export:", self.export_check)

        layout.addLayout(form)

        buttons = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        buttons.accepted.connect(self.accept)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)

    def _populate_name_hints(self):
        preset = []
        if self.component and self.filename:
            comp_presets = PRESET_ITEMS.get(self.component, {})
            preset = comp_presets.get(self.filename, [])
        existing_set = set(self.existing_names)
        filtered = [k for k in preset if k not in existing_set]
        self.name_combo.addItem("")
        for key in filtered:
            desc = DESCRIPTIONS.get(key, "")
            core_mark = "★ " if _is_core_item(key) else ""
            if desc:
                display = f"{core_mark}{key}  —  {desc[:40]}{'...' if len(desc) > 40 else ''}"
            else:
                display = f"{core_mark}{key}"
            self.name_combo.addItem(display, key)

    def _populate_plain_list_hints(self):
        self.name_combo.addItem("")
        if "hadoop" in self.component:
            hints = ["datanode3", "datanode4", "datanode5"]
        elif "hbase" in self.component:
            hints = ["hbase-regionserver3", "hbase-regionserver4"]
        elif "spark" in self.component:
            hints = ["spark-worker2", "spark-worker3"]
        elif "flink" in self.component:
            hints = ["flink-taskmanager2", "flink-taskmanager3"]
        else:
            hints = []
        for h in hints:
            if h not in self.existing_names:
                self.name_combo.addItem(h, h)

    def _on_name_changed(self, text):
        idx = self.name_combo.currentIndex()
        key = self.name_combo.itemData(idx) if idx >= 0 else None
        if key is None:
            raw = text.strip()
            key = raw.lstrip("★ ").split("  —")[0].strip() if "  —" in raw else raw.lstrip("★ ").strip()
        desc = DESCRIPTIONS.get(key, "")
        core_mark = "★ 核心配置项 — " if _is_core_item(key) else ""
        self.desc_preview.setText(core_mark + (desc if desc else "（无预置说明，可自定义配置项）"))
        if self.file_type == "xml" and hasattr(self, "desc_edit"):
            if desc and not self.desc_edit.text().strip():
                self.desc_edit.setText(desc)

    def _on_plain_list_name_changed(self, text):
        idx = self.name_combo.currentIndex()
        key = self.name_combo.itemData(idx) if idx >= 0 else None
        if key:
            self.name_combo.setCurrentText(key)

    def get_data(self):
        if self.file_type == "plain_list":
            name = self.name_combo.currentText().strip()
            if not name:
                return None
            return {"name": name, "value": "", "description": ""}

        idx = self.name_combo.currentIndex()
        key = self.name_combo.itemData(idx) if idx >= 0 else None
        if key:
            name = key
        else:
            raw = self.name_combo.currentText().strip()
            name = raw.lstrip("★ ").split("  —")[0].strip() if "  —" in raw else raw.lstrip("★ ").strip()

        if not name:
            return None
        result = {"name": name, "value": "", "description": ""}
        if self.file_type != "plain_list":
            result["value"] = self.value_edit.text().strip()
        if self.file_type == "xml":
            result["description"] = self.desc_edit.text().strip()
        if self.file_type == "shell":
            result["export"] = self.export_check.currentIndex() == 0
        if self.file_type == "key_value":
            result["sep"] = "="
        return result


class ConfigEditorWidget(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.current_items = []
        self.current_file_type = None
        self.current_filepath = None
        self.current_component = None
        self.current_filename = None
        self.is_modified = False
        self._init_ui()

    def _init_ui(self):
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(6)

        top_bar = QHBoxLayout()
        self.info_label = QLabel("请选择组件和配置文件")
        self.info_label.setStyleSheet(
            "font-size: 13px; color: #555; padding: 6px; "
            "background: #f0f4f8; border-radius: 4px;"
        )
        top_bar.addWidget(self.info_label, 1)

        self.btn_add = QPushButton("➕ 新增配置项")
        self.btn_add.setStyleSheet(
            "QPushButton { background: #27ae60; color: white; padding: 6px 14px; "
            "border-radius: 4px; font-weight: bold; }"
            "QPushButton:hover { background: #219a52; }"
        )
        self.btn_add.clicked.connect(self._add_item)
        self.btn_add.setEnabled(False)
        top_bar.addWidget(self.btn_add)

        self.btn_delete = QPushButton("🗑 删除选中项")
        self.btn_delete.setStyleSheet(
            "QPushButton { background: #e74c3c; color: white; padding: 6px 14px; "
            "border-radius: 4px; font-weight: bold; }"
            "QPushButton:hover { background: #c0392b; }"
        )
        self.btn_delete.clicked.connect(self._delete_item)
        self.btn_delete.setEnabled(False)
        top_bar.addWidget(self.btn_delete)

        layout.addLayout(top_bar)

        self.stacked = QWidget()
        self.stacked_layout = QVBoxLayout(self.stacked)
        self.stacked_layout.setContentsMargins(0, 0, 0, 0)

        self.table = QTableWidget()
        self.table.setColumnCount(3)
        self.table.setHorizontalHeaderLabels(["配置项名称", "配置值", "说明"])
        header = self.table.horizontalHeader()
        header.setSectionResizeMode(0, QHeaderView.ResizeToContents)
        header.setSectionResizeMode(1, QHeaderView.Stretch)
        header.setSectionResizeMode(2, QHeaderView.Stretch)
        self.table.setAlternatingRowColors(True)
        self.table.setEditTriggers(QAbstractItemView.NoEditTriggers)
        self.table.setSelectionBehavior(QAbstractItemView.SelectRows)
        self.table.setSelectionMode(QAbstractItemView.SingleSelection)
        self.table.verticalHeader().setVisible(False)
        self.table.setStyleSheet(
            "QTableWidget { font-size: 12px; }"
            "QHeaderView::section { background: #e8edf2; font-weight: bold; padding: 4px; }"
        )
        self.stacked_layout.addWidget(self.table)

        self.text_editor = QTextEdit()
        self.text_editor.setStyleSheet(
            "QTextEdit { font-family: Consolas, 'Courier New', monospace; "
            "font-size: 12px; border: 1px solid #d0d5dd; border-radius: 4px; "
            "padding: 8px; background: #fefefe; }"
        )
        self.text_editor.textChanged.connect(self._mark_modified)
        self.stacked_layout.addWidget(self.text_editor)

        self.text_editor.hide()
        layout.addWidget(self.stacked)

    def _show_table_mode(self):
        self.table.show()
        self.text_editor.hide()
        self.btn_add.show()
        self.btn_delete.show()

    def _show_text_mode(self):
        self.table.hide()
        self.text_editor.show()
        self.btn_add.hide()
        self.btn_delete.hide()

    def load_file(self, component, filename, file_type_override=None):
        comp_info = COMPONENTS[component]
        subdir = comp_info["subdir"]

        if file_type_override:
            file_type = file_type_override
        else:
            file_type = detect_file_type(filename)

        filepath = _ensure_workspace_file(component, filename, file_type)

        if file_type == "plain_text":
            try:
                items = parse_plain_text(filepath)
            except Exception as e:
                QMessageBox.critical(self, "解析错误", f"读取文件失败:\n{e}")
                return

            self.current_items = items
            self.current_file_type = file_type
            self.current_filepath = filepath
            self.current_component = component
            self.current_filename = filename
            self.is_modified = False

            type_label = TYPE_LABELS.get(file_type, file_type)
            self.info_label.setText(
                f"📁 {COMPONENTS[component]['label']} → {filename}  ({type_label})"
            )
            self.btn_add.setEnabled(False)
            self.btn_delete.setEnabled(False)
            self._show_text_mode()
            self.text_editor.setPlainText(items[0]["value"])
            return

        if not os.path.isfile(filepath):
            QMessageBox.warning(self, "文件不存在", f"配置文件不存在:\n{filepath}")
            return

        parser = PARSERS.get(file_type)
        if not parser:
            QMessageBox.warning(self, "不支持的格式", f"无法解析文件类型: {file_type}")
            return

        try:
            items = parser(filepath)
        except Exception as e:
            QMessageBox.critical(self, "解析错误", f"解析文件失败:\n{e}")
            return

        self.current_items = items
        self.current_file_type = file_type
        self.current_filepath = filepath
        self.current_component = component
        self.current_filename = filename
        self.is_modified = False

        type_label = TYPE_LABELS.get(file_type, file_type)
        self.info_label.setText(
            f"📁 {COMPONENTS[component]['label']} → {filename}  "
            f"({type_label} · {len(items)} 项)"
        )
        self.btn_add.setEnabled(True)
        self.btn_delete.setEnabled(True)
        self._show_table_mode()
        self._populate_table()

    def _populate_table(self):
        self.table.setRowCount(0)
        self.table.setRowCount(len(self.current_items))

        for row, item in enumerate(self.current_items):
            is_core = _is_core_item(item["name"])
            display_name = f"★ {item['name']}" if is_core else item["name"]

            name_item = QTableWidgetItem(display_name)
            name_item.setFlags(name_item.flags() & ~Qt.ItemIsEditable)
            name_item.setToolTip(item["name"])
            if is_core:
                name_item.setForeground(QColor("#c0392b"))
                font = name_item.font()
                font.setBold(True)
                name_item.setFont(font)
            self.table.setItem(row, 0, name_item)

            value = item.get("value", "")
            enum_options = KNOWN_ENUMS.get(item["name"])

            if item.get("flag"):
                w = QComboBox()
                w.addItem("✓ 已启用", "enabled")
                w.addItem("✗ 未启用", "disabled")
                w.setCurrentIndex(0)
                w.currentIndexChanged.connect(lambda: self._mark_modified())
                self.table.setCellWidget(row, 1, w)
            elif enum_options:
                w = QComboBox()
                for opt in enum_options:
                    w.addItem(opt)
                idx = enum_options.index(value) if value in enum_options else 0
                w.setCurrentIndex(idx)
                w.currentIndexChanged.connect(lambda: self._mark_modified())
                self.table.setCellWidget(row, 1, w)
            elif value.lower() in ("true", "false"):
                w = QComboBox()
                w.addItems(["true", "false"])
                w.setCurrentIndex(0 if value.lower() == "true" else 1)
                w.currentIndexChanged.connect(lambda: self._mark_modified())
                self.table.setCellWidget(row, 1, w)
            elif self.current_file_type == "plain_list":
                w = QLineEdit(item["name"])
                w.setStyleSheet("padding: 2px 4px;")
                w.textChanged.connect(lambda: self._mark_modified())
                self.table.setCellWidget(row, 1, w)
            else:
                w = QLineEdit(value)
                w.setStyleSheet("padding: 2px 4px;")
                w.textChanged.connect(lambda: self._mark_modified())
                self.table.setCellWidget(row, 1, w)

            desc = item.get("description", "")
            if not desc:
                desc = DESCRIPTIONS.get(item["name"], "")
            desc_item = QTableWidgetItem(desc)
            desc_item.setFlags(desc_item.flags() & ~Qt.ItemIsEditable)
            desc_item.setToolTip(desc if desc else "")
            self.table.setItem(row, 2, desc_item)

        self.table.resizeRowsToContents()

    def _mark_modified(self):
        self.is_modified = True

    def _add_item(self):
        if not self.current_file_type:
            return
        existing_names = [it["name"] for it in self.current_items]
        dlg = AddItemDialog(
            self.current_file_type,
            component=self.current_component,
            filename=self.current_filename,
            existing_names=existing_names,
            parent=self,
        )
        if dlg.exec_() != QDialog.Accepted:
            return
        data = dlg.get_data()
        if not data:
            return
        for it in self.current_items:
            if it["name"] == data["name"]:
                QMessageBox.warning(self, "重复", f"配置项 '{data['name']}' 已存在")
                return
        self.current_items.append(data)
        self.is_modified = True
        self._populate_table()
        self.info_label.setText(
            f"📁 {COMPONENTS[self.current_component]['label']} → {self.current_filename}  "
            f"({TYPE_LABELS.get(self.current_file_type, '')} · {len(self.current_items)} 项 · 已修改)"
        )

    def _delete_item(self):
        row = self.table.currentRow()
        if row < 0:
            QMessageBox.information(self, "提示", "请先选中要删除的行")
            return
        name = self.current_items[row]["name"]
        reply = QMessageBox.question(
            self, "确认删除", f"确定删除配置项 '{name}' 吗？",
            QMessageBox.Yes | QMessageBox.No, QMessageBox.No,
        )
        if reply != QMessageBox.Yes:
            return
        self.current_items.pop(row)
        self.is_modified = True
        self._populate_table()

    def collect_values(self):
        if self.current_file_type == "plain_text":
            if self.current_items:
                self.current_items[0]["value"] = self.text_editor.toPlainText()
            return self.current_items
        for row, item in enumerate(self.current_items):
            widget = self.table.cellWidget(row, 1)
            if isinstance(widget, QComboBox):
                if item.get("flag"):
                    pass
                else:
                    item["value"] = widget.currentText()
            elif isinstance(widget, QLineEdit):
                if self.current_file_type == "plain_list":
                    new_name = widget.text().strip()
                    if new_name:
                        item["name"] = new_name
                else:
                    item["value"] = widget.text()
        return self.current_items

    def _write_file(self, filepath):
        items = self.collect_values()
        file_type = self.current_file_type
        builder = BUILDERS.get(file_type)
        if not builder:
            QMessageBox.warning(self, "不支持", f"无法构建文件类型: {file_type}")
            return False
        try:
            if file_type == "xml":
                tree = builder(items, self.current_filepath)
                tree.write(filepath, encoding="UTF-8", xml_declaration=True)
            elif file_type == "plain_text":
                content = items[0]["value"] if items else ""
                os.makedirs(os.path.dirname(filepath), exist_ok=True)
                with open(filepath, "w", encoding="utf-8") as f:
                    f.write(content)
            else:
                content = builder(items, self.current_filepath)
                os.makedirs(os.path.dirname(filepath), exist_ok=True)
                with open(filepath, "w", encoding="utf-8") as f:
                    f.write(content)
        except Exception as e:
            QMessageBox.critical(self, "保存错误", f"保存文件失败:\n{e}")
            return False
        self.is_modified = False
        return True

    def save_file(self):
        if not self.current_filepath:
            return
        if self._write_file(self.current_filepath):
            QMessageBox.information(self, "保存成功", f"配置已保存到:\n{self.current_filepath}")

    def apply_to_source(self):
        if not self.current_filepath:
            return
        comp_info = COMPONENTS[self.current_component]
        subdir = comp_info["subdir"]
        source_path = os.path.join(CONFIG_DIR, subdir, self.current_filename)
        reply = QMessageBox.question(
            self, "确认覆盖",
            f"将覆盖源配置文件:\n{source_path}\n\n此操作不可撤销，是否继续？",
            QMessageBox.Yes | QMessageBox.No, QMessageBox.No,
        )
        if reply != QMessageBox.Yes:
            return
        if self._write_file(source_path):
            QMessageBox.information(self, "应用成功", f"源配置文件已更新:\n{source_path}")


class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("大数据平台配置可视化工具")
        self.setMinimumSize(1000, 650)
        self.resize(1200, 750)
        self._init_ui()
        self._apply_styles()

    def _init_ui(self):
        central = QWidget()
        self.setCentralWidget(central)
        main_layout = QHBoxLayout(central)
        main_layout.setContentsMargins(8, 8, 8, 8)
        main_layout.setSpacing(8)

        splitter = QSplitter(Qt.Horizontal)
        splitter.addWidget(self._build_left_panel())
        splitter.addWidget(self._build_right_panel())
        splitter.setStretchFactor(0, 1)
        splitter.setStretchFactor(1, 3)
        splitter.setSizes([250, 950])
        main_layout.addWidget(splitter)
        self.statusBar().showMessage("就绪 — 选择左侧组件和配置文件开始编辑")

    def _build_left_panel(self):
        panel = QWidget()
        layout = QVBoxLayout(panel)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(6)

        comp_group = QGroupBox("选择组件")
        comp_layout = QVBoxLayout(comp_group)
        self.comp_list = QListWidget()
        self.comp_list.setIconSize(QSize(24, 24))
        for key, info in COMPONENTS.items():
            item = QListWidgetItem(info["label"])
            item.setData(Qt.UserRole, key)
            self.comp_list.addItem(item)
        self.comp_list.currentItemChanged.connect(self._on_component_changed)
        comp_layout.addWidget(self.comp_list)

        comp_btn_row = QHBoxLayout()
        self.btn_add_comp = QPushButton("➕ 新增组件")
        self.btn_add_comp.setStyleSheet(
            "QPushButton { background: #8e44ad; color: white; padding: 4px 10px; "
            "border-radius: 3px; font-size: 11px; font-weight: bold; }"
            "QPushButton:hover { background: #7d3c98; }"
        )
        self.btn_add_comp.clicked.connect(self._on_add_component)
        comp_btn_row.addWidget(self.btn_add_comp)

        self.btn_del_comp = QPushButton("🗑 删除组件")
        self.btn_del_comp.setStyleSheet(
            "QPushButton { background: #95a5a6; color: white; padding: 4px 10px; "
            "border-radius: 3px; font-size: 11px; font-weight: bold; }"
            "QPushButton:hover { background: #7f8c8d; }"
        )
        self.btn_del_comp.clicked.connect(self._on_del_component)
        comp_btn_row.addWidget(self.btn_del_comp)
        comp_layout.addLayout(comp_btn_row)

        layout.addWidget(comp_group)

        file_group = QGroupBox("配置文件")
        file_layout = QVBoxLayout(file_group)
        self.file_list = QListWidget()
        self.file_list.currentItemChanged.connect(self._on_file_changed)
        file_layout.addWidget(self.file_list)

        file_btn_row = QHBoxLayout()
        self.btn_add_file = QPushButton("➕ 新增文件")
        self.btn_add_file.setStyleSheet(
            "QPushButton { background: #8e44ad; color: white; padding: 4px 10px; "
            "border-radius: 3px; font-size: 11px; font-weight: bold; }"
            "QPushButton:hover { background: #7d3c98; }"
        )
        self.btn_add_file.clicked.connect(self._on_add_file)
        self.btn_add_file.setEnabled(False)
        file_btn_row.addWidget(self.btn_add_file)

        self.btn_del_file = QPushButton("🗑 删除文件")
        self.btn_del_file.setStyleSheet(
            "QPushButton { background: #95a5a6; color: white; padding: 4px 10px; "
            "border-radius: 3px; font-size: 11px; font-weight: bold; }"
            "QPushButton:hover { background: #7f8c8d; }"
        )
        self.btn_del_file.clicked.connect(self._on_del_file)
        self.btn_del_file.setEnabled(False)
        file_btn_row.addWidget(self.btn_del_file)
        file_layout.addLayout(file_btn_row)

        layout.addWidget(file_group)

        btn_layout = QVBoxLayout()
        self.btn_save = QPushButton("💾 保存")
        self.btn_save.setToolTip(f"保存到工作目录: {WORK_DIR}/[组件名]/[文件名]")
        self.btn_save.clicked.connect(self._on_save)
        self.btn_save.setEnabled(False)
        btn_layout.addWidget(self.btn_save)

        self.btn_apply = QPushButton("📤 同步到 config/")
        self.btn_apply.setToolTip("将工作目录的文件复制到 config/ 目录（谨慎操作）")
        self.btn_apply.clicked.connect(self._on_apply)
        self.btn_apply.setEnabled(False)
        btn_layout.addWidget(self.btn_apply)
        layout.addLayout(btn_layout)

        return panel

    def _build_right_panel(self):
        panel = QWidget()
        layout = QVBoxLayout(panel)
        layout.setContentsMargins(0, 0, 0, 0)
        self.editor = ConfigEditorWidget()
        layout.addWidget(self.editor)
        return panel

    def _on_component_changed(self, current, previous):
        self.file_list.clear()
        if not current:
            self.btn_add_file.setEnabled(False)
            self.btn_del_file.setEnabled(False)
            return
        component = current.data(Qt.UserRole)
        comp_info = COMPONENTS[component]
        subdir = comp_info["subdir"]
        for fname in comp_info["files"]:
            work_path = os.path.join(WORK_DIR, subdir, fname)
            config_path = os.path.join(CONFIG_DIR, subdir, fname)
            exists = os.path.isfile(work_path)
            in_config = os.path.isfile(config_path)
            item = QListWidgetItem(fname)
            item.setData(Qt.UserRole, fname)
            if not exists and not in_config:
                item.setForeground(QColor("#999"))
                item.setToolTip("新文件（尚未创建）")
            elif not exists and in_config:
                item.setForeground(QColor("#e67e22"))
                item.setToolTip("尚未初始化（首次选择时从 config/ 复制）")
            self.file_list.addItem(item)
        self.btn_save.setEnabled(False)
        self.btn_apply.setEnabled(False)
        self.btn_add_file.setEnabled(True)
        self.btn_del_file.setEnabled(True)

    def _on_file_changed(self, current, previous):
        if not current:
            return
        comp_item = self.comp_list.currentItem()
        if not comp_item:
            return
        component = comp_item.data(Qt.UserRole)
        filename = current.data(Qt.UserRole)
        file_type_override = current.data(Qt.UserRole + 1)
        self.editor.load_file(component, filename, file_type_override=file_type_override)
        self.btn_save.setEnabled(True)
        self.btn_apply.setEnabled(True)
        self.statusBar().showMessage(
            f"已加载: {COMPONENTS[component]['label']} → {filename}"
        )

    def _on_add_component(self):
        dlg = AddComponentDialog(self)
        if dlg.exec_() != QDialog.Accepted:
            return
        data = dlg.get_data()
        COMPONENTS[data["key"]] = {
            "label": data["label"],
            "subdir": data["subdir"],
            "files": [],
        }
        work_dir = os.path.join(WORK_DIR, data["subdir"])
        os.makedirs(work_dir, exist_ok=True)
        item = QListWidgetItem(data["label"])
        item.setData(Qt.UserRole, data["key"])
        self.comp_list.addItem(item)
        self.comp_list.setCurrentItem(item)
        self.statusBar().showMessage(f"已新增组件: {data['label']} → {work_dir}")

    def _on_del_component(self):
        current = self.comp_list.currentItem()
        if not current:
            return
        component = current.data(Qt.UserRole)
        comp_info = COMPONENTS[component]
        reply = QMessageBox.question(
            self, "确认删除",
            f"确定删除组件 '{comp_info['label']}' 吗？\n"
            f"这将从列表中移除该组件（不会删除配置文件）。",
            QMessageBox.Yes | QMessageBox.No, QMessageBox.No,
        )
        if reply != QMessageBox.Yes:
            return
        del COMPONENTS[component]
        row = self.comp_list.row(current)
        self.comp_list.takeItem(row)
        self.file_list.clear()
        self.statusBar().showMessage(f"已删除组件: {comp_info['label']}")

    def _on_add_file(self):
        comp_item = self.comp_list.currentItem()
        if not comp_item:
            return
        component = comp_item.data(Qt.UserRole)
        dlg = AddFileDialog(component, self)
        if dlg.exec_() != QDialog.Accepted:
            return
        data = dlg.get_data()
        fname = data["filename"]
        file_type = data["file_type"]

        COMPONENTS[component]["files"].append(fname)

        work_path = _ensure_workspace_file(component, fname, file_type)

        item = QListWidgetItem(fname)
        item.setData(Qt.UserRole, fname)
        if file_type == "plain_text":
            item.setData(Qt.UserRole + 1, "plain_text")

        self.file_list.addItem(item)
        self.file_list.setCurrentItem(item)
        self.statusBar().showMessage(
            f"已新增文件: {COMPONENTS[component]['label']} → {fname} "
            f"({TYPE_LABELS.get(file_type, file_type)}) → {work_path}"
        )

    def _on_del_file(self):
        comp_item = self.comp_list.currentItem()
        file_item = self.file_list.currentItem()
        if not comp_item or not file_item:
            return
        component = comp_item.data(Qt.UserRole)
        filename = file_item.data(Qt.UserRole)
        reply = QMessageBox.question(
            self, "确认删除",
            f"确定从组件 '{COMPONENTS[component]['label']}' 中移除文件 '{filename}' 吗？\n"
            f"这将从列表中移除（不会删除实际文件）。",
            QMessageBox.Yes | QMessageBox.No, QMessageBox.No,
        )
        if reply != QMessageBox.Yes:
            return
        COMPONENTS[component]["files"].remove(filename)
        row = self.file_list.row(file_item)
        self.file_list.takeItem(row)
        self.statusBar().showMessage(f"已移除文件: {filename}")

    def _on_save(self):
        self.editor.save_file()

    def _on_apply(self):
        self.editor.apply_to_source()

    def _apply_styles(self):
        self.setStyleSheet("""
            QMainWindow { background: #f5f7fa; }
            QGroupBox {
                font-weight: bold; font-size: 13px;
                border: 1px solid #d0d5dd; border-radius: 6px;
                margin-top: 8px; padding-top: 16px;
            }
            QGroupBox::title {
                subcontrol-origin: margin; left: 12px; padding: 0 6px;
            }
            QListWidget {
                border: 1px solid #d0d5dd; border-radius: 4px;
                font-size: 12px; outline: none;
            }
            QListWidget::item { padding: 6px 8px; border-bottom: 1px solid #eee; }
            QListWidget::item:selected { background: #4a90d9; color: white; }
            QListWidget::item:hover { background: #e8f0fe; }
            QPushButton {
                background: #4a90d9; color: white; border: none;
                border-radius: 4px; padding: 8px 16px;
                font-size: 12px; font-weight: bold;
            }
            QPushButton:hover { background: #357abd; }
            QPushButton:pressed { background: #2a5f9e; }
            QPushButton:disabled { background: #b0c4de; }
            QStatusBar { font-size: 12px; color: #666; }
        """)


def main():
    app = QApplication(sys.argv)
    app.setFont(QFont("Microsoft YaHei", 10))
    window = MainWindow()
    window.show()
    sys.exit(app.exec_())


if __name__ == "__main__":
    main()
