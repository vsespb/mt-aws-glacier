#!/bin/sh
#./gemu-test.pl --filter 'subcommand=sync_modified'|taskset -c 2,3 ./gemu-test-worker.pl -n 5

#./gemu-test.pl --filter 'subcommand=sync_missing'|USENEWFSM=1 taskset -c 2,3 ./gemu-test-worker.pl -n 1 --verbose
./gemu-test.pl --filter 'command=sync'|USENEWFSM=0 ./gemu-test-worker.pl -n 4  --state MyState

#./gemu-test.pl --filter 'subcommand=sync_modified otherfiles_count=1'
#./gemu-test.pl --filter 'subcommand=sync_new filesize=47029023'|taskset -c 2,3 ./gemu-test-worker.pl -n 5
