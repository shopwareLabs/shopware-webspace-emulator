# Shopware Webspace Emulator

A single Docker image that behaves like a classic shared webspace: Apache with mod_php, an SSH login and a MariaDB server. Use it to try out and test SSH-based Shopware deployments, such as the `shopware-cli project deploy` commands, without a real hosting account.

> [!WARNING]
> This image is for local development and testing only. Do not expose it to the internet.

## What's inside

Based on `debian:trixie-slim`, with all packages from Debian:

| Component | Details |
|-----------|---------|
| PHP | 8.4 with `mod_php` and the CLI, plus the extensions Shopware needs: intl, gd, mysql, zip, bcmath, xml, curl, mbstring, opcache, amqp, redis |
| Apache | Serves `/var/www/shopware/current/public`, follows symlinks, honours `.htaccess`; `mod_rewrite`, `mod_headers` and `mod_expires` enabled |
| SSH | Login as user `web` with public keys only; TCP forwarding enabled for database tunnels |
| MariaDB | Listens on `127.0.0.1:3306` inside the container only |
| Tools | Composer 2 (from `composer/composer`), git, unzip, rsync |

[supervisord](http://supervisord.org/) runs sshd, MariaDB and Apache. All logs go to the container output.

The SSH user `web` is also the user Apache and PHP run as. Files deployed over SSH and files written by the shop (cache, media, uploads) have the same owner, like on a shared webspace.

## Usage

```bash
docker run -d --name webspace \
  -p 2222:22 -p 8080:80 \
  -e SSH_PUBLIC_KEY="$(cat ~/.ssh/id_ed25519.pub)" \
  ghcr.io/shopwarelabs/shopware-webspace-emulator

ssh -p 2222 web@localhost
```

The shop is served at <http://localhost:8080> once `/var/www/shopware/current/public` exists. Until then, Apache logs a warning that the document root is missing.

### Docker Compose

```yaml
services:
  webspace:
    image: ghcr.io/shopwarelabs/shopware-webspace-emulator
    ports:
      - "2222:22"
      - "8080:80"
    environment:
      SSH_PUBLIC_KEY: |
        ssh-ed25519 AAAA... alice@example.com
        ssh-ed25519 AAAA... bob@example.com
    volumes:
      - webspace-files:/var/www/shopware
      - webspace-db:/var/lib/mysql

volumes:
  webspace-files:
  webspace-db:
```

### Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SSH_PUBLIC_KEY` | | One or more public keys, one per line. Replaces `/home/web/.ssh/authorized_keys` on every start. |
| `MYSQL_DATABASE` | `shopware` | Database created on start |
| `MYSQL_USER` | `shopware` | Database user with full access to `MYSQL_DATABASE` |
| `MYSQL_PASSWORD` | `shopware` | Password of `MYSQL_USER` |

Instead of `SSH_PUBLIC_KEY`, you can mount a file at `/home/web/.ssh/authorized_keys`.

### Volumes

| Path | Content |
|------|---------|
| `/var/www/shopware` | Deployment root: releases, shared files and the `current` symlink |
| `/var/lib/mysql` | MariaDB data |

## Deploying with shopware-cli

Add an SSH environment to `.config/shopware-project.yml`:

```yaml
environments:
  webspace:
    type: ssh
    url: http://localhost:8080
    ssh:
      host: localhost
      port: 2222
      user: web
      directory: /var/www/shopware/current
```

Then initialize the target:

```bash
shopware-cli project deploy init -e webspace
```

When asked for the database, use `mysql://shopware:shopware@127.0.0.1:3306/shopware`. The address is resolved inside the container, and shopware-cli tunnels database connections over SSH automatically.

## Building locally

```bash
docker build -t shopware-webspace-emulator .
```

## Image tags

Images are built for `linux/amd64` and `linux/arm64` with [docker/github-builder](https://github.com/docker/github-builder), which signs SLSA provenance and SBOM attestations.

| Tag | Source |
|-----|--------|
| `latest` | `main` branch, rebuilt weekly for security updates |
| `1.2.3`, `1.2` | Git tags `v1.2.3` |
| `sha-<commit>` | Every pushed commit |
