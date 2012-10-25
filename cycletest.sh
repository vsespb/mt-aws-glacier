#!/bin/sh

# mt-aws-glacier - AWS Glacier sync client
# Copyright (C) 2012  Victor Efimov
# vs@vs-dev.com http://vs-dev.com
# License: GPLv3
#
# This file is part of "mt-aws-glacier"
#
#    mt-aws-glacier is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    mt-aws-glacier is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

if test -z "$2"; then exit; fi
DIR=./$2
test -x $DIR || exit 0

ROOT=$DIR/files
VAULT=test1
JOURNAL=$DIR/journal

case $1 in

init)
# warning, make sure DIR is correct, avoid disaster!
rm -rf $DIR/*
mkdir $ROOT
dd if=/dev/urandom of=$ROOT/file4 bs=100 count=1
dd if=/dev/urandom of=$ROOT/file5 bs=100 count=3
dd if=/dev/urandom of=$ROOT/file6 bs=100 count=30

./mtglacier.pl sync --config=glacier.cfg --from-dir $ROOT --to-vault=$VAULT -journal=$JOURNAL
./mtglacier.pl check-local-hash --config=glacier.cfg --from-dir $ROOT --to-vault=$VAULT -journal=$JOURNAL
md5sum $ROOT/* > $DIR/original-md5

	;;
sync)
./mtglacier.pl sync --config=glacier.cfg --from-dir $ROOT --to-vault=$VAULT -journal=$JOURNAL

	;;
	
check)
./mtglacier.pl check-local-hash --config=glacier.cfg --from-dir $ROOT --to-vault=$VAULT -journal=$JOURNAL

	;;
	
retrieve)
# warning, make sure DIR is correct, avoid disaster!
rm -rf $ROOT/*
./mtglacier.pl check-local-hash --config=glacier.cfg --from-dir $ROOT --to-vault=$VAULT -journal=$JOURNAL
./mtglacier.pl restore -config=glacier.cfg --from-dir $ROOT --to-vault=$VAULT -journal=$JOURNAL --max-number-of-files=10
	;;

purge)
# warning, make sure DIR is correct, avoid disaster!
./mtglacier.pl purge-vault -config=glacier.cfg --from-dir $ROOT --to-vault=$VAULT -journal=$JOURNAL
	;;

restore)
./mtglacier.pl restore-completed -config=glacier.cfg --from-dir $ROOT --to-vault=$VAULT -journal=$JOURNAL
	;;
esac
