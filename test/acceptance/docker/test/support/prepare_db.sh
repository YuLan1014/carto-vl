#!/bin/sh

# this script prepare database and redis instance to run accpetance test
#
# NOTE: assumes existance of a "template_postgis"
# NOTE2: use PG* environment variables to control who and where
#
# NOTE3: a side effect of the db preparation is the persistent creation
#        of two database roles which will be valid for the whole cluster
#        TODO: fix that
#

git clone https://github.com/CartoDB/cartodb-postgresql.git ;

# Install cartodb extension
cd cartodb-postgresql
make all install

cd -

PREPARE_REDIS=yes
PREPARE_PGSQL=yes

while [ -n "$1" ]; do
  OPTION=$(echo "$1" | tr -d '[:space:]')
  if [[ "$OPTION" == "--skip-pg" ]]; then
    PREPARE_PGSQL=no
    shift; continue
  elif [[ "$OPTION" == "--skip-redis" ]]; then
    PREPARE_REDIS=no
    shift; continue
  else
    shift; continue;
  fi
done

die() {
        msg=$1
        echo "${msg}" >&2
        exit 1
}

# This is where postgresql connection parameters are read from
TESTENV=../../config/environments/test.js
if [ \! -r ${TESTENV} ]; then
  echo "Cannot read ${TESTENV}" >&2
  exit 1
fi

TESTUSERID=1

TESTUSER=`node -e "console.log(require('${TESTENV}').postgres_auth_user || '')"`
if test -z "$TESTUSER"; then
  echo "Missing postgres_auth_user from ${TESTENV}" >&2
  exit 1
fi
TESTUSER=`echo ${TESTUSER} | sed "s/<%= user_id %>/${TESTUSERID}/"`

TESTPASS=`node -e "console.log(require('${TESTENV}').postgres_auth_pass || 'test')"`
# TODO: should postgres_auth_pass be optional ?
if test -z "$TESTPASS"; then
  echo "Missing postgres_auth_pass from ${TESTENV}" >&2
  exit 1
fi
TESTPASS=`echo ${TESTPASS} | sed "s/<%= user_id %>/${TESTUSERID}/"`

TEST_DB="${TESTUSER}_db"

# NOTE: will be set by caller trough environment
if test -z "$REDIS_PORT"; then REDIS_PORT=6335; fi

PUBLICUSER=`node -e "console.log(require('${TESTENV}').postgres.user || 'xxx')"`
PUBLICPASS=`node -e "console.log(require('${TESTENV}').postgres.password || 'xxx')"`
echo "PUBLICUSER: ${PUBLICUSER}"
echo "PUBLICPASS: ${PUBLICPASS}"
echo "TESTUSER: ${TESTUSER}"
echo "TESTPASS: ${TESTPASS}"

# Sets the env variable POSTGIS_VERSION as Major * 10000 + Minor * 100 + Patch
# For example, for 2.4.5 ~> 20405
# auto_postgis_version() {
#     local POSTGIS_STR=$(psql -c "Select default_version from pg_available_extensions WHERE name = 'postgis';" -t);
#     local pg_version=$(echo $POSTGIS_STR | awk -F '.' '{print $1 * 10000 + $2 * 100 + $3}')

#     echo $pg_version
# }

# if [ -z "$POSTGIS_VERSION" ]; then
#     export POSTGIS_VERSION=$(auto_postgis_version)
#     echo "POSTGIS_VERSION: ${POSTGIS_VERSION}"
# fi

if test x"$PREPARE_PGSQL" = xyes; then

  echo "preparing postgres..."
  dropdb "${TEST_DB}"
  createdb -T template_postgis -EUTF8 "${TEST_DB}" || die "Could not create test database"

  # Generated by:
  # ssh dbdp05.gusc.cartodb.net
  # mkdir -p /tmp/cartovl
  # for TABLE in mnmappluto monarch_migration_1 pop_density_points sf_stclines
  # do
  #   pg_dump --username postgres --dbname cartodb_user_de952f5f-6a86-467d-8c27-72cf6be3395e_db --table $TABLE --format plain --file /tmp/cartovl/$TABLE.sql
  # done
  # tar -cjf cartovl.tar.gz /tmp/cartovl
  psql -c "CREATE USER tileuser;" ${TEST_DB}
  psql -c "CREATE EXTENSION IF NOT EXISTS cartodb CASCADE;" ${TEST_DB}

  curl https://cartodb-libs.global.ssl.fastly.net/carto-vl/assets/mnmappluto.sql -o sql/mnmappluto.sql
  curl https://cartodb-libs.global.ssl.fastly.net/carto-vl/assets/monarch_migration_1.sql -o sql/monarch_migration_1.sql
  curl https://cartodb-libs.global.ssl.fastly.net/carto-vl/assets/pop_density_points.sql -o sql/pop_density_points.sql
  curl https://cartodb-libs.global.ssl.fastly.net/carto-vl/assets/sf_stclines.sql -o sql/sf_stclines.sql

  LOCAL_SQL_SCRIPTS='analysis_catalog windshaft.test cdb_analysis_check cdb_invalidate_varnish mnmappluto monarch_migration_1 pop_density_points sf_stclines'
  for i in ${LOCAL_SQL_SCRIPTS}
  do
    cat sql/${i}.sql |
      sed -e "s/:PUBLICUSER/${PUBLICUSER}/" |
      sed -e "s/:PUBLICPASS/${PUBLICPASS}/" |
      sed -e "s/:TESTUSER/${TESTUSER}/" |
      sed -e "s/:TESTPASS/${TESTPASS}/" |
      sed -e "s/cartodb_user_de952f5f-6a86-467d-8c27-72cf6be3395e/${TESTUSER}/" |
      sed -e "s/tileuser/${PUBLICUSER}/" |
      sed -e "s/TO publicuser/TO ${PUBLICUSER}/" |
      grep -v ".cdb_checkquota" |
      PGOPTIONS='--client-min-messages=WARNING' psql -q -v ON_ERROR_STOP=1 ${TEST_DB} > /dev/null || exit 1
  done
fi

if test x"$PREPARE_REDIS" = xyes; then

  echo "preparing redis..."

  cat <<EOF | redis-cli -p ${REDIS_PORT} -n 5
HMSET rails:users:localhost id ${TESTUSERID} \
                            database_name "${TEST_DB}" \
                            database_host localhost \
                            map_key 1234
SADD rails:users:localhost:map_key 1235
EOF

  # A user configured as with cartodb-2.5.0+
  cat <<EOF | redis-cli -p ${REDIS_PORT} -n 5
HMSET rails:users:cartodb250user id ${TESTUSERID} \
                                 database_name "${TEST_DB}" \
                                 database_host "localhost" \
                                 database_password "${TESTPASS}" \
                                 map_key 4321
EOF


  cat <<EOF | redis-cli -p ${REDIS_PORT} -n 0
HSET rails:${TEST_DB}:my_table infowindow "this, that, the other"
HSET rails:${TEST_DB}:test_table_private_1 privacy "0"
EOF

fi

# API keys ==============================

# User localhost -----------------------

# API Key Master
cat <<EOF | redis-cli -p ${REDIS_PORT} -n 5
  HMSET api_keys:localhost:1234 \
    user "localhost" \
    type "master" \
    grants_sql "true" \
    grants_maps "true" \
    database_role "${TESTUSER}" \
    database_password "${TESTPASS}"
EOF

# API Key Default public
cat <<EOF | redis-cli -p ${REDIS_PORT} -n 5
  HMSET api_keys:localhost:default_public \
    user "localhost" \
    type "default" \
    grants_sql "true" \
    grants_maps "true" \
    database_role "test_windshaft_publicuser" \
    database_password "public"
EOF

# API Key Regular
cat <<EOF | redis-cli -p ${REDIS_PORT} -n 5
  HMSET api_keys:localhost:regular1 \
    user "localhost" \
    type "regular" \
    grants_sql "true" \
    grants_maps "true" \
    database_role "test_windshaft_regular1" \
    database_password "regular1"
EOF

# API Key Regular 2 no Maps API access, only to check grants permissions to the API
cat <<EOF | redis-cli -p ${REDIS_PORT} -n 5
  HMSET api_keys:localhost:regular2 \
    user "localhost" \
    type "regular" \
    grants_sql "true" \
    grants_maps "false" \
    database_role "test_windshaft_publicuser" \
    database_password "public"
EOF

# User cartodb250user -----------------------

# API Key Master
cat <<EOF | redis-cli -p ${REDIS_PORT} -n 5
  HMSET api_keys:cartodb250user:4321 \
    user "localhost" \
    type "master" \
    grants_sql "true" \
    grants_maps "true" \
    database_role "${TESTUSER}" \
    database_password "${TESTPASS}"
EOF

# API Key Default
cat <<EOF | redis-cli -p ${REDIS_PORT} -n 5
  HMSET api_keys:cartodb250user:default_public \
    user "localhost" \
    type "default" \
    grants_sql "true" \
    grants_maps "true" \
    database_role "test_windshaft_publicuser" \
    database_password "public"
EOF


echo "Finished preparing data. Ready to run tests"
