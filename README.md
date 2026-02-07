# code-tunnel

Run a [VS Code tunnel](https://code.visualstudio.com/docs/remote/tunnels) inside a [SLURM](https://slurm.schedmd.com/) interactive GPU job — develop on a remote HPC cluster with full VS Code, right from your laptop.

## Why?

If you work on an HPC cluster managed by SLURM, you know the pain: SSH into a login node, request a GPU job, and then try to code in a terminal. VS Code's [Remote - Tunnels](https://marketplace.visualstudio.com/items?itemName=ms-vscode.remote-server) feature lets you connect a full VS Code client to a remote machine over a secure tunnel — but setting it up inside a SLURM job is fiddly.

**code-tunnel** automates this. One command gets you:

- A SLURM interactive job with a GPU (configurable resources)
- A VS Code tunnel running inside that job
- A persistent [GNU Screen](https://www.gnu.org/software/screen/) session so you can detach and reattach

You then connect from VS Code on your laptop using the Remote - Tunnels extension, and you're editing code directly on the compute node with full IntelliSense, debugging, and GPU access.

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/nickboucher/code-tunnel/main/install.sh | bash
```

Or with `wget`:

```bash
wget -qO- https://raw.githubusercontent.com/nickboucher/code-tunnel/main/install.sh | bash
```

This will:

1. Download the VS Code CLI for your platform
2. Install it to `~/.vscode-tunnel/bin/code`
3. Install the `tunnel` command to `~/.vscode-tunnel/bin/tunnel`
4. Add `~/.vscode-tunnel/bin` to your `PATH`

### Custom Install Directory

```bash
curl -fsSL https://raw.githubusercontent.com/nickboucher/code-tunnel/main/install.sh | bash -s -- --dir /opt/code-tunnel
```

### Prerequisites

- **Linux** (any SLURM cluster — RHEL, CentOS, Ubuntu, Debian, SUSE, etc.)
- **SLURM** (`srun` must be available)
- **GNU Screen** (`screen` must be available)
- **curl** or **wget** (for the installer)

## Usage

```bash
# Basic: specify account, partition, and time in minutes
tunnel -a myaccount -p gpu 60

# Interactive: you'll be prompted for the time
tunnel -a myaccount -p gpu

# With all options
tunnel -a myaccount -p gpu -c 4 -g gpu:2 -m 32G -q high 120
```

### Setting Defaults

Rather than passing flags every time, export environment variables in your shell config (e.g., `~/.bashrc`):

```bash
export CODE_TUNNEL_ACCOUNT=myaccount
export CODE_TUNNEL_PARTITION=gpu
export CODE_TUNNEL_CPUS=4
export CODE_TUNNEL_QOS=high
```

Then just run:

```bash
tunnel 60
```

### All Options

| Flag | Environment Variable | Default | Description |
|------|---------------------|---------|-------------|
| `-a, --account` | `CODE_TUNNEL_ACCOUNT` | *(required)* | SLURM account |
| `-p, --partition` | `CODE_TUNNEL_PARTITION` | *(required)* | SLURM partition |
| `-c, --cpus` | `CODE_TUNNEL_CPUS` | `2` | CPUs per task |
| `-g, --gpus` | `CODE_TUNNEL_GPUS` | `gpu:1` | GPU resource spec (GRES) |
| `-m, --mem` | `CODE_TUNNEL_MEM` | SLURM default | Memory (e.g., `16G`) |
| `-q, --qos` | `CODE_TUNNEL_QOS` | *(none)* | Quality of service |
| `--nodes` | `CODE_TUNNEL_NODES` | `1` | Number of nodes |
| `--ntasks` | `CODE_TUNNEL_NTASKS` | `1` | Number of tasks |
| `--session` | `CODE_TUNNEL_SESSION` | `vscode-tunnel` | Screen session name |
| `--extra` | `CODE_TUNNEL_EXTRA_ARGS` | *(none)* | Additional `srun` arguments |
| `-h, --help` | | | Show help |

Command-line flags take precedence over environment variables.

## Connecting from VS Code

1. Run `tunnel` on your cluster (as shown above).
2. The first time, you'll be prompted to authenticate with GitHub or Microsoft.
3. Once the tunnel is active, open VS Code on your laptop.
4. Install the [Remote - Tunnels](https://marketplace.visualstudio.com/items?itemName=ms-vscode.remote-server) extension.
5. Open the Command Palette (`Ctrl+Shift+P` / `Cmd+Shift+P`) → **Remote Tunnels: Connect to Tunnel**.
6. Select your machine from the list. You're now editing on the compute node.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/nickboucher/code-tunnel/main/uninstall.sh | bash
```

Or with `wget`:

```bash
wget -qO- https://raw.githubusercontent.com/nickboucher/code-tunnel/main/uninstall.sh | bash
```

If you installed to a custom directory:

```bash
curl -fsSL https://raw.githubusercontent.com/nickboucher/code-tunnel/main/uninstall.sh | bash -s -- --dir /opt/code-tunnel
```

## How It Works

Under the hood, `tunnel` runs:

```
srun -A <account> -p <partition> --gres=<gpus> -t <time> ... \
    --pty screen -mS vscode-tunnel \
    bash -c 'code tunnel; exec bash'
```

This:

1. Allocates a SLURM interactive job with the requested resources
2. Starts a GNU Screen session (so you can detach with `Ctrl+A D` and reattach with `screen -r vscode-tunnel`)
3. Launches the VS Code CLI tunnel inside the job
4. Keeps the shell alive after the tunnel exits

## License

[MIT](LICENSE)
