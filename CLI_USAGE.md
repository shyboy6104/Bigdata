# BigData Platform CLI Management Tool

A comprehensive shell script-based CLI tool for managing Docker containers and images in your big data platform. Supports both single-component and multi-component architectures, with interactive menu and command-line modes.

## Features

- **Interactive Menu Mode**: User-friendly guided operation with menus
- **Command Line Mode**: Direct parameter-based execution for automation
- **Image Management**: Build and delete Docker images
- **Container Lifecycle**: Start, stop, destroy, restart, and clean containers
- **Status Monitoring**: View container status, logs, and supervisor status
- **Testing**: Run component functionality tests
- **Dual Architecture Support**: Both single-component and multi-component (5-node cluster) architectures
- **Volume Management**: Clean unused Docker volumes

## Quick Start

### Prerequisites

- Docker installed and running
- Docker Compose installed
- Bash shell environment (Linux/WSL)

### Basic Usage

```bash
# Make the script executable
chmod +x bigdata-cli.sh

# Start interactive menu mode (recommended for beginners)
./bigdata-cli.sh

# Show help
./bigdata-cli.sh --help

# List available components
./bigdata-cli.sh list
```

## Usage Modes

### Interactive Menu Mode

Run the script without arguments to enter interactive mode:

```bash
./bigdata-cli.sh
```

Menu options:
1. **Image Management** - Build/Delete images
2. **Container Lifecycle Management** - Start/Stop/Restart/Destroy/Clean
3. **Status Monitoring** - View status/logs/supervisor
4. **Component Testing** - Run functionality tests
5. **List Available Components** - Show all components
6. **Command Line Mode** - Switch to CLI help
0. **Exit**

### Command Line Mode

```bash
./bigdata-cli.sh [options] <command> <component>
```

## Commands

### Image Management

```bash
# Build Docker image for a component
./bigdata-cli.sh build hadoop
./bigdata-cli.sh build kafka
./bigdata-cli.sh build hadoop-ha

# Delete Docker image
./bigdata-cli.sh delete hadoop
./bigdata-cli.sh delete zookeeper
```

### Container Lifecycle

```bash
# Start containers
./bigdata-cli.sh start hadoop
./bigdata-cli.sh start kafka

# Stop containers
./bigdata-cli.sh stop hadoop
./bigdata-cli.sh stop zookeeper

# Destroy containers (stop and remove)
./bigdata-cli.sh destroy hadoop

# Restart containers
./bigdata-cli.sh restart hadoop

# Clean containers, networks and volumes
./bigdata-cli.sh clean hadoop

# Clean all unused volumes in the system
./bigdata-cli.sh clean-volumes
```

### Status and Logs

```bash
# View container status
./bigdata-cli.sh status hadoop
./bigdata-cli.sh status kafka

# View container logs
./bigdata-cli.sh logs hadoop

# Follow logs in real-time
./bigdata-cli.sh logs kafka -f

# View supervisor status (multi-architecture only)
./bigdata-cli.sh supervisor all
```

### Testing

```bash
# Test component functionality
./bigdata-cli.sh test hadoop
./bigdata-cli.sh test kafka
./bigdata-cli.sh test hadoop-ha

# Test full-stack cluster (multi-architecture)
./bigdata-cli.sh --architecture multi test all
```

## Architecture Support

### Single-Component Architecture (Default)

Each big data component runs in its own independent container cluster:

```bash
# Start Hadoop single-component cluster
./bigdata-cli.sh start hadoop

# Start Hadoop HA cluster
./bigdata-cli.sh start hadoop-ha

# Start Kafka single-component cluster
./bigdata-cli.sh start kafka
```

### Multi-Component Architecture (5-Node Full-Stack)

All components run together in a 5-node cluster:

```bash
# Start full-stack cluster
./bigdata-cli.sh --architecture multi start all

# Check status of full-stack cluster
./bigdata-cli.sh --architecture multi status all

# View supervisor status for all nodes
./bigdata-cli.sh --architecture multi supervisor all
```

## Available Components

| Component | Description | Docker Image |
|-----------|-------------|--------------|
| **hadoop** | Distributed computing and storage framework | bigdata-hadoop:latest |
| **hadoop-ha** | Hadoop High Availability configuration | bigdata-hadoop:latest |
| **zookeeper** | Distributed coordination service | bigdata-zookeeper:latest |
| **hbase** | Distributed NoSQL database | bigdata-hbase:latest |
| **hive** | Data warehouse tool | bigdata-hive:latest |
| **kafka** | Distributed message queue | bigdata-kafka:latest |
| **spark** | In-memory computing engine | bigdata-spark:latest |
| **flink** | Stream processing framework | bigdata-flink:latest |
| **flume** | Log collection tool | bigdata-flume:latest |
| **mysql** | Relational database (Hive metadata) | bigdata-mysql:latest |

> **Note**: `hadoop` and `hadoop-ha` share the same Docker image (`bigdata-hadoop:latest`) but use different Docker Compose and configuration files.

## Options

| Option | Description |
|--------|-------------|
| `-a, --architecture <arch>` | Architecture type: `single` (default) or `multi` |
| `-h, --help` | Show help message |
| `-f` | Follow logs in real-time (used with `logs` command) |

## Examples

### Complete Workflow for Single Component

```bash
# Build and start Hadoop cluster
./bigdata-cli.sh build hadoop
./bigdata-cli.sh start hadoop

# Check status
./bigdata-cli.sh status hadoop

# Test functionality
./bigdata-cli.sh test hadoop

# View logs
./bigdata-cli.sh logs hadoop

# Clean up
./bigdata-cli.sh clean hadoop
./bigdata-cli.sh delete hadoop
```

### Hadoop HA Cluster

```bash
# Build image (shares same image as hadoop)
./bigdata-cli.sh build hadoop-ha

# Start HA cluster
./bigdata-cli.sh start hadoop-ha

# Test HA functionality
./bigdata-cli.sh test hadoop-ha
```

### Multi-Component Cluster Management

```bash
# Build and start full-stack cluster
./bigdata-cli.sh --architecture multi build all
./bigdata-cli.sh --architecture multi start all

# Monitor all components
./bigdata-cli.sh --architecture multi status all

# View supervisor status
./bigdata-cli.sh --architecture multi supervisor all

# Test full-stack cluster
./bigdata-cli.sh --architecture multi test all

# Clean up full-stack cluster
./bigdata-cli.sh --architecture multi clean all
```

### Development and Testing

```bash
# Quick restart for development
./bigdata-cli.sh restart kafka

# Monitor logs during testing
./bigdata-cli.sh logs flink -f

# Test multiple components sequentially
./bigdata-cli.sh test zookeeper
./bigdata-cli.sh test hadoop-ha
./bigdata-cli.sh test hbase
./bigdata-cli.sh test hive
./bigdata-cli.sh test kafka
./bigdata-cli.sh test spark
./bigdata-cli.sh test flink
./bigdata-cli.sh test flume
./bigdata-cli.sh test mysql
```

### Volume Cleanup

```bash
# Clean volumes for a specific component
./bigdata-cli.sh clean hadoop

# Clean all unused volumes in the system
./bigdata-cli.sh clean-volumes
```

## Windows Usage

For Windows users, use the batch file wrapper:

```cmd
bigdata-cli.bat --help
bigdata-cli.bat list
bigdata-cli.bat start hadoop
```

Or run directly with bash in WSL:

```bash
bash bigdata-cli.sh start hadoop
```

## Error Handling

The CLI tool provides colored output for different message types:

- **Blue [INFO]**: Informational messages
- **Green [SUCCESS]**: Successful operations
- **Yellow [WARNING]**: Warning messages
- **Red [ERROR]**: Error messages

## Dependencies Check

The tool automatically checks for required dependencies:
- Docker
- Docker Compose

If dependencies are missing, the tool will display an error message and exit.

## Troubleshooting

### Common Issues

1. **Docker not running**: Ensure Docker daemon is started
2. **Permission denied**: Make script executable with `chmod +x bigdata-cli.sh`
3. **Component not found**: Use `./bigdata-cli.sh list` to see available components
4. **File not found**: Ensure Docker Compose files exist in the project directory
5. **Hadoop HA uses same image as Hadoop**: `hadoop-ha` shares the `bigdata-hadoop:latest` image

### Debug Mode

For detailed debugging, you can run the script with bash debugging:

```bash
bash -x bigdata-cli.sh start hadoop
```

## Contributing

This CLI tool is designed to be extensible. To add new components or features:

1. Update the `COMPONENTS` array in the script
2. Add corresponding Docker Compose file mappings to `SINGLE_COMPOSE_FILES`
3. Add corresponding Dockerfile mapping in `get_dockerfile()`
4. Implement new command functions as needed

## License

This tool is part of the Big Data Distributed Service Experimental Platform.
