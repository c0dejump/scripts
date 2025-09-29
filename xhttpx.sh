#!/bin/bash

usage() {
    echo "Usage: $0 -f input_file.txt -o output_file [-e exclude_code] [-s] [-t size_threshold] [-b blacklist_file]"
    echo
    echo "Options :"
    echo "  -f    Input file containing URLs (or domains if -s is used)"
    echo "  -o    Output file for valid URLs"
    echo "  -e    HTTP codes to exclude (e.g. 400 404 500) [default: 400 403 404 405 500 501 502 503]"
    echo "  -s    Use multiple subdomain discovery tools on input file"
    echo "  -t    Size threshold in bytes to consider responses different [default: 150]"
    echo "  -b    Blacklist file containing domains/patterns to exclude (one per line)"
    exit 1
}

use_subfinder=false
SIZE_THRESHOLD=150
blacklist_file=""

while getopts ":f:o:e:st:b:" opt; do
  case ${opt} in
    f ) input_file="$OPTARG" ;;
    o ) output_file="$OPTARG" ;;
    e ) BAD_CODES="$OPTARG" ;;
    s ) use_subfinder=true ;;
    t ) SIZE_THRESHOLD="$OPTARG" ;;
    b ) blacklist_file="$OPTARG" ;;
    \? ) usage ;;
  esac
done

if [ -z "$input_file" ] || [ -z "$output_file" ]; then
    usage
fi

if [ -z "$BAD_CODES" ]; then
    BAD_CODES="400 403 404 405 500 501 502 503"
fi

# Créer une blacklist par défaut si aucune n'est fournie
blacklist_created=false
if [ -z "$blacklist_file" ]; then
    blacklist_file=$(mktemp)
    blacklist_created=true
    cat > "$blacklist_file" << 'EOF'
login.microsoftonline.com
login.microsoftonline.us
outlook.office365.com
portal.office.com
login.windows.net
accounts.google.com
accounts.youtube.com
signin.aws.amazon.com
console.aws.amazon.com
login.salesforce.com
secure.salesforce.com
login.yahoo.com
signin.ebay.com
secure.paypal.com
checkout.paypal.com
login.live.com
account.microsoft.com
login.skype.com
auth0.com
*.okta.com
*.onelogin.com
*.auth0.com
adfs.*.com
sso.*.com
login.*.com
auth.*.com
signin.*.com
oauth.*.com
EOF
    echo "[*] Utilisation de la blacklist par défaut ($(wc -l < "$blacklist_file") entrées)"
else
    if [ ! -f "$blacklist_file" ]; then
        echo "[!] ERREUR: Le fichier de blacklist $blacklist_file n'existe pas !"
        exit 1
    fi
    echo "[*] Utilisation de la blacklist: $blacklist_file ($(wc -l < "$blacklist_file") entrées)"
fi

# Fonction pour vérifier si un domaine/URL est dans la blacklist
is_blacklisted() {
    local url="$1"
    local domain
    domain=$(echo "$url" | sed 's|^https\?://||' | cut -d'/' -f1)
    
    # Vérifier aussi les patterns dans l'URL complète (pour les redirections vers login)
    local full_url="$url"
    
    while read -r blacklist_entry; do
        [ -z "$blacklist_entry" ] && continue
        [[ "$blacklist_entry" =~ ^#.*$ ]] && continue
        
        if [[ "$blacklist_entry" == *"*"* ]]; then
            local pattern
            pattern=$(echo "$blacklist_entry" | sed 's/\./\\./g' | sed 's/\*/.*/')
            
            # Vérifier le domaine ET l'URL complète
            if [[ "$domain" =~ $pattern ]] || [[ "$full_url" =~ $pattern ]]; then
                return 0
            fi
        else
            # Correspondance exacte du domaine
            if [ "$domain" = "$blacklist_entry" ]; then
                return 0
            fi
            
            # Vérifier si l'URL contient des mots-clés de login
            if [[ "$full_url" == *"oauth"* ]] || [[ "$full_url" == *"login"* ]] || [[ "$full_url" == *"auth"* ]] || [[ "$full_url" == *"signin"* ]]; then
                if [[ "$full_url" == *"$blacklist_entry"* ]]; then
                    return 0
                fi
            fi
        fi
    done < "$blacklist_file"
    
    return 1
}

discover_subdomains() {
    local input_file="$1"
    local temp_subdoms="subdoms_combined.txt"
    local found_tools=0
    local total_domains
    total_domains=$(wc -l < "$input_file")
    
    echo "[*] Découverte de sous-domaines avec plusieurs outils sur $total_domains domaine(s)..." >&2
    echo "[*] Contenu du fichier d'entrée:" >&2
    head -5 "$input_file" | while read -r line; do 
        echo "    - $line" >&2
    done
    if [ "$total_domains" -gt 5 ]; then
        echo "    ... et $((total_domains - 5)) autres" >&2
    fi
    echo "" >&2
    
    > "$temp_subdoms"
    
    # Subfinder
    if command -v subfinder >/dev/null 2>&1; then
        echo "[+] $(date '+%H:%M:%S') - Lancement de subfinder..." >&2
        
        subfinder -dL "$input_file" -silent > subfinder_temp.txt 2>&1 &
        subfinder_pid=$!
        
        local elapsed=0
        while kill -0 $subfinder_pid 2>/dev/null; do
            sleep 2
            elapsed=$((elapsed + 2))
            local current_results=0
            if [ -f subfinder_temp.txt ]; then
                current_results=$(wc -l < subfinder_temp.txt 2>/dev/null || echo 0)
            fi
            echo -ne "[+] subfinder en cours... ${elapsed}s - $current_results résultats trouvés\r" >&2
            
            if [ "$elapsed" -gt 120 ]; then
                echo -e "\n[!] Timeout subfinder après 120s" >&2
                kill $subfinder_pid 2>/dev/null
                break
            fi
        done
        
        wait $subfinder_pid 2>/dev/null
        
        if [ -f subfinder_temp.txt ] && [ -s subfinder_temp.txt ]; then
            cat subfinder_temp.txt >> "$temp_subdoms"
            local count
            count=$(wc -l < subfinder_temp.txt)
            echo -e "\n[✓] subfinder terminé - $count résultats trouvés" >&2
            found_tools=$((found_tools + 1))
            rm subfinder_temp.txt
        else
            echo -e "\n[✗] subfinder a échoué" >&2
            [ -f subfinder_temp.txt ] && rm subfinder_temp.txt
        fi
    else
        echo "[!] subfinder non installé" >&2
    fi
    
    # Assetfinder
    if command -v assetfinder >/dev/null 2>&1; then
        echo "[+] $(date '+%H:%M:%S') - Lancement d'assetfinder..." >&2
        local assetfinder_temp
        assetfinder_temp=$(mktemp)
        local domains_processed=0
        
        while read -r domain; do
            if [ -n "$domain" ]; then
                domains_processed=$((domains_processed + 1))
                echo -ne "[+] assetfinder: $domains_processed/$total_domains\r" >&2
                timeout 30 assetfinder --subs-only "$domain" >> "$assetfinder_temp" 2>/dev/null
            fi
        done < "$input_file"
        
        if [ -s "$assetfinder_temp" ]; then
            cat "$assetfinder_temp" >> "$temp_subdoms"
            local count
            count=$(wc -l < "$assetfinder_temp")
            echo -e "\n[✓] assetfinder terminé - $count résultats trouvés" >&2
            found_tools=$((found_tools + 1))
        else
            echo -e "\n[✗] assetfinder n'a trouvé aucun résultat" >&2
        fi
        rm -f "$assetfinder_temp"
    else
        echo "[!] assetfinder non installé" >&2
    fi
    
    # Amass (mode passif)
    if command -v amass >/dev/null 2>&1; then
        echo "[+] $(date '+%H:%M:%S') - Lancement d'amass (mode passif)..." >&2
        
        amass enum -passive -df "$input_file" -o amass_temp.txt >/dev/null 2>&1 &
        amass_pid=$!
        
        local elapsed=0
        while kill -0 $amass_pid 2>/dev/null; do
            sleep 3
            elapsed=$((elapsed + 3))
            local current_results=0
            if [ -f amass_temp.txt ]; then
                current_results=$(wc -l < amass_temp.txt 2>/dev/null || echo 0)
            fi
            echo -ne "[+] amass en cours... ${elapsed}s - $current_results résultats trouvés\r" >&2
            
            if [ "$elapsed" -gt 300 ]; then
                echo -e "\n[!] Timeout amass après 300s" >&2
                kill $amass_pid 2>/dev/null
                break
            fi
        done
        
        wait $amass_pid 2>/dev/null
        
        if [ -f amass_temp.txt ] && [ -s amass_temp.txt ]; then
            cat amass_temp.txt >> "$temp_subdoms"
            local count
            count=$(wc -l < amass_temp.txt)
            echo -e "\n[✓] amass terminé - $count résultats trouvés" >&2
            found_tools=$((found_tools + 1))
            rm amass_temp.txt
        else
            echo -e "\n[✗] amass n'a trouvé aucun résultat" >&2
            [ -f amass_temp.txt ] && rm amass_temp.txt
        fi
    else
        echo "[!] amass non installé" >&2
    fi
    
    
    echo "" >&2
    echo "[*] Résumé: $found_tools outil(s) ont fonctionné" >&2
    
    if [ "$found_tools" -eq 0 ]; then
        echo "[!] Utilisation du fichier d'entrée original" >&2
        cp "$input_file" "$temp_subdoms"
    fi
    
    if [ -s "$temp_subdoms" ]; then
        echo "[*] Nettoyage en cours..." >&2
        local before_count
        before_count=$(wc -l < "$temp_subdoms")
        
        sort -u "$temp_subdoms" | grep -v '^$' | grep -E '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$' > "$temp_subdoms.clean"
        
        # Appliquer la blacklist
        local temp_filtered
        temp_filtered=$(mktemp)
        > "$temp_filtered"
        
        while read -r domain; do
            if ! is_blacklisted "$domain"; then
                echo "$domain" >> "$temp_filtered"
            fi
        done < "$temp_subdoms.clean"
        
        mv "$temp_filtered" "$temp_subdoms"
        rm -f "$temp_subdoms.clean"
        
        local final_count
        final_count=$(wc -l < "$temp_subdoms")
        local filtered_count=$((before_count - final_count))
        echo "[✓] $final_count sous-domaines découverts ($filtered_count filtrés)" >&2
    else
        echo "[!] Utilisation du fichier d'entrée original" >&2
        cp "$input_file" "$temp_subdoms"
    fi
    
    echo "$temp_subdoms"
}

if [ "$use_subfinder" = true ]; then
    echo "[*] Découverte de sous-domaines sur $input_file..."
    
    if [ ! -f "$input_file" ]; then
        echo "[!] ERREUR: Le fichier $input_file n'existe pas !"
        exit 1
    fi
    
    if [ ! -s "$input_file" ]; then
        echo "[!] ERREUR: Le fichier $input_file est vide !"
        exit 1
    fi
    
    discovered_file=$(discover_subdomains "$input_file")
    
    if [ -f "$discovered_file" ]; then
        discovered_count=$(wc -l < "$discovered_file")
        echo "[*] Fichier découvert: $discovered_file ($discovered_count domaines)"
        
        if [ "$discovered_count" -gt 0 ]; then
            input_file="$discovered_file"
        fi
    fi
fi

seen_urls_file=$(mktemp)
final_urls_file=$(mktemp)
> "$output_file"

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
ACCEPT_ENCODING="gzip, deflate"

total_urls=$(wc -l < "$input_file")
echo "[*] Fichier final: $input_file ($total_urls URLs à scanner)"

if [ "$total_urls" -eq 0 ]; then
    echo "[!] ERREUR: Aucune URL à scanner !"
    exit 1
fi

temp_file=$(mktemp)
echo "0" > "$temp_file"

export total_urls
export temp_file
export BAD_CODES
export USER_AGENT
export ACCEPT_ENCODING
export output_file
export SIZE_THRESHOLD
export seen_urls_file
export final_urls_file
export blacklist_file

show_progress() {
    local current_url
    current_url=$(cat "$temp_file" 2>/dev/null || echo "0")
    
    # Validation des entrées
    if ! [[ "$current_url" =~ ^[0-9]+$ ]]; then
        current_url=0
    fi
    if ! [[ "$total_urls" =~ ^[0-9]+$ ]] || [ "$total_urls" -eq 0 ]; then
        return
    fi
    
    local percent=$(( (current_url * 100) / total_urls ))
    local bar_width=40
    local filled=$(( (bar_width * percent) / 100 ))
    
    local bar=""
    local i
    for i in $(seq 1 $filled); do
        bar+="█"
    done
    for i in $(seq $((filled + 1)) $bar_width); do
        bar+="░"
    done
    
    echo -ne "[$bar] $percent% ($current_url/$total_urls)\r"
}

follow_redirects() {
    local url="$1"
    local max_redirects=5
    local current_url="$url"
    local i
    
    for i in $(seq 1 $max_redirects); do
        local response
        response=$(curl -k -s -o /dev/null -w "%{http_code} %{redirect_url} %{size_download}" \
            --max-time 10 -A "$USER_AGENT" -H "Accept-Encoding: $ACCEPT_ENCODING" "$current_url" 2>/dev/null)
        
        local code redirect_url size
        read -r code redirect_url size <<< "$response"
        
        if [[ "$code" =~ ^(301|302|307|308)$ ]] && [ -n "$redirect_url" ]; then
            current_url="$redirect_url"
        else
            echo "$code $current_url $size"
            return
        fi
    done
    
    echo "000 $url 0"
}

is_url_seen() {
    local url="$1"
    local normalized_url
    normalized_url=$(echo "$url" | sed 's|/$||')
    grep -q "^$normalized_url$" "$seen_urls_file" 2>/dev/null
}

add_seen_url() {
    local url="$1"
    local normalized_url
    normalized_url=$(echo "$url" | sed 's|/$||')
    echo "$normalized_url" >> "$seen_urls_file"
}

check_url_advanced() {
    local domain="$1"
    local url_https="https://$domain"
    local url_http="http://$domain"
    
    # Vérifier la blacklist
    if is_blacklisted "$domain"; then
        return
    fi
    
    # Debug: afficher quelques domaines testés
    local current_count
    current_count=$(cat "$temp_file" 2>/dev/null || echo "0")
    if [ "$((current_count % 100))" -eq 0 ]; then
        echo "[DEBUG] Testing: $domain" >&2
    fi
    
    local https_response
    https_response=$(follow_redirects "$url_https")
    local code_https final_url_https size_https
    read -r code_https final_url_https size_https <<< "$https_response"
    
    local http_response
    http_response=$(follow_redirects "$url_http")
    local code_http final_url_http size_http
    read -r code_http final_url_http size_http <<< "$http_response"
    
    local https_valid=false
    local http_valid=false
    
    if [ "$code_https" = "200" ] && ! is_blacklisted "$final_url_https"; then
        https_valid=true
        echo "[DEBUG] Found HTTPS 200: $final_url_https" >&2
    else
        if [ "$code_https" = "200" ]; then
            echo "[DEBUG] HTTPS 200 but blacklisted: $final_url_https" >&2
        fi
    fi
    
    if [ "$code_http" = "200" ] && ! is_blacklisted "$final_url_http"; then
        http_valid=true
        echo "[DEBUG] Found HTTP 200: $final_url_http" >&2
    else
        if [ "$code_http" = "200" ]; then
            echo "[DEBUG] HTTP 200 but blacklisted: $final_url_http" >&2
        fi
    fi
    
    if [ "$https_valid" = false ] && [ "$http_valid" = false ]; then
        return
    fi
    
    if [ "$https_valid" = true ] && ! is_url_seen "$final_url_https"; then
        if [ "$http_valid" = true ]; then
            local diff_size=$(( size_https > size_http ? size_https - size_http : size_http - size_https ))
            
            if [ "$final_url_https" = "$final_url_http" ] || [ "$diff_size" -le "$SIZE_THRESHOLD" ]; then
                echo "$final_url_https" >> "$final_urls_file"
                add_seen_url "$final_url_https"
                add_seen_url "$final_url_http"
                echo "[DEBUG] Added: $final_url_https" >&2
            else
                echo "$final_url_https" >> "$final_urls_file"
                add_seen_url "$final_url_https"
                echo "[DEBUG] Added: $final_url_https" >&2
                
                if ! is_url_seen "$final_url_http"; then
                    echo "$final_url_http" >> "$final_urls_file"
                    add_seen_url "$final_url_http"
                    echo "[DEBUG] Added: $final_url_http" >&2
                fi
            fi
        else
            echo "$final_url_https" >> "$final_urls_file"
            add_seen_url "$final_url_https"
            echo "[DEBUG] Added: $final_url_https" >&2
        fi
    elif [ "$http_valid" = true ] && ! is_url_seen "$final_url_http"; then
        echo "$final_url_http" >> "$final_urls_file"
        add_seen_url "$final_url_http"
        echo "[DEBUG] Added: $final_url_http" >&2
    fi
}

export -f check_url_advanced
export -f show_progress
export -f follow_redirects
export -f is_url_seen
export -f add_seen_url
export -f is_blacklisted

echo "[*] Scan en cours (30 processus parallèles)..."

start_time=$(date +%s)
export start_time

cat "$input_file" | sed 's|^https\?://||' | xargs -P 30 -I {} bash -c '
    if [ -f "$temp_file" ]; then
        current_url=$(cat "$temp_file" 2>/dev/null || echo "0")
        if [[ "$current_url" =~ ^[0-9]+$ ]]; then
            current_url=$((current_url + 1))
            echo "$current_url" > "$temp_file"
        fi
    fi
    check_url_advanced "{}"
    show_progress
'

echo -e "\n[*] Finalisation..."
sort -u "$final_urls_file" > "$output_file"

final_count=$(wc -l < "$output_file")
total_time=$(( $(date +%s) - start_time ))
echo "[✓] Scan terminé en ${total_time}s ! $final_count URLs trouvées dans $output_file"

rm -f "$temp_file" "$seen_urls_file" "$final_urls_file"
[ -f "subdoms_combined.txt" ] && rm -f "subdoms_combined.txt"

if [ "$blacklist_created" = true ]; then
    rm -f "$blacklist_file"
fi
