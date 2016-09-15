#! /usr/bin/env bash

set -o pipefail
set -o nounset
set -o errexit

SCALE_FACTOR=1
FORCE=false
HOST=
USER="postgres"
PORT=
CONCURRENCY=1

if [[ -z ${DBGEN_LOCATION} ]]; then
    echo "Need to specify DBGEN_LOCATION env variable"
    exit 1
fi

while getopts "s:c:h:fp:" opt; do
    case ${opt} in
        s)
            SCALE_FACTOR=${OPTARG}
            ;;
        f)
            FORCE=true
            ;;
        c)
            CONCURRENCY=${OPTARG}
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

vaccum_db () {
    ${PSQL} -c "VACUUM FULL;"
}

generate_data () {
    pushd ${DBGEN_LOCATION}
    # If -f is provided we regenerate all the data
    # since we don't know what the previous scale factor was
    rm -f *.tbl
    ./dbgen -s "${SCALE_FACTOR}" -T a -f
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
        while [[ wc -l "${file}" >= 7000000 ]]; do
            ${PSQL} -c "COPY ssb.${TABLENAME} FROM stdin WITH DELIMITER '|';" < head -n 7000000 ${file}
            vaccum_db &
            sed -ei '1,7000000d' "${file}" &
            wait
        done
    done
    popd
}

run_query () {
    QUERY_LOCATION=${1}

    for i in $(seq 1 "${CONCURRENCY}"); do
        fname="${RESULTDIR}/$(basename ${QUERY_LOCATION})-${i}"
        { time ${PSQL} < ${QUERY_LOCATION} ;} >  "${fname}" 2> "${fname}.time" &
    done
    wait
}

run_all () {
    for query in queries/*; do
        run_query ${query}
    done
}

main () {
    
    # Force needs to always be specified when changing scale factor between runs!!!
    if [[ ${FORCE} == true ]]; then
        generate_data
        ${PSQL} -c "DROP SCHEMA IF EXISTS ssb CASCADE;"
        create_schema_and_tables
        load_data
    fi
    
    # Always have the basedir present
    if [[ ! -d "${RESULTDIR}" ]]; then
        mkdir -p "${RESULTDIR}"
    fi
        
    RESULTDIR="${RESULTDIR}/${HOST}-${SCALE_FACTOR}-${CONCURRENCY}"
    
    # Wipe per scale factor results on rerun
    rm -rf "${RESULTDIR}"
    mkdir -p "${RESULTDIR}"

    echo $(date) > "${RESULTDIR}/started"
    
    # Start collectl on all nodes
    ansible all -m shell -a "nohup collectl --all > /root/{{ inventory_hostname }}.collectl &" -u root

    run_all
    
    # Stop collectl
    ansible all -m shell -a "pkill collectl" -u root
    
    # Get the results to the control node
    ansible all -m fetch -a "src=/root/{{ inventory_hostname }}.collectl dest=${RESULTDIR} flat=yes" -u root

    echo $(date) > "${RESULTDIR}/finished"
    exit 0
}

main
