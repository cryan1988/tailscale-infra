# tailscale-download

A shell script that downloads Tailscale packages for any platform with changelog information from the official RSS feed.

## Requirements

- `curl`
- `jq`
- `python3` (stdlib only)

## Usage

```bash
# Auto-detect platform, download latest stable release
./tailscale-download.sh

# Show changelog and recent releases without downloading
./tailscale-download.sh -l

# Changelog only
./tailscale-download.sh -c

# Specific platform
./tailscale-download.sh -p linux-arm64

# Specific version
./tailscale-download.sh -v 1.94.2 -p macos-pkg

# Unstable channel
./tailscale-download.sh -u

# Show 20 recent changelog entries
./tailscale-download.sh -c -n 20
```

## CLI reference

| Flag | Default | Description |
|------|---------|-------------|
| `-o DIR` | `~/Downloads` | Output directory |
| `-p PLATFORM` | auto-detect | Target platform (see below) |
| `-v VERSION` | latest | Specific version, e.g. `1.96.4` |
| `-n NUM` | `10` | Number of changelog entries to show |
| `-u` | off | Use unstable channel |
| `-l` | off | List recent releases only, skip download |
| `-c` | off | Show changelog only, skip download |
| `--no-verify` | off | Skip SHA256 checksum verification |

## Supported platforms

| `-p` value | Package |
|------------|---------|
| `macos-pkg` | `Tailscale-{version}-macos.pkg` |
| `macos-zip` | `Tailscale-{version}-macos.zip` |
| `linux-amd64` | `tailscale_{version}_amd64.tgz` |
| `linux-arm64` | `tailscale_{version}_arm64.tgz` |
| `linux-arm` | `tailscale_{version}_arm.tgz` |
| `linux-386` | `tailscale_{version}_386.tgz` |
| `windows-exe` | `tailscale-setup-{version}.exe` |
| `windows-msi-amd64` | `tailscale-setup-{version}-amd64.msi` |
| `windows-msi-arm64` | `tailscale-setup-{version}-arm64.msi` |

Platform is auto-detected from `uname` when `-p` is not specified.

## Notes

- Packages are downloaded from `pkgs.tailscale.com`. Per-platform latest versions are resolved independently — macOS and Linux may be on different patch versions.
- SHA256 checksums are verified automatically after each download (use `--no-verify` to skip).
- On macOS, the script offers to open the `.pkg` installer after download.
- Packages are skipped (with a prompt to overwrite) if they already exist in the output directory.
