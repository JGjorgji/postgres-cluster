#! /usr/bin/env bash

sfactors=(1 10 30 100 300);
concurrency=(1 10 20 30 40 50 60 70 80 100)
for sfactor in "${sfactors[@]}"; do
    firstrun=true
    for cfactor in "${concurrency[@]}"; do
        if [[ "$firstun" == true ]]; then
            ./benchmark.sh -s "${sfactor}" -c "${cfactor}" -f -h pgpool1 -p 9999
            firstrun=false
        else
            ./benchmark.sh -s "${sfactor}" -c "${cfactor}" -h pgpool1 -p 9999
        fi
    done
done;
