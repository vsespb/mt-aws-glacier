#!/bin/sh
#./gemu-test.pl |USENEWFSM=0 ./gemu-test-worker.pl -n 4  --state release_oldfsm.state --glacierbin prod
#./gemu-test.pl |USENEWFSM=1 ./gemu-test-worker.pl -n 4  --state release_newfs_mixed.state --glacierbin dev
#./gemu-test.pl |NEWFSM=1 ./gemu-test-worker.pl -n 4  --state release_newfs_full.state --glacierbin dev
./gemu-test.pl |NEWFSM=0 ./gemu-test-worker.pl -n 4  --state release_drop_old_fsm.state --glacierbin dev
