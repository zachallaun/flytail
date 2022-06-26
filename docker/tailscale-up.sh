#!/bin/bash

set -euo pipefail

mkdir -p /var/lock/tailscale/

# From: https://gist.github.com/przemoc/571091
# SPDX-License-Identifier: MIT

## Copyright (C) 2009 Przemyslaw Pawelczyk <przemoc@gmail.com>
##
## This script is licensed under the terms of the MIT license.
## https://opensource.org/licenses/MIT
#
# Lockable script boilerplate

### HEADER ###

LOCKFILE="/var/lock/tailscale/up.lock"
LOCKFD=99

# PRIVATE
_lock()             { flock -$1 $LOCKFD; }
_no_more_locking()  { _lock u; _lock xn && rm -f $LOCKFILE; }
_prepare_locking()  { eval "exec $LOCKFD>\"$LOCKFILE\""; trap _no_more_locking EXIT; }

# ON START
_prepare_locking

# PUBLIC
exlock_now()        { _lock xn; }  # obtain an exclusive lock immediately or fail
exlock()            { _lock x; }   # obtain an exclusive lock
shlock()            { _lock s; }   # obtain a shared lock
unlock()            { _lock u; }   # drop a lock

### BEGIN OF SCRIPT ###

# Remember! Lock file is removed when one of the scripts exits and it is
#           the only script holding the lock or lock is not acquired at all.

exlock
rm -f /var/lock/tailscale/up.ran
unlock

echo "Waiting for /var/run/tailscale/tailscaled.sock..."
until [ -S /var/run/tailscale/tailscaled.sock ]; do
  sleep 0.1
done
echo "Done waiting!"

tailscale up \
  "--authkey=${TAILSCALE_AUTHKEY}" \
  "--hostname=CHANGEME-${FLY_REGION}" \
  --accept-routes=true \
  --ssh

exlock
touch /var/lock/tailscale/up.ran
unlock
