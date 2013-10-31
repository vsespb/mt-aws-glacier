#/bin/sh
TAG=v1.056
#git tag -d $TAG && git push origin :refs/tags/$TAG
git tag -u D0FF5699 $TAG -m "$TAG"  && git push --tags
