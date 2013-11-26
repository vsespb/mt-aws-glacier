#!/bin/sh
set -e
COVER_DB=/tmp/cover_db
cover -delete $COVER_DB

if [ -z "$1" ]
then
MT_COVER=-MDevel::Cover=-db,$COVER_DB ../test.t cover
else
perl -MDevel::Cover=-db,$COVER_DB $(find ../t/ |grep -E "\.t$" |grep $1 )
fi

cover $COVER_DB -report=html -launch
echo OK DONE
