# -*- coding: utf-8 -*-

import requests
import sys
import time
import ssl, OpenSSL
import socket
import pprint

url = sys.argv[1]

RED = "\033[31m[!] \033[0m"
GREEN = "\033[32m[+] \033[0m"

requests.packages.urllib3.disable_warnings(requests.packages.urllib3.exceptions.InsecureRequestWarning)

#bf dico
def tryUrl(forced=False):
	try:
		dico = raw_input("entrez un dico : ")
		global payload 
		payload = open(dico,"r").read().split("\n")
	except:
		print "dico not found"
		tryUrl()
	for payl in payload:
		link = url + payl
		try:
			req = requests.get(link, allow_redirects=True, verify=False)
			#time.sleep(3)
			status_link = req.status_code
			sys.stdout.write(" "+payl+"\r")
			sys.stdout.flush()
			if status_link == 200:
				print GREEN + link
			if status_link == 403:
				if not forced:
					print RED + link + "\033[31m Forbidden \033[0m"
				else:
					pass
			if status_link == 301:
				print "\033[33m[+] \033[0m" + link + "\033[33m 301 Moved Permanently \033[0m"
			elif status_link == 302:
				print "\033[33m[+] \033[0m" + link + "\033[33m 302 Moved Temporarily \033[0m"
		except:
			print "url error"

# affiche le certificat
def get_certif(url):
	if "https" in url:
		print "certificat :"
		url = url.replace('https://','').replace('/','')
		context = ssl.create_default_context()
		conn = context.wrap_socket(socket.socket(socket.AF_INET),server_hostname=url)
		conn.connect((url, 443))
		cert = conn.getpeercert()
		print "=" * 20
		pprint.pprint(str(cert['subject']).replace(',','').replace('((','').replace('))',''))
		print "=" * 20
		pprint.pprint(cert['subjectAltName'])
		print "=" * 20
		pprint.pprint(str(cert['issuer']).decode('utf-8').replace(',','').replace('((','').replace('))',''))
	else:
		pass

def status(stat):
	if stat == 200:
		print GREEN + " url found"
		tryUrl()
	elif stat == 301:
		print GREEN + " 301 Moved Permanently"
		tryUrl()
	elif stat == 302:
		print GREEN + " 302 Moved Temporarily"
		tryUrl()
	elif stat == 404:
	    a = raw_input("[-] not found/ forced ?(y:n)")
	    if a == "y":
	        tryUrl()
	    else:
	        sys.exit()
	elif stat == 403:
	    a = raw_input(RED + " forbidden/ forced ?(y:n)")
	    if a == "y":
	        tryUrl(forced)
	    else:
	        sys.exit()
	else:
	    a = raw_input("[-] not found/ forced ?(y:n)")
	    if a == "y":
	    	tryUrl()
	    else:
	    	sys.exit()

if __name__ == '__main__':
	r = requests.get(url, verify=False)
	stat = r.status_code
	print "url: " + url + "\n"
	get_certif(url)
	status(stat)
