#A python script which pentest a website with CVEs and other stuff...( in development)

import sys, os
import requests, urllib, urllib2
from bs4 import BeautifulSoup
from parse import *
import time

url = sys.argv[1]

def write_response(resp):
    mon_fichier = open("reponse.txt", "w")    #Download file
    mon_fichier.write(resp)
    mon_fichier.close()

def scurl(): 
		dico = raw_input("entrez un dico : ")
		try:
			global payload 
			payload = open(dico,"r").read().split("\n")
		except:
			print "dico introuvable"
			scurl()

r = requests.get(url)
stat = r.status_code
if stat == 200:
	print "url found"
	rob = url+"robots.txt"
	r_rob = requests.get(rob)
	if r_rob.status_code == 200: #try robots.txt
		print "\033[32m[+] \033[0m"+url+"robots.txt/ [found]"
		affi = raw_input("afficher le contenue de robots.txt ? y/n : ")
		if affi == 'y':
			page = urllib.urlopen(rob)
			resp = page.read()
			page.close()
			print resp
			write_response(resp)
			curl = raw_input("tester les urls ? y/n : ")   #try urls
			if curl == "y":
				scurl()
				for payl in payload:
					link = url + payl
					req = requests.get(link)
					status_link = req.status_code
					sys.stdout.write(" "+payl+"\r")
					sys.stdout.flush()
					if status_link == 200:
						print "\033[32m[+] \033[0m" + link
				print "ok"			
			else:
				print "plop"
		else:
			curl = raw_input("tester les urls ? y/n : ")   #try urls
			if curl == "y":
				scurl()
				for payl in payload:
					link = url + payl
					req = requests.get(link)
					status_link = req.status_code
					sys.stdout.write(" "+payl+"\r")
					sys.stdout.flush()
					if status_link == 200:
						print "\033[32m[+] \033[0m" + link
				print "ok"
			else:
				print "plop"
	else:
		print "robots.txt not found"
elif stat == 301:
	print "HTTP/2.0 301 Moved Permanently"
elif stat == 302:
	print "Moved Temporarily"
else:
	print "url not found"


