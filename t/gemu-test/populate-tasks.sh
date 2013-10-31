#!/bin/sh
set -e
./gemu-test.pl | sort > gemu-test-tasks.txt
cd /home/prj/mt/misc/gemu-tasks
git diff gemu-test-tasks.txt > d
