job "vaultwarden" {
  datacenters = ["dc1"]
  type        = "service"

  group "vaultwarden" {
    count = 1

    network {
      port "http" {
        to = 80
      }
      port "db" {
        to = 5432
      }
    }

    service {
      name = "vaultwarden"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.vaultwarden.rule=Host(`vault.gavinholahan.com`)",
        "traefik.http.routers.vaultwarden.entrypoints=websecure",
        "traefik.http.routers.vaultwarden.tls.certresolver=lets-encrypt",
      ]
    }

    task "vaultwarden" {
      driver = "docker"

      config {
        image = "vaultwarden/server:latest-alpine"
        ports = ["http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}/data:/data",
          "/etc/localtime:/etc/localtime:ro"
        ]
      }

      template {
        data = <<EOF
DOMAIN=https://vault.gavinholahan.com
DATABASE_URL=postgresql://{{ key "vaultwarden/db/user" }}:{{ key "vaultwarden/db/password" }}@{{ env "NOMAD_ADDR_db" }}/{{ key "vaultwarden/db/name" }}
SIGNUPS_ALLOWED=true
INVITATIONS_ALLOWED=true

# This is not the actual token, but a hash of it. Vaultwarden does not like the actual token.
ADMIN_TOKEN={{ key "vaultwarden/admin/hash" }}
EOF

        destination = "local/env"
        env         = true
      }

      resources {
        cpu    = 500
        memory = 500
      }
    }

    task "db" {
      driver = "docker"

      config {
        image = "postgres:17-alpine"
        ports = ["db"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}/data/:/var/lib/postgresql/data",
        ]
      }

      template {
        data        = <<EOH
POSTGRES_PASSWORD={{ key "vaultwarden/db/password" }}
POSTGRES_USER={{ key "vaultwarden/db/user" }}
POSTGRES_NAME={{ key "vaultwarden/db/name" }}
EOH
        destination = "local/db.env"
        env         = true
      }
    }
  }
}
