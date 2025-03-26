#!/bin/bash

# Fonction d'aide pour afficher l'utilisation
usage() {
    echo "Usage: $0 -f fichier_urls.txt -o fichier_sortie [-e codes_a_exclure]"
    echo
    echo "Options :"
    echo "  -f    Fichier d'entrée contenant les URLs"
    echo "  -o    Fichier de sortie pour les URLs valides"
    echo "  -e    Codes HTTP à exclure (ex: 400 404 500) [default: 400 404 405 500 501 502]"
    exit 1
}

# Vérification des arguments
while getopts ":f:o:e:" opt; do
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
    \? )
      usage
      ;;
  esac
done

# Vérifie si les fichiers d'entrée et de sortie sont spécifiés
if [ -z "$input_file" ] || [ -z "$output_file" ]; then
    usage
fi

# Si aucun code d'exclusion n'est spécifié, définir un ensemble de codes par défaut
if [ -z "$BAD_CODES" ]; then
    BAD_CODES="400 404 405 500 501 502"
fi

# Nettoie le fichier de sortie s'il existe déjà
> "$output_file"

# Définition du User-Agent et Accept-Encoding
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36"
ACCEPT_ENCODING="gzip"

# Compte le nombre total de lignes dans le fichier d'entrée
total_urls=$(wc -l < "$input_file")
if [ "$total_urls" -eq 0 ]; then
    echo "Le fichier est vide. Aucun URL à traiter."
    exit 1
fi

# Création d'un fichier temporaire pour garder l'état de current_url
temp_file=$(mktemp)

# Initialisation de current_url à 0 dans le fichier temporaire
echo 0 > "$temp_file"

# Exporter les variables nécessaires
export total_urls
export temp_file
export BAD_CODES
export USER_AGENT
export ACCEPT_ENCODING
export output_file

# Fonction pour afficher la barre de progression
show_progress() {
    current_url=$(cat "$temp_file")  
    percent=$((100 * current_url / total_urls))
    
    # Définir la largeur de la barre de progression
    bar_width=50
    filled=$((bar_width * percent / 100))
    
    bar=""
    for i in $(seq 1 $filled); do
        bar="${bar}#"
    done
    for i in $(seq $filled $((bar_width - 1))); do
        bar="${bar} "
    done
    
    echo -ne "[$bar] $percent% ($current_url/$total_urls)\r"
}


# Fonction pour tester une URL
check_url() {
    url="$1"
    response_code=$(curl -k -s -o /dev/null -w "%{http_code}" --max-time 15 \
        -A "$USER_AGENT" -H "Accept-Encoding: $ACCEPT_ENCODING" "$url")

    # Ignore les erreurs de connexion
    if [ "$response_code" == "000" ]; then
        return
    fi

    # Si le code réponse n'est pas dans les codes à ignorer
    if [[ ! $BAD_CODES =~ $response_code ]]; then
        # Normaliser l'URL avant de l'ajouter au fichier de sortie
        if [[ ! "$url" =~ \/(index\.php|index\.html|api\/|[^/]+$) ]]; then
            url="$url/"
        fi
        echo "$url" >> "$output_file"
    fi
}

export -f check_url
export -f show_progress

# Préparer les URLs en supprimant http:// et https:// puis générer les variantes
cat "$input_file" | sed 's|^https\?://||' | xargs -P 20 -I {} bash -c '
    current_url=$(cat "$temp_file")  # Lire current_url depuis le fichier temporaire
    current_url=$((current_url + 1))  # Incrémenter current_url
    echo $current_url > "$temp_file"  # Sauvegarder current_url dans le fichier temporaire
    check_url "https://{}" && check_url "http://{}"
    show_progress
'

# Affichage de la barre de progression complète
echo -e "\nTraitement terminé. Résultats dans $output_file."
