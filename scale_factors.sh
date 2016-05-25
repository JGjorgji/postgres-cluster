factors=(1 10 30 100);
for sfactor in "${sfactors[@]}"; do
        DBGEN_LOCATION=/root/ssb-dbgen SCHEMA_FILE=schema/dss-ssb.ddl RESULTDIR=/root/results ./benchmark.sh -s "${sfactor}" -f -h pgpool1
done;
