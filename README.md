# Shopware Webspace Emulator

A Docker image that behaves like a classic shared webspace with Apache, mod_php, an SSH login and a MariaDB server. Use it to test SSH-based Shopware deployments without a real hosting account. Choose the default single-user image or the [two-user variant](#two-user-variant-for-deployer).

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

In the default image, Apache and PHP run as the SSH user `web`. Files deployed over SSH and files written by the shop (cache, media, uploads) have the same owner, like on a shared webspace.

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

## Two-user variant for Deployer

Use `ghcr.io/shopwarelabs/shopware-webspace-emulator:latest-http-user` in the run or Compose example. SSH still logs in as `web`, which owns `/var/www/shopware` and manages releases. Apache workers and mod_php run as `www-data`.

Configure the host in your `deploy.php`:

```php
host('webspace')
    ->set('hostname', 'localhost')
    ->set('port', 2222)
    ->set('remote_user', 'web')
    ->set('deploy_path', '/var/www/shopware')
    ->set('http_user', 'www-data')
    ->set('writable_mode', 'acl')
    ->set('writable_recursive', true);
```

The image includes `setfacl` and `getfacl`. Deployer's `deploy:writable` task grants `www-data` access to the paths in your recipe's `writable_dirs`. See the [Deployer writable recipe](https://deployer.org/docs/8.x/recipe/deploy/writable).

## Building locally

```bash
docker build -t shopware-webspace-emulator .
docker build --target http-user -t shopware-webspace-emulator:latest-http-user .
```

## Image tags

Images are built for `linux/amd64` and `linux/arm64` with [docker/github-builder](https://github.com/docker/github-builder), which signs SLSA provenance and SBOM attestations.

| Single-user tag | Two-user tag | Source |
|-----------------|--------------|--------|
| `latest` | `latest-http-user` | `main` branch, rebuilt weekly for security updates |
| `1.2.3`, `1.2` | `1.2.3-http-user`, `1.2-http-user` | Git tags `v1.2.3` |
| `sha-<commit>` | `sha-<commit>-http-user` | Every pushed commit |
