#!/bin/bash

MANDATORY_VARS=(
  MPH_PRIMARY
  MPH_SECONDARY
)

if [ "$MPH_VERBOSE" -ge 2 ]
then
  # very verbose !
  # WARNING password is dumped !
  [ "$MPH_VERBOSE" -ge 3 ] && set -x
  OUT=/dev/stdout
  DP_OPT="-V"
else
  OUT=/dev/null
  DP_OPT="-q"
fi

log() {
  DATE=$( date -I'seconds' )
  echo "$DATE $*"
}

err() {
  log "ERR" $* >&2
}

info() {
  [ "$MPH_VERBOSE" -ge 1 ] && log "INF" $*
}

dbg() {
  [ "$MPH_VERBOSE" -ge 2 ] && log "DBG" $*
}


# $1 dhcp url : http[s]://ip[:port]
# $2 password
# [$3] true/false
set_dhcp() {
  URL=$1
  PWD=$2
  VALUE=${3:-true}

  # auth
  SID=$( curl -sS -X POST "${URL}/api/auth" \
    -H 'accept: application/json'\
    -H 'content-type: application/json' \
    -d "{\"password\":\"${PWD}\"}" )
  if [ $? -ne 0 ]
  then
    err "Cannot connect to ${URL}"
    return 1
  fi
  dbg "auth: $SID"
  SID=$( echo $SID | jq -r '.session.sid' )

  sleep 1

  # get current state
  ACTUAL=$( curl -sS -X GET "${URL}/api/config/dhcp%2Factive"  \
    -H 'accept: application/json' \
    -H "sid: ${SID}" )
  dbg "state: $ACTUAL"
  ACTUAL=$( echo $ACTUAL | jq -r '.config.dhcp.active' )

  if [ "$ACTUAL" != "$VALUE" ]
  then
    # set DHCP new state
    sleep 1
    info "Setting ${URL} from $ACTUAL to $VALUE ..."
    curl -sS -X PATCH "${URL}/api/config" \
      -H 'accept: application/json'\
      -H 'content-type: application/json'\
      -H "sid: ${SID}" \
      -d "{\"config\":{\"dhcp\":{\"active\": ${VALUE}}}}" &> $OUT
    sleep 5 # wait for FTL restart
  fi

  if [ "$MPH_VERBOSE" -ge 1 ]
  then
    sleep 1
    # get current state
    ACTUAL=$( curl -sS -X GET "${URL}/api/config/dhcp%2Factive"  \
      -H 'accept: application/json' \
      -H "sid: ${SID}" )
    dbg "newstate: $ACTUAL"
    ACTUAL=$( echo $ACTUAL | jq -r '.config.dhcp.active' )
    info "dhcp on ${URL} is ${ACTUAL}"
  fi

  # de-auth
  sleep 1
  curl -X DELETE "${URL}/api/auth" \
    -H 'accept: application/json'\
    -H "sid: ${SID}" &> $OUT
}

# explode URL|pass into global variables MPH_xxx_[URL|PASS|IP]
# $1 PRIMARY or SECONDARY
# $2 "URL|pass"
explodeURL() {
  N=$1; U=$2
  # get evrything after |
  passname=MPH_${N}_PASS; declare -g MPH_${N}_PASS=${U#*|}
  # get everything before |
  urlname=MPH_${N}_URL;   declare -g MPH_${N}_URL=${U%|*}
  ipname=MPH_${N}_IP;
  # remove everything up to last /
  declare -g MPH_${N}_IP=${U##*/}
  # remove evrything after :
  declare -g MPH_${N}_IP=${!ipname%:*}
  dbg "$N,$U --> '${!urlname}'${!ipname}'${!passname}'"
}


##### main #####

# check presence of mandatory parameters
for v in ${MANDATORY_VARS[*]}
do
  if [ -z "${!v}" ]
  then
    err "Missing mandatory variable $v"
    exit 1
  else
    dbg "$v: ${!v}"
  fi
done

explodeURL "PRIMARY" "$MPH_PRIMARY"
explodeURL "SECONDARY" "$MPH_SECONDARY"

# get default interface
IFACE=$(ip route show default | awk '/default/ {print $5}')
# get its mac address
read CURMAC </sys/class/net/${IFACE}/address
MAC=${MPH_SECONDARY_MAC:-$CURMAC}
dbg "MACs: $CURMAC, $MPH_SECONDARY_MAC"

while [ 1 ]
do

  # check dhcp on primary for secondary
  info "Checking ${MPH_PRIMARY_IP} for ${MAC}/${MPH_SECONDARY_IP}"
  dhcping ${DP_OPT} -i -t 5 -h ${MAC} -c ${MPH_SECONDARY_IP} -s ${MPH_PRIMARY_IP}
  if [ $? -eq 0 ]
  then
    info "dhcp ${MPH_PRIMARY_IP} is alive, deactivate ${MPH_SECONDARY_URL} if needed"
    set_dhcp ${MPH_SECONDARY_URL} ${MPH_SECONDARY_PASS} false
  else
    err "Failed to get dhcp ack, assume ${MPH_PRIMARY_IP} is dead"
    set_dhcp ${MPH_SECONDARY_URL} ${MPH_SECONDARY_PASS}
  fi

  sleep ${MPH_MONITOR_DELAY}

done
