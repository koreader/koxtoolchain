#!/bin/bash

chown -R kox:kox /home/kox/build
exec runuser -u kox "$@"