job "unifi" {
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${attr.unique.hostname}"
    value     = "agamemnon"
  }

  group "unifi" {
    network {
      port "db" {
        to         = 27017
        static     = 27017
      }

      port "dns" {
        to         = 53
        static     = 53
      }
      port "stun" {
        to         = 3478
        static     = 3478
      }
      port "device_comm" {
        to         = 8080
        static     = 8080
      }
      port "web_gui" {
        to         = 8443
        static     = 8443
      }
      port "discovery" {
        to         = 10001
        static     = 10001
      }

      port "discovery-l2" {
        to     = 1900
        static     = 1900
      }
      port "guest-https" {
        to     = 8843
        static     = 8843
      }
      port "guest-http" {
        to     = 8880
        static     = 8880
      }
      port "mobile-throughput" {
        to     = 6789
        static     = 6789
      }
      port "syslog" {
        to     = 5514
        static     = 5514
      }

    }

    service {
      name = "unifi"
      port = "web_gui"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.unifi.rule=Host(`unifi.gavinholahan.com`)",
        "traefik.http.routers.unifi.entrypoints=web,websecure",
        "traefik.http.routers.unifi.tls.certresolver=lets-encrypt",
        "traefik.http.routers.unifi.middlewares=unifi-https-redirect",
        "traefik.http.services.unifi.loadbalancer.server.port=8443",
        "traefik.http.services.unifi.loadbalancer.serverstransport=ignorecert@",
        "traefik.http.services.unifi.loadbalancer.server.scheme=https"
      ]

    }

    task "unifi-controller" {
      driver = "docker"

      config {
        image = "lscr.io/linuxserver/unifi-network-application:latest"
        ports = ["dns", "stun", "device_comm", "web_gui", "discovery", "discovery-l2", "guest-https", "guest-http", "mobile-throughput", "syslog"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}/config:/config"
        ]
      }

      resources {
        cpu    = 300
        memory = 800
      }

      template {
        data        = <<EOF
PUID=1000
PGID=1000
TZ=Etc/UTC
MONGO_HOST={{ env "NOMAD_IP_db" }}
MONGO_PORT={{ env "NOMAD_HOST_PORT_db" }}
MONGO_USER={{ key "unifi/db/user" }}
MONGO_PASS={{ key "unifi/db/pass" }}
MONGO_DBNAME={{ key "unifi/db/name" }}
MONGO_AUTHSOURCE=admin
MEM_LIMIT=1024
MEM_STARTUP=1024
MONGO_TLS=
EOF
        destination = "local/env"
        env         = true
      }
    }

    task "mongodb" {
      driver = "docker"

      lifecycle {
        hook    = "prestart"
        sidecar = true
      }


      config {
        image = "docker.io/mongo:4.4"
        ports = ["db"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}/db:/data/db",
          "local/init-mongo.sh:/docker-entrypoint-initdb.d/init-mongo.sh:ro"
        ]
      }

      resources {
        cpu    = 300
        memory = 300
      }
      template {
        data        = <<EOF
MONGO_INITDB_ROOT_USERNAME=root
MONGO_INITDB_ROOT_PASSWORD={{ key "unifi/db/root-passwd" }}
MONGO_USER={{ key "unifi/db/user" }}
MONGO_PASS={{ key "unifi/db/pass" }}
MONGO_DBNAME={{ key "unifi/db/name" }}
MONGO_AUTHSOURCE=admin
EOF
        destination = "local/env"
        env         = true
      }

      template {
        data        = <<EOF
#!/bin/bash

if which mongosh > /dev/null 2>&1; then
  mongo_init_bin='mongosh'
else
  mongo_init_bin='mongo'
fi
"${mongo_init_bin}" <<EOMONGO
use ${MONGO_AUTHSOURCE}
db.auth("${MONGO_INITDB_ROOT_USERNAME}", "${MONGO_INITDB_ROOT_PASSWORD}")
db.createUser({
  user: "${MONGO_USER}",
  pwd: "${MONGO_PASS}",
  roles: [
    { db: "${MONGO_DBNAME}", role: "dbOwner" },
    { db: "${MONGO_DBNAME}_stat", role: "dbOwner" },
    { db: "${MONGO_DBNAME}_audit", role: "dbOwner" }
  ]
})
EOMONGO
EOF
        destination = "local/init-mongo.sh"
      }
    }
  }
}
