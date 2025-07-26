job "traefik" {
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${attr.unique.hostname}"
    value     = "gajax"
  }

  group "traefik" {
    network {
      port "http" {
        static = 80
      }
      port "https" {
        static = 443
      }
      port "admin" {
        static = 8081
      }
    }

    service {
      name = "traefik-http"
      port = "https"

    }

    task "traefik" {
      driver = "docker"

      config {
        image        = "traefik:latest"
        network_mode = "host"

        volumes = [
          "local/traefik.toml:/etc/traefik/traefik.toml",
          "local/acme.json:/acme.json"
        ]
      }

      template {
        data        = <<EOF
CLOUDFLARE_API_KEY={{ key "cloudflare/key" }}
CLOUDFLARE_EMAIL={{ key "cloudflare/email" }}
EOF
        destination = "local/env"
        env         = true
      }

      template {
        data        = <<EOF
{}
EOF
        destination = "local/acme.json"
        perms       = "600"
      }


      template {
        data = <<EOF
[log]
  level = "INFO"

[metrics]
  [metrics.prometheus]

[api]
  dashboard = true
  insecure = false

[entryPoints]
  [entryPoints.web]
  address = ":80"

    [entryPoints.web.http.redirections.entryPoint]
    to = "websecure"
    scheme = "https"

  [entryPoints.websecure]
    address = ":443"
    asDefault = true

    [entryPoints.websecure.http.tls]
      certresolver = "lets-encrypt"

    [[entryPoints.websecure.http.tls.domains]]
      main = "gavinholahan.com"
      sans = ["*.gavinholahan.com"]

  [entryPoints.traefik]
    address = ":8081"

[providers.consulCatalog]
  prefix = "traefik"
  exposedByDefault = false
  [providers.consulCatalog.endpoint]
    address = "127.0.0.1:8500"
    scheme  = "http"

[providers.nomad]
  prefix = "traefik"
  exposedByDefault = false
  [providers.nomad.endpoint]
    address = "http://127.0.0.1:4646"

[certificatesResolvers.lets-encrypt.acme]
  email = "gholahan9@gmail.com"
  storage = "local/acme.json"
  [certificatesResolvers.lets-encrypt.acme.dnsChallenge]
    provider = "cloudflare"

[providers.file]
  filename = "/local/traefik_dynamic.toml"
EOF

        destination = "local/traefik.toml"
      }

      template {
        data        = <<EOF
[http]

[http.middlewares]

# handle redirects for short links
# NOTE: this is a consul template, add entries via consul kv
# create the middlewares with replacements for each redirect
{{ range $pair := tree "redirect/gavinholahan" }}
  [http.middlewares.redirect-{{ trimPrefix "redirect/gavinholahan/" $pair.Key }}.redirectRegex]
    regex = ".*"  # match everything - hosts are handled by the router
    replacement = "{{ $pair.Value }}"
    permanent = true
{{- end }}

[http.routers]

# create routers with middlewares for each redirect
{{ range $pair := tree "redirect/gavinholahan" }}
  [http.routers.{{ trimPrefix "redirect/gavinholahan/" $pair.Key }}-redirect]
    rule = "Host(`{{ trimPrefix "redirect/gavinholahan/" $pair.Key }}.gavinholahan.com`)"
    entryPoints = ["web", "websecure"]
    middlewares = ["redirect-{{ trimPrefix "redirect/gavinholahan/" $pair.Key }}"]
    service = "dummy-service"  # all routers need a service, this isn't used
    [http.routers.{{ trimPrefix "redirect/gavinholahan/" $pair.Key }}-redirect.tls]
{{- end }}

[http.serversTransports.ignorecert]
  insecureSkipVerify = true


[http.services]
  [http.services.dummy-service.loadBalancer]
    [[http.services.dummy-service.loadBalancer.servers]]
      url = "http://127.0.0.1"  # Dummy service - not used
EOF
        destination = "local/traefik_dynamic.toml"
      }
    }


  }
}
