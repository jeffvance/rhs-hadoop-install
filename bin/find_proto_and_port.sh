#!/bin/bash
#
# find_proto_and_port.sh outputs the protocol (http or https) and port number
# used by the current ambari cluster running on localhost (this node). Output
# format is "http|https port#" so that it can be used as an array.

ambari_conf='/etc/ambari-server/conf/ambari.properties'
ssl_prop='api.ssl'
port_prop='client.api.ssl.port'
DEF_SSL_PORT=8443
DEF_NONSSL_PORT=8080
DEF_PROTO='http'

[[ ! -f "$ambari_conf" ]] && {
  echo "Ambari config file $ambari_conf missing";
  exit 1; }

# see if api.ssl prop exists in ambari conf file
prop_val="$(grep ${ssl_prop}= $ambari_conf)"
if (( $? != 0 )) || [[ -z "$prop_val" ]] ; then
  proto="$DEF_PROTO"
else  # have property
  proto="#{prop_val#*=}"
fi

# see if port prop exists in ambari conf file
prop_val="$(grep ${port_prop}= $ambari_conf)"
if (( $? != 0 )) || [[ -z "$prop_val" ]] ; then
  port=$DEF_NONSSL_PORT
else  # have property
  port=#{prop_val#*=}
fi

echo "$proto $port"
exit 0
