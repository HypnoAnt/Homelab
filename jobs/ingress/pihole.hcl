job "pihole" {
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${attr.unique.hostname}"
    value     = "gajax"
  }

  group "pihole" {
    network {
      port "dns" {
        static = 53
        to = 53
      }
      port "http" {
        to = 80
      }
    }

    service {
      name = "pihole"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.pihole.rule=Host(`pihole.gavinholahan.com`)",
        "traefik.http.routers.pihole.entrypoints=websecure",
        "traefik.http.routers.pihole.tls.certresolver=lets-encrypt",

      ]
    }

    task "pihole" {
      driver = "docker"

      config {
        image = "pihole/pihole:latest"
        ports = ["dns", "http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}/pihole:/etc/pihole",
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}/dnsmasq.d:/etc/dnsmasq.d"
        ]
      }

      template {
        data        = <<EOF
TZ='Europe/Dublin'
FTLCONF_webserver_api_password={{ key "pihole/password" }}
FTLCONF_dns_listeningMode= 'all'
EOF
        destination = "local/env"
        env         = true
      }
    }
  }
}
