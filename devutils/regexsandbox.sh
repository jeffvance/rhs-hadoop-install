#VALID_HOSTNAME_RE='^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]        *[A-Za-z0-9])$'

VALID_HOSTNAME_RE='^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$'

declare -a arr=(my_host myhost)

#Works   
#local VALID_HOSTNAME_RE='.*'

# read hosts file, skip comments and blank lines, parse out hostname and ip
#read -a hosts_ary <<< $(sed '/^ *#/d;/^ *$/d;s/#.*//' $HOSTS_FILE)
for i in ${arr[@]}
do
  host=$i
  if [[ ! $host =~ $VALID_HOSTNAME_RE ]] ; then
     echo "bad hostname :( $host "
  else


   echo "good hostname :)  $host  "
  fi
done
