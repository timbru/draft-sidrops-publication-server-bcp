#!/bin/bash
docker run --rm \
    -v $(pwd):/rfc \
    -v $HOME/.cache/xml2rfc:/var/cache/xml2rfc \
    -w /rfc \
    paulej/rfctools \
    mmark draft-timbru-sidrops-publication-server-bcp-01.md > draft-timbru-sidrops-publication-server-bcp-01.xml


docker run --rm \
    -v $(pwd):/rfc \
    -v $HOME/.cache/xml2rfc:/var/cache/xml2rfc \
    -w /rfc \
    paulej/rfctools \
    xml2rfc --text --html draft-timbru-sidrops-publication-server-bcp-01.xml
