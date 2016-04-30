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
PORT=

if [[ -z ${DBGEN_LOCATION} ]]; then
    echo "Need to specify DBGEN_LOCATION env variable"
    exit 1
fi

while getopts "s:q:c:h:fp:" opt; do
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
        p)
            PORT=${OPTARG}
            ;;
        *)
            echo "Unknown command line option"
            exit 1
            ;;
    esac
done

PSQL="$(which psql) -U ${USER} -h ${HOST} -p ${PORT}"

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
    { time ${PSQL} < ${QUERY_LOCATION} ;} > "${RESULTDIR}/$(basename ${QUERY_LOCATION})" 2> "${RESULTDIR}/$(basename ${QUERY_LOCATION}).time"
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
    
    RESULTDIR="${RESULTDIR}/${HOST}-${SCALE_FACTOR}"
    mkdir ${RESULTDIR}

    echo $(date) > "${RESULTDIR}/started"
    
    # Start collectl on all nodes
    while $IFS= read -r node
    do
        ssh root@"${node}" "collectl --all > collectl.output &"
    done < "/root/hosts"

    run_all
    
    # Stop collectl
    while $IFS= read -r node
    do
        ssh root@"${node}" "pkill collectl"
    done < "/root/hosts"   
    
    # Get the results to the control node
    while $IFS= read -r node
    do
        scp root@"${node}:/root/collectl.output" "${RESULTDIR}/${node}.collectl.output"
    done < "/root/hosts"


    echo $(date) > "${RESULTDIR}/finished"
    exit 0
}

main
