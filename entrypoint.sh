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


# default behaviour is to launch postgres
if [[ -z ${1} ]]; then
  setup_postgres
  run_startup_scripts

  echo "Starting PostgreSQL ${PG_VERSION}..."
  exec gosu postgres ${PG_BINDIR}/postgres -D ${PG_DATADIR} ${EXTRA_ARGS}
else
  # This second flow is only usable with DOCKER EXEC or DOCKER RUN.
  # We will check how we are executed (basically if postgres is running or not)
  # Please note that IT IS A VERY BAD IDEA to run anothe posgres instance
  # From a RUNNING postgres directory. So, to sum up:
  # - use "docker exec" to enter a running instance
  # - use "docker run" to modify the data of an existing (shut-down) instance, if you try to do it on 
  #   an already running instance, YOU WILL CRASH IT.
  [[ ${DEBUG} == true ]] && echo "Verifying if we are running from an existing container..."
  [[ ${DEBUG} == true ]] && echo gosu postgres pg_ctl -D "$PG_DATADIR" status && gosu postgres pg_ctl -D "$PG_DATADIR" status
  [[ ${DEBUG} == true ]] && echo exec gosu postgres "$@"

  if [ `gosu postgres pg_ctl -D "$PG_DATADIR" status 2>&1 | grep -q "server is running"` ]; then
    # Support the "exec" option

    [ ${DEBUG} == true ]] && "We're in an existing container, execute the command: $@"
    exec gosu postgres "$@"
  else
    # Support the "run" option

    echo "Starting PostgreSQL ${PG_VERSION}..."
    start_postgres_daemon
    exec gosu postgres "$@"
    stop_postgres_daemon
  fi
fi

