FROM alpine:edge
MAINTAINER Bojan Cekrlic <verynotbad+github@gmail.com>

ENV PG_APP_HOME="/etc/docker-postgresql" \
    PG_VERSION=9.5.1 \
    PG_USER=postgres \
    PG_DATABASE=postgres \
    PG_HOME=/var/lib/postgresql \
    PG_RUNDIR=/run/postgresql \
    PG_LOGDIR=/var/log/postgresql \
    PG_CERTDIR=/etc/postgresql/certs \
    PG_LOG_ARCHIVING=false \
    PG_LOG_ARCHIVING_COMMAND="" \
    GOSU_VERSION=1.7 \
    LANG=en_US.utf8

ENV PG_BINDIR=/usr/bin/ \
    PG_DATADIR=${PG_HOME}/${PG_VERSION}/main \
    MUSL_LOCPATH=${LANG}

RUN mkdir -p /tmp/files/
COPY files/* /tmp/files/

RUN \
    export ARCH=$(uname -m) && \
    if [ "$ARCH" == "x86_64" ]; then export ARCH=amd64; fi && \
    if [[ "$ARCH" == "i*" ]]; then export ARCH=i386; fi && \
    if [[ "$ARCH" == "arm*" ]]; then export ARCH=armhf; fi && \
    echo "@edge http://nl.alpinelinux.org/alpine/edge/main" >> /etc/apk/repositories && \
    apk add --update acl bash curl tar perl python libuuid libxml2 libldap libxslt util-linux-dev python-dev perl-dev openldap-dev libxslt-dev libxml2-dev build-base linux-headers openssl-dev zlib-dev make gcc pcre-dev openssl-dev zlib-dev ncurses-dev readline-dev && \
    cd /tmp && \
    curl --retry 5 --max-time 300 --connect-timeout 10 -fSL https://ftp.postgresql.org/pub/source/v$PG_VERSION/postgresql-$PG_VERSION.tar.bz2 | tar xfj - && \
    cd /tmp/postgres* && \
    for i in /tmp/files/*.patch; do patch -p1 -i $i; done && \
    ./configure \
		--build=$CBUILD \
		--host=$CHOST \
		--prefix=/usr \
		--mandir=/usr/share/man \
		--with-openssl \
		--with-ldap \
		--with-libxml \
		--with-libxslt \
		--with-perl \
		--with-python \
		--with-libedit-preferred \
		--with-uuid=e2fs && \
	make world && make install install-docs && make -C contrib install && \
	install -D -m755 /tmp/files/postgresql.initd /etc/init.d/postgresql && \
	install -D -m644 /tmp/files/postgresql.confd /etc/conf.d/postgresql && \
	install -D -m755 /tmp/files/pg-restore.initd /etc/init.d/pg-restore && \
	install -D -m644 /tmp/files/pg-restore.confd /etc/conf.d/pg-restore && \
	mkdir /docker-entrypoint-initdb.d && \
	curl --retry 5 --max-time 120 --connect-timeout 5 -fsSL -o /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-${ARCH}" && \
	chmod +x /usr/local/bin/gosu && \
	apk del util-linux-dev openldap-dev libxslt-dev libxml2-dev build-base linux-headers python-dev perl-dev openssl-dev pcre-dev zlib-dev expat pkgconf pkgconfig make gcc pcre-dev openssl-dev zlib-dev ncurses-dev readline-dev musl-dev g++ fortify-headers && \
	(rm -rf /var/cache/apk/* > /dev/null || true) && (rm -rf /tmp/* > /dev/null || true)

COPY runtime/ ${PG_APP_HOME}/
COPY entrypoint.sh /sbin/entrypoint.sh
RUN chmod 755 /sbin/entrypoint.sh

RUN \
	mkdir -p ${PG_HOME}/wal-backup/ && \
	echo "#!/bin/bash" > ${PG_HOME}/wal-backup.sh && \
	echo -n "test ! -f $PG_HOME/wal-backup/\$1.bz2 && " >> ${PG_HOME}/wal-backup.sh && \
	echo "bzip2 \$2 > $PG_HOME/wal-backup/\$1.bz2) || exit 1" >> ${PG_HOME}/wal-backup.sh && \
	chmod 755 $PG_HOME/wal-backup.sh && \
	echo "=== Created wal-backup.sh ===" && cat $PG_HOME/wal-backup.sh

EXPOSE 5432/tcp
VOLUME ["${PG_HOME}", "${PG_RUNDIR}"]
WORKDIR ${PG_HOME}
ENTRYPOINT ["/sbin/entrypoint.sh"]
