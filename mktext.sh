#!/bin/bash

DRAFT="draft-timbru-sidrops-publication-server-bcp-00"

mmark $DRAFT.md  > $DRAFT.xml && xml2rfc --text --html $DRAFT.xml
