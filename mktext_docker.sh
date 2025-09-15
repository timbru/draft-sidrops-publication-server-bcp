#!/bin/bash

DRAFT="draft-ietf-sidrops-publication-server-bcp-04"

docker run --rm \
    -v $(pwd):/rfc \
    -v $HOME/.cache/xml2rfc:/var/cache/xml2rfc \
    -w /rfc \
    paulej/rfctools \
    mmark $DRAFT.md > $DRAFT.xml


docker run --rm \
    -v $(pwd):/rfc \
    -v $HOME/.cache/xml2rfc:/var/cache/xml2rfc \
    -w /rfc \
    paulej/rfctools \
    xml2rfc --text --html --pdf $DRAFT.xml
