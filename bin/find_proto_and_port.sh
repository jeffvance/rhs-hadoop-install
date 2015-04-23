#!/bin/bash
#
# find_proto_and_port.sh outputs the protocol (http or https) and port number
# used by the current ambari cluster running on localhost (this node). Output
# format is "http|https port#" so that it can also be used as an array.

ambari_conf='/etc/ambari-server/conf/ambari.properties'
ssl_prop='api.ssl'		    # 'true' then using https
nonssl_port_prop='client.api.port'  # can be missing
ssl_port_prop='client.api.ssl.port' # can be missing
DEF_NONSSL_PORT=8080
DEF_SSL_PORT=8443

[[ ! -f "$ambari_conf" ]] && {
  echo "Ambari config file $ambari_conf missing";
  exit 1; }

# protocol
proto='http'
# see if we're using ssl or not
prop_val="$(grep ${ssl_prop}= $ambari_conf)"
[[ "${prop_val#*=}" == true ]] && proto='https' # use ssl

# port number
port_prop="$nonssl_port_prop" # default for http
port=$DEF_NONSSL_PORT	      # default for http
[[ "$proto" == 'https' ]] && {
  port_prop="$ssl_port_prop";
  port=$DEF_SSL_PORT;
}

# see if 1 of the port props exists in ambari conf, else use default port
prop_val="$(grep ${port_prop}= $ambari_conf)"
(( $? == 0 )) && [[ -n "$prop_val" ]] && port=${prop_val#*=}

echo "$proto $port"
exit 0
