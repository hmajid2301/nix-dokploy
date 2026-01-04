# nix-dokploy

[![Build](https://github.com/el-kurto/nix-dokploy/actions/workflows/build.yml/badge.svg)](https://github.com/el-kurto/nix-dokploy/actions/workflows/build.yml)

A **NixOS module** that runs [Dokploy](https://dokploy.com/) (a self-hosted PaaS / deployment platform) using declarative systemd units.

⚠️ This module is **NixOS-only**. It integrates directly with `systemd.services` and `systemd.tmpfiles`, so it will not work on nix-darwin, home-manager, or plain nixpkgs environments.

## ✨ Features

- `dokploy-stack.service` and `dokploy-traefik.service` systemd units
- Proper service ordering (`docker.service` → `dokploy-stack.service` → `dokploy-traefik.service`)
- Automatic state directory creation via `systemd.tmpfiles`
- Clean `ExecStop` + `ExecStopPost` handling (containers removed on stop/restart)
- No reliance on upstream shell scripts

![Service Dependencies](./Readme/systemctl-list-dependencies-dokploy.png)
![Service Status](./Readme/systemctl-status-dokploy.png)
![Docker Stack](./Readme/docker-stack-ps-dokploy.png)

## 📋 Requirements

- Docker must be enabled
- Docker live-restore must be disabled (required for swarm)
- Rootless Docker is not supported (swarm limitation)

## 🚀 Quick Start

Add to your `flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-dokploy.url = "github:el-kurto/nix-dokploy";
  };

  outputs = { self, nixpkgs, nix-dokploy, ... }: {
    nixosConfigurations.my-server = nixpkgs.lib.nixosSystem {
      modules = [
        nix-dokploy.nixosModules.default
        {
          # Required dependencies
          virtualisation.docker.enable = true;
          virtualisation.docker.daemon.settings.live-restore = false;

          # Enable Dokploy
          services.dokploy.enable = true;
        }
      ];
    };
  };
}
```

That's it! Dokploy will be available at `http://your-server-ip:3000`

## ⚙️ Configuration Options

### Basic Options

| Option | Default | Description |
|--------|---------|-------------|
| `services.dokploy.dataDir` | `/etc/dokploy` | Data directory for Dokploy |
| `services.dokploy.image` | `dokploy/dokploy:v0.25.11` | Dokploy Docker image |
| `services.dokploy.port` | `"3000:3000"` | Port binding for web UI (⚠️ see note) |
| `services.dokploy.lxc` | `false` | Enable LXC compatibility (required for Proxmox) |
| `services.dokploy.database.useHostPostgres` | `false` | Use host PostgreSQL instead of container |
| `services.dokploy.database.port` | `null` | External port for containerized PostgreSQL |
| `services.dokploy.traefik.enable` | `true` | Enable Dokploy-managed Traefik container |
| `services.dokploy.traefik.image` | `traefik:v3.6.1` | Traefik Docker image |
| `services.dokploy.traefik.extraArgs` | `[]` | Extra arguments for Traefik container |
| `services.dokploy.traefik.ports.http` | `80` | HTTP port for Traefik |
| `services.dokploy.traefik.ports.https` | `443` | HTTPS port for Traefik (TCP) |
| `services.dokploy.traefik.ports.httpsUdp` | `443` | HTTPS port for Traefik (UDP/HTTP3) |
| `services.dokploy.swarm.autoRecreate` | `false` | Auto-recreate swarm when IP change is detected during service restart |

### Swarm Advertise Address

Control which IP address Docker Swarm advertises to other nodes:

```nix
# Use private IP (default - recommended for security)
services.dokploy.swarm.advertiseAddress = "private";

# Use public IP (see security note below)
services.dokploy.swarm.advertiseAddress = "public";

# Use a specific IP
services.dokploy.swarm.advertiseAddress = {
  command = "echo 192.168.1.100";
};

# Use Tailscale IP (recommended for multi-node)
services.dokploy.swarm.advertiseAddress = {
  command = "tailscale ip -4 | head -n1";
  extraPackages = [ pkgs.tailscale ];
};

# Auto-recreate swarm when IP change is detected during service restart
services.dokploy.swarm.autoRecreate = true;
```

**Note on Multi-Node Swarms:**

Using `"public"` will expose swarm management ports (2377, 7946, 4789) to the internet. It seems unwise to do this unless you really know what you're doing and have properly secured these ports.

Some viable secure alternatives include:

- **Tailscale or WireGuard**: Use VPN IPs as advertise addresses for secure node-to-node communication
- **Private networks**: Use private IPs when nodes are on the same network
- **Cloud security groups**: Restrict access to specific trusted IPs if public addressing is necessary

For single-node setups (the most common case), the default `"private"` setting should work well. If your IP changes frequently (Tailscale, DHCP), enable `swarm.autoRecreate` to automatically handle address changes.

### Web UI Port Configuration

⚠️ **Recommendation**: Disable port 3000 once Traefik is configured to reverse proxy Dokploy.

1. Deploy with default port for initial configuration
2. Access Dokploy UI and configure Traefik reverse proxy
3. Redeploy with `port = null` to disable direct access

```nix
# Default - Exposes port 3000 to all interfaces (bypasses firewall!)
services.dokploy.port = "3000:3000";

# Disable direct port access (access through Traefik only)
services.dokploy.port = null;
```

### Using Host PostgreSQL

Instead of the containerized PostgreSQL, you can use NixOS's PostgreSQL service via Unix sockets:

```nix
services.dokploy = {
  enable = true;
  database.useHostPostgres = true;
};

# Configure PostgreSQL with required database and user
services.postgresql = {
  enable = true;
  ensureDatabases = [ "dokploy" ];
  ensureUsers = [{
    name = "dokploy";
    ensureDBOwnership = true;
  }];
  # Set authentication - use md5 for password auth
  authentication = ''
    local dokploy dokploy md5
  '';
};

# Set the password for the dokploy user (required by Dokploy)
# Note: The password must be set to Dokploy's hardcoded value
# You can do this with: sudo -u postgres psql -c "ALTER USER dokploy PASSWORD 'amukds4wi9001583845717ad2';"
```

**Benefits of using host PostgreSQL:**
- No containerized database
- Use NixOS's declarative PostgreSQL configuration
- Connect via Unix sockets (no network overhead)
- Easier backups with NixOS services
- Integrate with existing PostgreSQL monitoring

**Note:** Dokploy hardcodes the database password in its source code. You must set the password to `amukds4wi9001583845717ad2` for the `dokploy` user.

### Using Host Traefik

Disable the bundled Traefik container and use your own instance:

```nix
services.dokploy = {
  enable = true;
  traefik.enable = false;  # Disable bundled Traefik
};

# Example: Use NixOS Traefik service
services.traefik = {
  enable = true;
  staticConfigOptions = {
    providers.docker = {
      endpoint = "unix:///var/run/docker.sock";
      network = "dokploy-network";
      exposedByDefault = false;
    };
    entryPoints = {
      web.address = ":80";
      websecure.address = ":443";
    };
  };
};

# Ensure Traefik can connect to the dokploy-network
# You may need to manually attach Traefik to the network:
# docker network connect dokploy-network <traefik-container-name>
```

**Benefits of using host Traefik:**
- Use existing Traefik configuration
- Centralized reverse proxy management
- Share Traefik across multiple services
- Use NixOS declarative config instead of Dokploy's files

### Configurable Traefik/PostgreSQL Ports

You can customize the ports for the bundled services:

```nix
services.dokploy = {
  # Traefik ports
  traefik.ports = {
    http = 8080;        # Use port 8080 for HTTP
    https = 8443;       # Use port 8443 for HTTPS
    httpsUdp = null;    # Disable HTTP/3 (UDP)
  };

  # PostgreSQL port (expose to host)
  database.port = 5432;  # Expose PostgreSQL on port 5432
};
```

Set ports to `null` to disable port binding.

### Traefik Configuration

You can pass extra arguments to the Traefik container using `traefik.extraArgs`. This is useful for passing environment variables or mounting additional volumes.

```nix
services.dokploy.traefik.extraArgs = [
  "--log.level=DEBUG"
  "-e CF_API_EMAIL=user@example.com"
  "-e CF_API_KEY=your_api_key"
  "-v /path/to/certs:/certs"
];
```

## 📄 License

This NixOS module is licensed under the [MIT License](./LICENSE) - use it freely without restrictions.

**Note:** Dokploy itself is licensed under [Apache License 2.0 with additional terms](https://github.com/Dokploy/dokploy/blob/canary/LICENSE.MD). This module simply wraps Dokploy for NixOS deployment.
