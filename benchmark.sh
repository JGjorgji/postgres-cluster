#! /bin/bash

set -o pipefail
set -o nounset
set -o errexit

SCALE_FACTOR=1
FORCE=false
QUERY_MODE="sequential"
CACHE_MODE="both"
HOST=""
USER="postgres"

if [ -z ${DBGEN_LOCATION} ]; then
    echo "Need to specify DBGEN_LOCATION env variable"
    exit 1
fi

while getopts "s:fq:c:h:" opt; do
    case ${opt} in
        s)
            SCALE_FACTOR=${OPTARG}
            ;;
        f)
            FORCE=true
            ;;
        q)
            QUERY_MODE=${OPTARG}
            ;;
        c)
            CACHE_MODE=${OPTARG}
            ;;
        h)
            HOST=${OPTARG}
            ;;
        *)
            echo "Unknown command line option"
            exit 1
            ;;
    esac
done

PSQL="$(which psql) -U ${USER} -h ${HOST}"

generate_data () {
    pushd ${DBGEN_LOCATION}
    DBGEN_ARGS="-s ${SCALE_FACTOR} -T a"
    if [ ${FORCE} ]; then
        DBGEN_ARGS="${DBGEN_ARGS} -f"
    fi
    ./dbgen ${DBGEN_ARGS}

    # Now we need to remove the last delimiter so postgres can import the data
    for file in *.tbl; do
        sed -i 's/|$//' ${file} &
    done
    wait
    popd
    # Data should now be nicely formatted for import
}

create_schema_and_tables () {
    #${PSQL} -c "DROP SCHEMA ssb IF EXISTS CASCADE;"
    ${PSQL} -c "CREATE SCHEMA IF NOT EXISTS ssb;"
    ${PSQL} < ${SCHEMA_FILE}
}

load_data () {
    pushd ${DBGEN_LOCATION}
    for file in *.tbl; do
        TABLENAME=$(echo ${file} | sed 's/\.tbl$//')
        ${PSQL} -c "COPY ssb.${TABLENAME} FROM stdin WITH DELIMITER '|';" < ${file}
    done
    popd
}

vaccum_db () {
    ${PSQL} -c "VACUUM FULL;"
}

run_query () {
    QUERY_LOCATION=${1}
    time ${PSQL} < ${QUERY_LOCATION}
}

run_all () {
    for query in queries/*; do
        run_query ${query}
    done
}

main () {
    generate_data
    
    # Force needs to always be specified when changing scale factor between runs!!!
    if [ ${FORCE} ]; then
        ${PSQL} -c "DROP SCHEMA ssb IF EXISTS CASCADE;"
    fi

    create_schema_and_tables

    load_data

    run_all

    echo "Finished at $(date)"
    exit 0
}

