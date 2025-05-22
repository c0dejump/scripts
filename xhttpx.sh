#!/bin/bash

usage() {
    echo "Usage: $0 -f fichier_urls.txt -o fichier_sortie [-e codes_a_exclure] [-s]"
    echo
    echo "Options :"
    echo "  -f    Input file containing URLs (or domains if -s is used)"
    echo "  -o    Output file for valid URLs"
    echo "  -e    HTTP codes to exclude (e.g. 400 404 500) [default: 400 404 405 500 501 502]"
    echo "  -s    Use subfinder on input file to discover subdomains"
    exit 1
}

use_subfinder=false

while getopts ":f:o:e:s" opt; do
  case ${opt} in
    f )
      input_file=$OPTARG
      ;;
    o )
      output_file=$OPTARG
      ;;
    e )
      BAD_CODES=$OPTARG
      ;;
    s )
      use_subfinder=true
      ;;
    \? )
      usage
      ;;
  esac
done

if [ -z "$input_file" ] || [ -z "$output_file" ]; then
    usage
fi

if [ -z "$BAD_CODES" ]; then
    BAD_CODES="400 404 405 500 501 502"
fi

if [ "$use_subfinder" = true ]; then
    echo "[*] Subfinder Execution on $input_file..."
    subfinder -dL "$input_file" -o subdoms.txt
    if [ $? -ne 0 ]; then
        echo "Error with subfinder."
        exit 1
    fi
    input_file="subdoms.txt"
fi

> "$output_file"

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36"
ACCEPT_ENCODING="gzip"

total_urls=$(wc -l < "$input_file")
if [ "$total_urls" -eq 0 ]; then
    echo "The file is empty"
    exit 1
fi

temp_file=$(mktemp)
echo 0 > "$temp_file"

export total_urls
export temp_file
export BAD_CODES
export USER_AGENT
export ACCEPT_ENCODING
export output_file

show_progress() {
    current_url=$(cat "$temp_file")  
    percent=$((100 * current_url / total_urls))
    
    bar_width=50
    filled=$((bar_width * percent / 100))
    
    bar=""
    for i in $(seq 1 $filled); do bar="${bar}#"; done
    for i in $(seq $filled $((bar_width - 1))); do bar="${bar} "; done
    
    echo -ne "[$bar] $percent% ($current_url/$total_urls)\r"
}

check_url() {
    url="$1"
    response_code=$(curl -L -k -s -o /dev/null -w "%{http_code}" --max-time 15 \
        -A "$USER_AGENT" -H "Accept-Encoding: $ACCEPT_ENCODING" "$url")

    if [ "$response_code" == "000" ]; then return; fi

    if [[ ! $BAD_CODES =~ $response_code ]]; then
        if [[ ! "$url" =~ \/(index\.php|index\.html|api\/|[^/]+$) ]]; then
            url="$url/"
        fi
        echo "$url" >> "$output_file"
    fi
}

export -f check_url
export -f show_progress

cat "$input_file" | sed 's|^https\?://||' | xargs -P 50 -I {} bash -c '
    current_url=$(cat "$temp_file")  
    current_url=$((current_url + 1))  
    echo $current_url > "$temp_file"  
    check_url "https://{}" && check_url "http://{}"
    show_progress
'

echo -e "\nScan finish. Results in $output_file."
