#!/bin/sh
cd .. && grep -s -q APP-MTAWS-ROOT-DIR Build.PL || exit 1 # protect from wrong dir
[ `which perl` = "/usr/bin/perl" ] || exit 1
perl Build.PL && ./Build build
DISTROS="precise trusty utopic"
for DISTRO in $DISTROS
do
rm -rf debian
mkdir -p debian/source
scripts/write_debian_files.pl ./packaging ubuntu $DISTRO || exit 1
debuild -S
rm -rf debian
done

