# Building rackspace-monitoring-agent for Ubuntu 24.04

Build Debian packages for rackspace-monitoring-agent compatible with Ubuntu 24.04 using Docker.

## Prerequisites

- Docker installed and running
- ~2GB free disk space
- Internet connection

## Sigar Dependency

The build requires the [racker/sigar](https://github.com/racker/sigar) project (private repo) to be available as a sibling directory to this project:

```
parent-directory/
├── rackspace-monitoring-agent/   # this project
└── sigar/                        # required sibling
```

Clone it manually (requires SSH access to the private repo):

```bash
cd ..
git clone git@github.com:racker/sigar.git
cd rackspace-monitoring-agent
```

The build script will error out with instructions if sigar is not found.

## Signing Keys

The build produces signed packages and a signed APT repository. The following files must be placed in the project root before building:

| File | Purpose |
|------|---------|
| `server.key` | Signs the agent binary (generates `.sig` file) |
| `signing-key.asc` | Public key included in meta packages for APT verification |
| `agent-package-signing-key.txt` | GPG private key used to sign the APT repository (`InRelease`, `Release.gpg`) |

These files can be found at: https://passwordsafe.corp.rackspace.com/projects/42902

> **Note:** The build will still succeed without these files, but the binary will not be signed, and the signed APT repository and meta packages will not be generated.

## Build the Package

> **Note:** The first build takes 15-20 minutes as it downloads all dependencies and compiles from source. Subsequent builds are much faster due to Docker layer caching.

Since sigar is a private repository, you must clone it manually before building:

```bash
cd ..
git clone git@github.com:racker/sigar.git   # requires SSH access
cd rackspace-monitoring-agent
```

The Docker build context must be the **parent directory** containing both projects:

```bash
mkdir -p dist
docker build -f rackspace-monitoring-agent/Dockerfile.ubuntu24 -t rma-ubuntu24-builder ..
docker run --rm -v "$(pwd)/dist:/output" rma-ubuntu24-builder
```

Or use the Makefile target (if updated):

```bash
make ubuntu24-build
```

## Test Installation (Docker)

Quick test in a clean Ubuntu 24.04 container:

```bash
make ubuntu24-test
```

## Test Installation (Vagrant)

For a full VM test with systemd, networking, etc:

```bash
# Build the .deb first, then:
vagrant up        # boots VM, copies .deb, installs it
vagrant ssh       # SSH in to inspect

# Inside the VM:
rackspace-monitoring-agent -v
sudo systemctl status rackspace-monitoring-agent
sudo journalctl -u rackspace-monitoring-agent -f
```

To re-test after rebuilding the `.deb`:

```bash
vagrant destroy -f
vagrant up
```

## Other Make Targets

| Target | Description |
|--------|-------------|
| `make ubuntu24-build` | Build the `.deb` package |
| `make ubuntu24-test` | Test install in a clean container |
| `make ubuntu24-shell` | Interactive shell in build environment |
| `make ubuntu24-clean` | Remove build image and dist artifacts |

## Build Process

1. Uses Ubuntu 24.04 Docker image as build environment
2. Installs build tools (cmake, gcc, dpkg-dev, debhelper, etc.)
3. Downloads luvi-sigar runtime and builds lit package manager
4. Compiles the agent binary via CMake
5. Creates the Debian package via CPack
6. Copies `.deb` to `./dist/`

## Package Contents

- `/usr/bin/rackspace-monitoring-agent`
- `/etc/systemd/system/rackspace-monitoring-agent.service`
- `/etc/init.d/rackspace-monitoring-agent` (SysV)
- `/etc/init/rackspace-monitoring-agent.conf` (Upstart)
- `/etc/rackspace-monitoring-agent.conf.d/`
- `/var/lib/rackspace-monitoring-agent/`
- `/usr/lib/rackspace-monitoring-agent/plugins/`
- `/etc/logrotate.d/rackspace-monitoring-agent`

## Deploy to a VM

```bash
scp dist/rackspace-monitoring-agent-*.deb user@your-vm:/tmp/
ssh user@your-vm
sudo apt-get install -y /tmp/rackspace-monitoring-agent-*.deb
rackspace-monitoring-agent -v
```

## Troubleshooting

- Docker not running? `docker ps`
- Permission issues? `sudo chown -R $USER:$USER dist/`
- Need to debug the build? `make ubuntu24-shell`
- Out of disk? `docker system prune -a`
