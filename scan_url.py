import requests
import sys
import time

url = sys.argv[1]

requests.packages.urllib3.disable_warnings(requests.packages.urllib3.exceptions.InsecureRequestWarning)

def tryUrl():
	dico = raw_input("entrez un dico : ")
	try:
		global payload 
		payload = open(dico,"r").read().split("\n")
	except:
		print "dico not found"
		tryUrl()
	for payl in payload:
		link = url + payl
		try:
			req = requests.get(link, allow_redirects=False, verify=False)
			#time.sleep(3)
			status_link = req.status_code
			sys.stdout.write(" "+payl+"\r")
			sys.stdout.flush()
			if status_link == 200:
				print "\033[32m[+] \033[0m" + link
			if status_link == 403:
				print "\033[33m[+] \033[0m" + link + "\033[33m forbidden \033[0m"
		#	if status_link == 302 or status_link == 301:
		#		print "\033[33m[+] \033[0m" + link + "\033[33m Moved Temporarily \033[0m"
		except:
			pass

def tryUrlforbi():
	dico = raw_input("entrez un dico : ")
	try:
		global payload 
		payload = open(dico,"r").read().split("\n")
	except:
		print "dico not found"
		tryUrl()
	for payl in payload:
		link = url + payl
		try:
			req = requests.get(link, allow_redirects=False, verify=False)
			#time.sleep(3)
			status_link = req.status_code
			sys.stdout.write(" "+payl+"\r")
			sys.stdout.flush()
			if status_link == 200:
				print "\033[32m[+] \033[0m" + link
			if status_link == 403:
				pass
			if status_link == 302 or status_link == 301:
				print "\033[33m[+] \033[0m" + link + "\033[33m Moved Temporarily \033[0m"
		except:
			pass


r = requests.get(url, verify=False)
stat = r.status_code
print url
if stat == 200:
	print "url found"
	tryUrl()
elif stat == 301:
	print "HTTP/2.0 301 Moved Permanently"
	tryUrl()
elif stat == 302:
	print "Moved Temporarily"
	tryUrl()
elif stat == 404:
    a = raw_input("not found/ forced ?(y:n)")
    if a == "y":
        tryUrl()
    else:
        sys.exit()
elif stat == 403:
    a = raw_input("forbidden/ forced ?(y:n)")
    if a == "y":
        tryUrlforbi()
    else:
        sys.exit()
else:
	print "url not found"
