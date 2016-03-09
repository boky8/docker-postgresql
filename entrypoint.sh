#!/bin/bash
set -e
source ${PG_APP_HOME}/functions

[[ ${DEBUG} == true ]] && set -x

# allow arguments to be passed to postgres
if [[ ${1:0:1} = '-' ]]; then
  EXTRA_ARGS="$@"
  set --
elif [[ ${1} == postgres || ${1} == $(which postgres) ]]; then
  EXTRA_ARGS="${@:2}"
  set --
fi

start_postgres_daemon() {
  # internal start of server in order to allow set-up using psql-client   
  # does not listen on TCP/IP and waits until start finishes
  gosu postgres pg_ctl -D "$PG_DATADIR" -o "-c listen_addresses=''" -w start
}

stop_postgres_daemon() {
  # Stop the daemon
  gosu postgres pg_ctl -D "$PG_DATADIR" -s -m fast -w stop
  set_postgresql_param "listen_addresses" "*" quiet
}

setup_postgres() {
  map_uidgid

  create_datadir
  create_certdir
  create_logdir
  create_rundir

  set_resolvconf_perms

  configure_postgresql
}

run_startup_scripts() {
  # Run scripts in much the same manner that the official image does
  if [ -f /docker-entrypoint-initdb.d/* ]; then
    start_postgres_daemon

    : ${PG_USER:=postgres}
    : ${PG_DATABASE:=$PG_USER}
    export PG_USER PG_DATABASE

    for f in /docker-entrypoint-initdb.d/*; do
      case "$f" in
        *.sh)
          echo "$0: running $f"
          . "$f" 
          ;;
        *.sql) 
          echo "$0: running $f"
          psql -v ON_ERROR_STOP=1 --username "$PG_USER" --dbname "$PG_DATABASE" < "$f"
          echo 
          ;;
        *)
          echo "$0: ignoring $f" 
          ;;
        esac
    echo
    done

    stop_postgres_daemon
  fi
}


# We run the setup and the startup scripts every time, even if the user is running a specific command.
# We do this to support use cases where a user, for example, has startup scripts to prepopulate the
# database and then runs "docker ... psql" directly to connect to the database. If we didn't do it,
# he would need to start the docker image once and then restart it with "psql".
setup_postgres
run_startup_scripts


# default behaviour is to launch postgres
if [[ -z ${1} ]]; then
  echo "Starting PostgreSQL ${PG_VERSION}..."
  exec gosu postgres ${PG_BINDIR}/postgres -D ${PG_DATADIR} ${EXTRA_ARGS}
else
  start_postgres_daemon
  exec gosu postgres "$@"
  stop_postgres_daemon
fi

