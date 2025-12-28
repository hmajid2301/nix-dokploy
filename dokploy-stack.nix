# Docker stack configuration for Dokploy
{ cfg, lib }:
{
  version = "3.8";

  services = lib.optionalAttrs (!cfg.database.useHostPostgres) {
    postgres = {
      image = "postgres:16";
      environment = {
        POSTGRES_USER = "dokploy";
        POSTGRES_PASSWORD = "\${POSTGRES_PASSWORD}";
        POSTGRES_DB = "dokploy";
      };
      volumes = [
        "dokploy-postgres-database:/var/lib/postgresql/data"
      ];
      networks = {
        dokploy-network = {
          aliases = ["dokploy-postgres"];
        };
      };
      deploy = {
        placement.constraints = ["node.role == manager"];
        restart_policy.condition = "any";
      };
    } // lib.optionalAttrs (cfg.database.port != null) {
      ports = [ "${toString cfg.database.port}:5432" ];
    };
  } // {

    redis = {
      image = "redis:7";
      volumes = [
        "redis-data-volume:/data"
      ];
      networks = {
        dokploy-network = {
          aliases = ["dokploy-redis"];
        };
      };
      deploy = {
        placement.constraints = ["node.role == manager"];
        restart_policy.condition = "any";
      };
    };

    dokploy = {
      image = cfg.image;
      environment = {
        ADVERTISE_ADDR = "\${ADVERTISE_ADDR}";
      } // lib.optionalAttrs cfg.database.useHostPostgres {
        DATABASE_URL = "postgresql:///dokploy?host=/run/postgresql&user=dokploy&password=\${POSTGRES_PASSWORD}";
      };
      networks = {
        dokploy-network = {
          aliases = ["dokploy-app"];
        };
      };
      volumes = [
        "/var/run/docker.sock:/var/run/docker.sock"
        "${cfg.dataDir}:/etc/dokploy"
        "dokploy-docker-config:/root/.docker"
      ] ++ lib.optionals cfg.database.useHostPostgres [
        "/run/postgresql:/run/postgresql"
      ];
      depends_on = if cfg.database.useHostPostgres then ["redis"] else ["postgres" "redis"];
      deploy = {
        replicas = 1;
        placement.constraints = ["node.role == manager"];
        update_config = {
          parallelism = 1;
          order = "stop-first";
        };
        restart_policy.condition = "any";
      };
    } // lib.optionalAttrs (cfg.port != null) {
      ports = [ cfg.port ];
    };
  };

  networks = {
    dokploy-network = {
      name = "dokploy-network";
      driver = "overlay";
      attachable = true;
    };
  };

  volumes = lib.optionalAttrs (!cfg.database.useHostPostgres) {
    dokploy-postgres-database = {};
  } // {
    redis-data-volume = {};
    dokploy-docker-config = {};
  };
}