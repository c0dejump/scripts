import requests
from bs4 import BeautifulSoup
import sys, os, re

requests.packages.urllib3.disable_warnings(requests.packages.urllib3.exceptions.InsecureRequestWarning)

def req_domain(url, scan=False):
    try:
        req = requests.get(url, verify=False, allow_redirects=False, timeout=2)
        if req.status_code == 200:
            return url, 1
        elif req.json() or "xml" in req.text:
            if "404" in req.text or req.status_code == 404:
                return 0, 0
            elif req.status_code == 401:
                return url, 3
            else:
                return url, 2
        else:
            0, 0
    except:
        return 0, 0

def try_api(api_found, run=False):
    for api in api_found:
        print("\ntry with: {}".format(api))
        with open("test.txt", "r") as endpoints:
            for endpoint in endpoints.read().splitlines():
                url_endpoint = "{}{}".format(api, endpoint)
                req_e, status = req_domain(url_endpoint, run)
                #print(url_endpoint)
                if req_e and status == 1:
                    print("[+] {}".format(req_e))
                    if run:
                        return True, req_e
                elif req_e and status == 2:
                    print("[+] Potential {}".format(req_e))
                    if run:
                        return True, req_e
                elif req_e and status == 3:
                    print("[!] 401 {}".format(req_e))
                else:
                    pass


def test_api_url(url, run=False):
    api_found = []
    with open("api_url.txt", "r") as apis_url:
        found = False
        for apis in apis_url.read().splitlines():
            api_domain = ["http://{}.{}/".format(apis, url), "https://{}.{}/".format(apis, url), "http://{}/{}/".format(url, apis), "https://{}/{}/".format(url, apis)]
            for api_urls in api_domain:
                if run:
                    api_urls = [api_urls] 
                    bf, req_e = try_api(api_urls, run)
                    if bf:
                        run = False
                        api_domain.append(req_e)
                else:
                    req_d, status = req_domain(api_urls)
                    if req_d and status == 1:
                        print("API found: {}".format(req_d))
                        found = True
                        api_found.append(req_d)
                    elif req_d and status == 2:
                        print("Potential API found: {}".format(req_d))
                        found = True
                        api_found.append(req_d)
                    else:
                        pass
        if not found:
            try:
                answer = raw_input("Nothing API found, still try ?(y:n)\n")
            except:
                answer = input("Nothing API found, still try ?(y:n)\n")
            if answer == "y":
                test_api_url(url, run=True)
            else:
                pass
    if api_found:
        try_api(api_found, run=True)
    else:
        pass              

if __name__ == '__main__':
    url = "netflix.com"
    test_api_url(url)