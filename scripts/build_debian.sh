#!/bin/sh
cd .. && grep -s -q APP-MTAWS-ROOT-DIR Build.PL || exit 1 # protect from wrong dir

rm -rf debian
mkdir -p debian/source
scripts/write_debian_files.pl ./packaging debian wheezy
debuild 
rm -rf debian

