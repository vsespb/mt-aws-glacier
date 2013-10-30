#!/bin/sh
set -e
COVER_DB=/tmp/cover_db
cover -delete $COVER_DB
MT_COVER=-MDevel::Cover=-db,$COVER_DB ../test.t cover
cover $COVER_DB -report=html -launch
echo OK DONE
