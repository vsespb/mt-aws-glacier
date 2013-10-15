#!/bin/sh

DISTROS="lucid precise quantal raring saucy"
for DISTRO in $DISTROS
do
rm -rf debian
mkdir -p debian/source
scripts/write_debian_files.pl packaging $DISTRO
debuild -S
rm -rf debian
done

