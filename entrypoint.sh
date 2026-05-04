#!/bin/sh
set -xve

# Test using the following form:
# export SANED_NET_HOSTS="a|b" AIRSCAN_DEVICES="c|d" DELIMITER="|"; ./entrypoint.sh

# turn off globbing
set -f

# split at newlines only (airscan devices can have spaces in)
IFS='
'

# Get a custom delimiter but default to ;
DELIMITER=${DELIMITER:-;}

# Insert a list of net hosts
if [ ! -z "$SANED_NET_HOSTS" ]; then
  hosts=$(echo $SANED_NET_HOSTS | sed "s/$DELIMITER/\n/")
  for host in $hosts; do
    echo $host >> /etc/sane.d/net.conf
  done
fi

# Insert airscan devices
if [ ! -z "$AIRSCAN_DEVICES" ]; then
  devices=$(echo $AIRSCAN_DEVICES | sed "s/$DELIMITER/\n/")
  for device in $devices; do
    sed -i "/^\[devices\]/a $device" /etc/sane.d/airscan.conf
  done
fi

# Insert pixma hosts
if [ ! -z "$PIXMA_HOSTS" ]; then
  hosts=$(echo $PIXMA_HOSTS | sed "s/$DELIMITER/\n/")
  for host in $hosts; do
    echo "bjnp://$host" >> /etc/sane.d/pixma.conf
  done
fi

unset IFS
set +f

# Drop privileges if PUID is set to a non-root value
PUID=${PUID:-0}
PGID=${PGID:-0}

if [ "$PUID" != "0" ]; then
  groupadd -g "$PGID" -o scanservjs 2>/dev/null || groupmod -g "$PGID" -o scanservjs
  useradd -o -u "$PUID" -g "$PGID" -s /bin/bash scanservjs 2>/dev/null || usermod -u "$PUID" -g "$PGID" scanservjs
  chown -R "$PUID:$PGID" /var/lib/scanservjs /etc/sane.d/net.conf /etc/sane.d/airscan.conf
  exec gosu scanservjs node ./server/server.js
fi

exec node ./server/server.js
