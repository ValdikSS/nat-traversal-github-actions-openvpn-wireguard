#!/bin/bash
if [[ ! "$1" ]] || ! ([[ "$1" == "wireguard" ]] || [[ "$1" == "openvpn" ]]); then
  echo "$0 <openvpn / wireguard>"
  exit 1
fi

# Check for stun client by hanpfei
STUN=""
[[ "$(command -v stun-client)" ]] && STUN="stun-client"
[[ "$(command -v stun)" ]] && STUN="stun"
if [[ ! "$STUN" ]]; then
  echo "stun client not found, please install 'stun' or 'stun-client' package!"
  exit 2
fi

# Check for any netcat implementation
if [[ ! "$(command -v nc)" ]]; then
  echo "Some NAT types require netcat, but it is not found. Please install 'netcat', 'netcat-openbsd', 'ncat' or 'nc' package!"
  exit 3
fi

# Check for git
if [[ ! "$(command -v git)" ]]; then
  echo "git not found, please install 'git' package!"
  exit 4
fi


# Choose random local source port from 20000-30000 range.
# Linux/Android default local port range is 32768-60999,
# Windows and macOS is 49152-65535.
# Do not use ports from this range to prevent possible
# mapping collision with some rare source-dependent-port-preserving
# NATs.
PORT=$(( 20000 + $RANDOM % 10000 ))

# Run stun client with source port PORT and save its output,
# stun.ekiga.net server with two external IP addresses,
# which is important for receiving proper NAT type information.
STUN_OUTPUT="$("$STUN" stun.ekiga.net -v -p $PORT 2>&1)"

# Extract external IP address and mapped port from stun output.
IPPORT=$(echo "$STUN_OUTPUT" | awk '/MappedAddress/ {print $3; exit}')

echo -n "Your NAT type is: "
echo "$STUN_OUTPUT" | awk '/Primary:/ {print substr($0, index($0, $2)); exit}'
echo

# Random port, host/port dependent mapping NAT would not work unfortunately, as we
# won't be able to determine NAT port mapping for GitHub Actions worker IP address.
if [[ ! $(echo "$STUN_OUTPUT" | grep 'Independent Mapping') ]]; then
  echo "Unfortunately, your NAT type uses random mappings for different destination host/port, which is not compatible"
  echo "with this example. The script will now exit."
  exit 4
fi

if [[ "$1" == "openvpn" ]]; then
  git commit -m "OVPN: $IPPORT:$PORT" --allow-empty && git push
elif [[ "$1" == "wireguard" ]]; then
  git commit -m "WG: $IPPORT:$PORT" --allow-empty && git push
fi

echo
echo ">>> Now check GitHub Actions job 'OpenVPN connection string' or 'WireGuard configuration file' for connection information <<<"

# If out NAT does not map local source port to the same external source port,
# keep mapping active in the background by sending empty UDP packets from our
# local source port with 10s interval.
# The 3.3.3.3 IP address here is in non-routed IP address space, the packets
# would punch NAT but won't be delivered anywhere.
# The port 443 here was chosen without any strong reason. It does not matter
# for "Independent Mapping" NAT. We may have used ports 1024 or 1984 here
# (two most common external port mappings in Actions for the first outgoing
# request), just in case if there's someone who implemented
# "port, but not address-dependent mapping" NAT. But for now, let it be just
# 443.
#
# Short interval of 10 seconds is used to prevent the case when the client
# press CTRL+C very close to NAT mapping expiration timeout, but not starting
# OpenVPN/WireGuard connection in time.
# Common "non-established" UDP NAT mapping timeout is 30 seconds.
if [[ ! $(echo "$STUN_OUTPUT" | grep 'preserves ports') ]]; then

  echo "> Punching NAT in the background, press CTRL+C just before connecting to the VPN!"
  while [ 1 ]; do
    echo | nc -n -u -p $PORT 3.3.3.3 443
    sleep 10
  done
fi
