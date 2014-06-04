#!/bin/bash
set -e

export PATH=$HOME/local/perl-5.18/bin:$PATH
CDIR=$(cd $(dirname $0) && pwd)
cd $CDIR
carton install
carton exec -- ./fetch.pl



