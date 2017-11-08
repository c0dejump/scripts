import os,sys
import re

post = "$_POST"
get = "$_GET"
i = 1

payloads = ["addslashes","magic_quotes_gpc"]

PRETTY_PLUS = "\033[32m[+] \033[0m"
PRETTY_LESS = "\033[31m[-] \033[0m"

try:
	file = open(sys.argv[1],"r").read().split('\n')
	print "file found"
except:
	print "file not found"


for line in file:
	if post in line:
		print PRETTY_PLUS + "variable " + post + " found ligne " + str(i)
		for payl in payloads:
			if payl in line:
				print "\t" + PRETTY_LESS + "filtre found " + payl + " in " + post
	if get in line:
		print PRETTY_PLUS + "variable " + get + " found"
		for payl in payloads:
			if payl in line:
				print "\t" + PRETTY_LESS + "filtre found " + payl + " in " + get	
	i += 1

with open(sys.argv[1],"r") as f:
	for lines in f.readlines():
		if "@" in lines:
			print PRETTY_PLUS + "@ disable warning found ligne " + str(i)
		i += 1 
