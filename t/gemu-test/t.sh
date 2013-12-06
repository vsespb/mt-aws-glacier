#!/bin/sh
./gemu-test.pl |USENEWFSM=0 ./gemu-test-worker.pl -n 4  --state release_oldfsm.state --glacierbin prod
