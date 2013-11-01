#!/bin/sh
set -e
COVER_DB=/tmp/cover_db
cover -delete $COVER_DB
#MT_COVER=-MDevel::Cover=-db,$COVER_DB ../test.t cover
perl -MDevel::Cover=-db,$COVER_DB ../t/unit/queue_job/fetch_and_download_inventory.t
cover $COVER_DB -report=html -launch
echo OK DONE
