#! /usr/bin/env bash

sfactors=(1 10 30 100);
for sfactor in "${sfactors[@]}"; do
    ./benchmark.sh -s "${sfactor}" -f -h pgpool1 -p 9999
done;
