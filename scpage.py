import sys, os
import requests
from bs4 import BeautifulSoup

url = sys.argv[1]

def writeReq(o):
	file = open("bla.txt", "w")
	file.write(str(o).replace('None',''))
	file = open("bla.txt")
	print "\033[32m[+] \033[0m "+file.read()
	file.close()
	os.remove("bla.txt")

req = requests.get(url)
soup = BeautifulSoup(req.text,"html.parser")
for p in soup.find_all('script'):
	o = p.get("src")
	writeReq(o)
for i in soup.find_all('a'):
	o = i.get("href")
	writeReq(o)
