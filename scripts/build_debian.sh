#!/bin/sh
cd .. && grep -s -q APP-MTAWS-ROOT-DIR Build.PL || exit 1 # protect from wrong dir
[ `which perl` = "/usr/bin/perl" ] || exit 1
perl Build.PL && ./Build build

DISTROS="squeeze wheezy jessie"
for DISTRO in $DISTROS
do
rm -rf debian
mkdir -p debian/source
scripts/write_debian_files.pl ./packaging debian $DISTRO || exit 1
debuild -b
rm -rf debian
done
