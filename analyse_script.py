import os,sys
import re

post = "$_POST"
get = "$_GET"
i = 1

payloads = ["addslashes","magic_quotes_gpc","mysql_real_escape_string","intval","is_numeric"]

PLUS = "\033[32m[+] \033[0m"
PFILTR = "\033[33m[+] \033[0m"
LESS = "\033[31m[-] \033[0m"
WARN = "\033[31m[!] \033[0m"


try:
	file = open(sys.argv[1],"r").read().split('\n')[:-1]
	print "file found"
except:
	print "file not found"


for line in file:
	if post in line:
		print PLUS + "variable " + post + " found / ligne " + str(i)
		found = False
		for payl in payloads:
			if payl in line:
				print "\t" + PFILTR + "filtre " + payl + "() in " + post
				found = True
				break
		if not found:
			print "\t" + LESS + "no filtre in " + post
				
	if get in line:
		print PLUS + "variable " + get + " found / ligne " + str(i)
		found = False
		for payl in payloads:
			if payl in line:
				print "\t" + PFILTR + "filtre " + payl + "() in " + get
				found = True
				break
		if not found:
			print "\t" + LESS + "no filtre in " + get

	if "select" in line or "SELECT" in line and "from" in line or "FROM" in line:
		print PLUS + line.replace("  ","") + " / ligne " + str(i) + "\n"

	if "echo $_GET" in line or "echo $_POST" in line:
		print "\t" + WARN + "risk XSS / ligne " + str(i)
	i += 1
