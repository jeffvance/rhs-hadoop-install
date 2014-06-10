## IN is a string with uname,fname,lname.

IN="$1" 
set -- "$IN" 
IFS=","; declare -a Array=($*) 
uname="${Array[0]}"      
fname="${Array[1]}" 
lname="${Array[2]}"

echo "ipa user-add --displayname=$uname --firstname=$fname --lastname=$lname"
