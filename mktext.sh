#!/bin/bash

DRAFT="draft-timbru-sidrops-publication-server-bcp-01"

mmark $DRAFT.md  > $DRAFT.xml && xml2rfc --text --html $DRAFT.xml
