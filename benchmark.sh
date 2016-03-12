#! /usr/bin/env bash

set -o pipefail
set -o nounset
set -o errexit

SCALE_FACTOR=1
FORCE=false
QUERY_MODE="sequential"
CACHE_MODE="both"
HOST=
USER="postgres"
RESULTDIR=

if [[ -z ${DBGEN_LOCATION} ]]; then
    echo "Need to specify DBGEN_LOCATION env variable"
    exit 1
fi

while getopts "s:q:c:h:f" opt; do
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
    # If -f is provided we regenerate all the data
    # since we don't know what the previous scale factor was
    if [[ ${FORCE} == true ]]; then
        rm -f *.tbl
        ./dbgen -s "${SCALE_FACTOR}" -T a -f
    fi
    popd
}

create_schema_and_tables () {
    ${PSQL} -c "CREATE SCHEMA ssb;"
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
    { time ${PSQL} < ${QUERY_LOCATION} ;} > "${RESULTDIR}/${QUERY_LOCATION}"
}

run_all () {
    for query in queries/*; do
        run_query ${query}
    done
}

main () {
    generate_data
    
    # Force needs to always be specified when changing scale factor between runs!!!
    if [[ ${FORCE} == true ]]; then
        ${PSQL} -c "DROP SCHEMA IF EXISTS ssb CASCADE;"
        create_schema_and_tables
        load_data
    fi
    if [[ ! -d "${RESULTDIR}" ]]; then
        mkdir -p "${RESULTDIR}"
    fi
    
    RESULTDIR="${RESULTDIR}/$(date +'%d-%m-%Y-%H-%M')"
    mkdir ${RESULTDIR}

    echo date > "${RESULTDIR}/started"

    run_all

    echo date > "${RESULTDIR}/finished"
    exit 0
}

main
