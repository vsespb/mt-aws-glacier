#!/bin/sh
set -e
FULLPATH=/home/prj/mt/misc/gemu-tasks/gemu-test-tasks.txt
./gemu-test.pl | sort > $FULLPATH
cd /home/prj/mt/misc/gemu-tasks
git diff gemu-test-tasks.txt > d
