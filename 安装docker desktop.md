# Windows 安装 Docker Desktop 并配置 WSL2 完整指南

## 系统要求和前提条件

在开始安装之前，请确保您的系统满足以下要求：

| 要求项目 | 详细说明 |
|---------|---------|
| **操作系统** | Windows 11 或 Windows 10 版本 1903 及以上 |
| **虚拟化支持** | 已在 BIOS/UEFI 中开启虚拟化技术 |
| **WSL2** | 需要 WSL2（Windows Subsystem for Linux version 2）的支持 |
| **管理员权限** | 安装过程中需要管理员权限 |
| **硬件配置** | 内存建议至少 4GB，推荐 8GB 或更高；硬盘空间至少需要 10GB 可用空间 |

### 检查系统要求

1. **检查 Windows 版本**：
   - 按下 `Win + R` 组合键，输入 `winver` 并回车
   - 确认您的版本是 Windows 11 或 Windows 10 版本 1903 及以上

2. **检查硬件配置**：
   - 内存：建议至少 4GB，推荐 8GB 或更高
   - 硬盘空间：至少需要 10GB 可用空间

3. **检查 BIOS 虚拟化是否启用**：
   - 重启电脑，进入 BIOS/UEFI 设置（通常在开机时按 Delete、F2、F12、Esc 等键）
   - 查找包含 "Virtualization Technology"、"Intel VT-x"、"AMD-V" 或类似名称的选项
   - 确保其状态为 "Enabled"
   - 保存更改并退出 BIOS/UEFI

## 第一步：安装和配置 WSL2

如果尚未安装 WSL2，请按以下步骤操作：

### 启用 Windows 功能

1. 以管理员身份打开 PowerShell（右击开始菜单，选择"Windows PowerShell (管理员)"）

2. 依次执行以下命令启用必要功能：

```powershell
# 启用"适用于 Linux 的 Windows 子系统"功能
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart

# 启用"虚拟机平台"功能
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart

# 设置 WSL2 为默认版本
wsl --set-default-version 2
```

3. 重启电脑以确保更改生效

### 更新 WSL2（可选，解决常见问题）

如果遇到 WSL2 相关的问题，可以尝试更新：

```powershell
# 尝试使用 web 下载方式更新
wsl --update --web-download
```

如果上述命令无效，可以手动下载并安装 WSL2 Linux 内核更新包：

1. 访问 Microsoft 官方下载页面：https://learn.microsoft.com/zh-cn/windows/wsl/install-manual#step-4---download-the-linux-kernel-update-package
2. 下载最新的 x64 内核更新包（wsl_update_x64.msi）
3. 右键单击下载的文件，选择"以管理员身份运行"
4. 按照安装向导完成安装
5. 安装完成后，重启计算机

### 安装 Ubuntu 发行版

1. 从 Microsoft Store 安装 Ubuntu（推荐选择 LTS 版本，如 Ubuntu 22.04 LTS）
2. 安装后启动 Ubuntu，完成初始用户名和密码的设置

## 第二步：安装 Docker Desktop

Docker Desktop 是管理容器和镜像的便捷工具，并提供了与 WSL2 的无缝集成。

### 下载 Docker Desktop

1. 访问 Docker 官方下载页面：https://www.docker.com/products/docker-desktop
2. 下载 Windows 版本的安装程序（Docker Desktop Installer.exe）

### 安装 Docker Desktop

1. 双击下载的 Docker Desktop Installer.exe
2. 安装过程中，务必勾选"使用 WSL2 代替 Hyper-V"或类似选项
3. 遵循安装向导完成安装
4. 安装完成后根据提示重启电脑

### 验证安装

1. 重启后，Docker Desktop 通常会自动启动。如果没有，可从开始菜单启动它
2. 打开 PowerShell 或命令提示符，输入以下命令检查版本：

```bash
docker --version
```

3. 若显示版本号（如 `Docker version 24.0.7, build 1114ade`），则说明安装成功

## 第三步：配置 Docker Desktop 与 WSL2 集成

这是实现用 Windows 上的 Docker Desktop 管理 WSL2 Ubuntu 环境的关键步骤。

1. 系统托盘中找到 Docker 鲸鱼图标，右击选择 "Settings"（或 "设置"）
2. 在设置窗口中，导航到 "Resources" -> "WSL Integration"
3. 确保 "Enable integration with my default WSL distro" 已开启
4. 在下面的列表中找到你安装的 Ubuntu 发行版（例如 Ubuntu-22.04），并切换开关将其启用
5. 点击 "Apply & Restart" 以应用设置并重启 Docker 服务

## 第四步：安装后的配置

### 配置国内镜像加速器

为了提升镜像下载速度，建议配置国内镜像源。

1. 在 Docker Desktop 的设置中，导航到 "Docker Engine"
2. 在配置文件中找到或添加 "registry-mirrors" 项，填入国内镜像站地址：

```json
{
  "registry-mirrors": [
    "https://docker.mirrors.ustc.edu.cn",
    "https://hub-mirror.c.163.com", 
    "https://mirror.baidubce.com",
    "https://registry.docker-cn.com"
  ]
}
```

3. 点击 "Apply & Restart"

### 验证 Docker 能否在 Ubuntu 中工作

1. 打开你的 WSL2 Ubuntu 终端
2. 运行以下命令验证 Docker 客户端是否可用并能与 Docker 守护进程通信：

```bash
docker info
```

3. 你应该能看到详细的 Docker 系统信息，包括你配置的镜像加速器

## 第五步：修改 Docker 镜像和容器存储路径（可选）

默认情况下，Docker 数据存储在 C 盘。为了防止 C 盘空间不足，你可以将其迁移到其他分区（例如 D 盘）。

**注意：此操作会删除现有的镜像和容器，请谨慎操作。**

1. 首先在 Docker Desktop 中完全退出 Docker（右击系统托盘图标选择 Quit Docker Desktop）

2. 在管理员 PowerShell 中关闭所有 WSL 发行版：

```powershell
wsl --shutdown
```

3. 导出现有的 Docker 数据（如果存在且你需要备份）：

```powershell
wsl --export docker-desktop-data "D:\wsl\docker-desktop-data.tar"
wsl --export docker-desktop "D:\wsl\docker-desktop.tar"
```

4. 注销当前的 Docker 发行版：

```powershell
wsl --unregister docker-desktop-data
wsl --unregister docker-desktop
```

5. 在新的目录（如 D:\docker\wsl\）中重新导入：

```powershell
wsl --import docker-desktop-data "D:\docker\wsl\data" "D:\wsl\docker-desktop-data.tar" --version 2
wsl --import docker-desktop "D:\docker\wsl\desktop" "D:\wsl\docker-desktop.tar" --version 2
```

6. 删除导出的 .tar 备份文件以节省空间
7. 重新启动 Docker Desktop

## 第六步：测试使用

现在，你可以在 WSL2 Ubuntu 终端或 Windows PowerShell/命令提示符中运行 Docker 命令来管理你的容器和镜像。

### 基础测试

1. 在 Ubuntu 中拉取并运行一个测试容器：

```bash
# 拉取一个轻量级镜像，如 Hello-World
docker pull hello-world

# 运行容器
docker run hello-world
```

如果看到欢迎信息，说明一切正常！

2. 在 Ubuntu 中运行一个更实用的容器（例如 Nginx Web 服务器）：

```bash
docker run --name my-nginx -p 8080:80 -d nginx
```

然后在 Windows 浏览器中访问 `http://localhost:8080`，你应该能看到 Nginx 的欢迎页面。

### 查看镜像和容器

```bash
# 查看所有镜像
docker images

# 查看运行中的容器
docker ps

# 查看所有容器（包括停止的）
docker ps -a
```

## 常见问题与故障排除

### 问题1：WSL2 安装失败

**症状**：运行 `wsl --install` 时出现错误

**解决方案**：
1. 确保已启用虚拟化技术
2. 尝试手动下载并安装 WSL2 内核更新包
3. 检查 Windows 版本是否为支持的版本

### 问题2：Docker Desktop 无法启动

**症状**：Docker Desktop 启动时显示错误或无法连接

**解决方案**：
1. 确保 WSL2 已正确安装和配置
2. 检查 Docker Desktop 设置中的 WSL Integration 是否已启用
3. 重启 Docker Desktop 服务
4. 重启计算机

### 问题3：镜像下载速度慢

**解决方案**：
1. 配置国内镜像加速器（参考第四步）
2. 检查网络连接
3. 尝试使用不同的镜像源

### 问题4：磁盘空间不足

**解决方案**：
1. 清理无用的镜像和容器：`docker system prune`
2. 迁移 Docker 数据到其他分区（参考第五步）
3. 定期清理 Docker 缓存

## 总结

通过以上步骤，您应该已经成功在 Windows 系统上安装了 Docker Desktop 并配置了 WSL2 环境。现在您可以开始使用 Docker 来管理和运行容器化应用程序了。

Docker 与 WSL2 的集成提供了强大的开发环境，让您可以在 Windows 上享受 Linux 容器的便利性，同时保持与 Windows 系统的无缝集成。