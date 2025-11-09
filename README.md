<p align="center">
  <img width="250" src="https://upload.wikimedia.org/wikipedia/en/1/15/Pi-hole_vector_logo.svg">
</p>
<p align="center">
  <img alt="macOS" src="https://img.shields.io/badge/Platform-macOS-black?logo=apple&logoColor=white"> 
  <img alt="Shell" src="https://img.shields.io/badge/Shell-bash-4EAA25?logo=gnu-bash&logoColor=white"> 
  <img alt="Requires" src="https://img.shields.io/badge/Requires-Docker-2496ED?logo=docker&logoColor=white">
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/License-MIT-blue.svg"></a>
</p>

## Quick Start

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/tfeuerbach/pihole-bootstrapper/master/pihole-bootstrapper.sh)"
```

# Pi-hole Bootstrapper for macOS

A simple, user-friendly script to run a local instance of Pi-hole on macOS using Docker. This tool aims to automate the entire setup and any of the *contingencies* that may arise when installing new software including network configuration, Pi-hole configuration, dependency resolution, etc. so you can enjoy system-wide ad-blocking with a single command.

**This is ideal for personal, system-wide ad-blocking on a single machine at times when you don't have backend and/or physical access to the network you're using. Some examples of this might be when you're at a hotel, school, airport, Dalaran, etc.**

<small><em>Dedicated to Trevor.</em></small>

## Prerequisites

- **macOS:** This script is designed specifically for macOS and uses `networksetup`.
- **(Optional) Homebrew:** If you don't have Homebrew or Docker Desktop installed, the wizard will offer to install them for you automatically.

## How to Use

Run the script from your terminal:

```bash
./pihole-bootstrapper.sh
```

This will launch an interactive wizard that guides you through the following:

- **Install/Start Pi-Hole:** If Pi-hole is not installed, this will guide you through a first-time setup, including choosing an upstream DNS provider. If Pi-hole is already installed but stopped, this will simply start it and configure your network.
- **Stop Pi-Hole:** This will stop the Pi-hole container and revert your network settings without deleting any of your Pi-hole configurations or blocklists.
- **Uninstall Pi-Hole:** This will completely remove the Pi-hole container and all of its related configuration files from your system.

The script will print the admin password for the web interface upon successful setup. By default, the admin portal will be available at `http://pihole.local/admin` with the password `pihole`. You can change this password at the top of the `pihole-bootstrapper.sh` script.

## Advanced Usage

### Debug Mode

If you encounter unexpected issues, you can run the script with the `-d` flag to enable debug mode. This will print a detailed trace of every command the script executes, which can be helpful for troubleshooting.

```bash
./pihole-bootstrapper.sh -d
```

## Future Wishlist

- Windows PowerShell bootstrapper
- Linux bootstrapper (Debian/Ubuntu via apt; Fedora/RHEL via dnf)
- Optional DoH upstream presets (cloudflared/unbound)
- Compose file export for power users

Got Windows/PowerShell skill or non‑UNIX experience? Please fork and open a PR — I **detest** development on Windows systems and as a result it is strongest weakness. I also hate Active Directory and everything it stands for, not that AD has anything to do with this.

## Development

- Lint: run `shellcheck pihole-bootstrapper.sh`
- Optional CI: GitHub Actions with ShellCheck for PRs/commits
- Style: POSIX-friendly bash, set -e, minimal prompts, clear output

## License

MIT — see [LICENSE](LICENSE).
