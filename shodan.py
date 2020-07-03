#! /usr/bin/env python
# -*- coding: utf-8 -*-

import mmh3
import requests
import argparse
import os
import subprocess

requests.packages.urllib3.disable_warnings(requests.packages.urllib3.exceptions.InsecureRequestWarning)

def main(hash_fav, url):
    domain = url.split("/")[2]
    print("\nUrl: {}\nDomain: {}\nhash favicon: {}\n".format(url, domain, hash_fav))
    search_shodan = subprocess.Popen(
        """
        shodan search hostname:"{}" http.favicon.hash:{} --fields ip_str,port --separator " " 
        """.format(domain, hash_fav), shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    s_shodan = [s for s in search_shodan.stdout.readlines()]
    for s in s_shodan:
        if "Error" not in s:
            print("potentialy vuln")
            print(s)
        else:
            print("[-] Nothing found, try with just domain:\n")
            check_shodan = subprocess.Popen('shodan search hostname:"{}" | grep "200" '.format(domain), shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            c_shodan = [c for c in check_shodan.stdout.readlines()]
            for c in c_shodan:
                print(c.replace("\\n","\n").replace("\\r", "\r"))

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument("-u", help="URL", dest='url')
    parser.add_argument("-f", help="URL to favicon", dest='url_fav')
    results = parser.parse_args()
                                     
    url = results.url
    url_fav = results.url_fav

    r = requests.get(url_fav ,verify=False)
    hash_fav = mmh3.hash(r.content.encode('base64'))
    hash_fav = -hash_fav if "-" in str(hash_fav) else hash_fav

    main(hash_fav, url)
