# syntax=docker/dockerfile:1
#
# Local stand-in for a classic shared webspace: Apache + mod_php, an SSH login
# and a MariaDB server in one container, supervised by supervisord.
# See README.md for usage.

FROM debian:trixie-slim AS base

COPY --from=composer/composer:2-bin /composer /usr/local/bin/composer

RUN <<EOF
set -eux
apt-get update
apt-get install -y --no-install-recommends \
    apache2 libapache2-mod-php \
    php-cli php-mysql php-intl php-gd php-zip php-bcmath php-xml php-curl php-mbstring php-opcache php-amqp php-redis \
    git unzip rsync ca-certificates \
    openssh-server mariadb-server supervisor
rm -rf /var/lib/apt/lists/*

useradd --create-home --shell /bin/bash web
install -d -o web -g web -m 0755 /var/www/shopware
install -d -o web -g web -m 0700 /home/web/.ssh
mkdir -p /run/sshd
rm -f /etc/ssh/ssh_host_*

a2enmod rewrite headers expires

php_version=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
for sapi in apache2 cli; do
    ln -s /etc/php/shopware.ini "/etc/php/$php_version/$sapi/conf.d/99-shopware.ini"
done
EOF

COPY <<EOF /etc/php/shopware.ini
memory_limit = 512M
upload_max_filesize = 64M
post_max_size = 64M
max_execution_time = 120
opcache.memory_consumption = 256
opcache.max_accelerated_files = 20000
EOF

COPY <<EOF /etc/apache2/sites-available/000-default.conf
ServerName localhost
<VirtualHost *:80>
    DocumentRoot /var/www/shopware/current/public
    <Directory /var/www/shopware>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog /dev/stderr
    CustomLog /dev/stdout combined
</VirtualHost>
EOF

COPY <<EOF /etc/ssh/sshd_config.d/webspace.conf
PasswordAuthentication no
PermitRootLogin no
AllowUsers web
AllowTcpForwarding yes
MaxSessions 32
EOF

COPY <<EOF /etc/supervisor/conf.d/webspace.conf
[supervisord]
nodaemon=true
user=root
logfile=/dev/null
logfile_maxbytes=0
pidfile=/run/supervisord.pid

[program:sshd]
command=/usr/sbin/sshd -D -e
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
redirect_stderr=true

[program:mariadb]
command=/usr/sbin/mariadbd --user=mysql --bind-address=127.0.0.1
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
redirect_stderr=true

[program:mariadb-setup]
command=/usr/local/bin/webspace-database-setup
autorestart=false
startsecs=0
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
redirect_stderr=true

[program:apache2]
command=/usr/sbin/apache2ctl -D FOREGROUND
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
redirect_stderr=true
EOF

COPY --chmod=0755 <<'EOF' /usr/local/bin/webspace-database-setup
#!/bin/sh
set -eu
until mariadb-admin ping --silent 2>/dev/null; do sleep 1; done
mariadb <<SQL
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'localhost' IDENTIFIED BY '${MYSQL_PASSWORD}';
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'127.0.0.1' IDENTIFIED BY '${MYSQL_PASSWORD}';
GRANT ALL ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'localhost', '${MYSQL_USER}'@'127.0.0.1';
SQL
echo "Database ${MYSQL_DATABASE} is ready"
EOF

COPY --chmod=0755 <<'EOF' /usr/local/bin/webspace-entrypoint
#!/bin/sh
set -eu

if [ -n "${SSH_PUBLIC_KEY:-}" ]; then
    printf '%s\n' "$SSH_PUBLIC_KEY" > /home/web/.ssh/authorized_keys
fi
if [ -f /home/web/.ssh/authorized_keys ]; then
    chown web:web /home/web/.ssh/authorized_keys
    chmod 0600 /home/web/.ssh/authorized_keys
else
    echo "No SSH key configured: set SSH_PUBLIC_KEY or mount /home/web/.ssh/authorized_keys" >&2
fi
ssh-keygen -A

if [ ! -d /var/lib/mysql/mysql ]; then
    mariadb-install-db --user=mysql --datadir=/var/lib/mysql --skip-test-db >/dev/null
fi
install -d -o mysql -g mysql /run/mysqld

exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
EOF

ENV MYSQL_DATABASE=shopware \
    MYSQL_USER=shopware \
    MYSQL_PASSWORD=shopware

VOLUME ["/var/www/shopware", "/var/lib/mysql"]
EXPOSE 22 80

ENTRYPOINT ["webspace-entrypoint"]

# Keep Debian's www-data Apache user and provide Deployer's ACL and detection tools.
FROM base AS http-user
RUN apt-get update \
    && apt-get install -y --no-install-recommends acl procps \
    && rm -rf /var/lib/apt/lists/*

# The default build runs Apache as the SSH user.
FROM base AS single-user
RUN sed -i 's/^export APACHE_RUN_USER=.*/export APACHE_RUN_USER=web/; s/^export APACHE_RUN_GROUP=.*/export APACHE_RUN_GROUP=web/' /etc/apache2/envvars
