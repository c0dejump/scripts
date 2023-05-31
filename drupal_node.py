#! /usr/bin/env python3
# -*- coding: utf-8 -*-

import sys
import requests
from lxml.html import fromstring
import argparse

requests.packages.urllib3.disable_warnings(requests.packages.urllib3.exceptions.InsecureRequestWarning)


def main(url, type_, s, ranges):
    type_ = "taxonomy/term/" if type_ == "taxonomy" else "node/"
    if ranges:
        range_1 = ranges.split("-")[0]
        range_2 = ranges.split("-")[1]
    else:
        range_1 = 0
        range_2 = 1000
    for i in range(int(range_1),int(range_2)):
        uri = "{}{}{}".format(url, type_, i)
        req = s.get(uri, verify=False)
        if req.status_code not in [404] and len(req.content) != 174921:
            tree = fromstring(req.content)
            title = tree.findtext('.//title')
            print("\033[32m{}\033[0m - [{}b] - {} :: \033[34m{}\033[0m".format(req.status_code, len(req.content), uri, title))
        sys.stdout.write(" {} \r".format(uri))
        sys.stdout.write("\033[K")


if __name__ == '__main__':

    parser = argparse.ArgumentParser()

    parser.add_argument("-u", help="URL login to test \033[31m[required]\033[0m", dest='url')
    parser.add_argument("-r", help="range (Ex: 0-1000); Default: 0-1000", dest='ranges', required=False)
    parser.add_argument("-t", help="type of scan (taxonomy or node)", dest='type_', required=False)
    results = parser.parse_args()
                                     
    url = results.url
    ranges = results.ranges
    type_ = results.type_

    s = requests.Session()
    s.headers.update({'User-agent': 'Mozilla/5.0 (Windows NT 6.3; WOW64; Trident/7.0; LCJB; rv:11.0) like Gecko'})


    main(url, type_, s, ranges)
