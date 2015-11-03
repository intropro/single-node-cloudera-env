#! /usr/bin/env bash

SCRIPTNAME=$(readlink -f $0)
SCRIPTPATH=$(dirname $SCRIPTNAME)
DOCKERTEMPLATE=$SCRIPTPATH/templates/dockerfile.tmpl
PROFILE=$1
DOCKERFILE=$SCRIPTPATH/Dockerfile

usage_message () {
    printf "
Usage: $0 <path to profile file>
generate Dockerfile with profile content

"

    exit 1
}

if [[ -z "$1" ]]; then
    usage_message
fi

[[ -e $DOCKERFILE ]] && cp $DOCKERFILE $DOCKERFILE.bc

sed -e "/# Environment/r$PROFILE"  $DOCKERTEMPLATE > $DOCKERFILE && echo "Dockerfile was generated. Now you can build docker image."
