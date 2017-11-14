import os,sys
import re

post = "$_POST"
get = "$_GET"
cookie = "$_COOKIE"
i = 1

payloadsql = ["addslashes","magic_quotes_gpc","mysql_real_escape_string","intval","is_numeric"]

PLUS = "\033[32m[+] \033[0m"
PFILTR = "\033[33m[+] \033[0m"
LESS = "\033[31m[-] \033[0m"
WARN = "\033[31m[!] \033[0m"


try:
	file = open(sys.argv[1],"r").read().split('\n')[:-1]
	print "file found"
	print "_______________________________\n"
except:
	print "file not found"

def inject(plop):
	print PLUS + "variable " + plop + " found / ligne " + str(i)
	found = False
	for payl in payloadsql:
		if payl in line:
			print "\t" + PFILTR + "filtre " + payl + "() in " + plop
			found = True
			break
	if not found:
		print "\t" + LESS + "no filtre in " + plop


for line in file:
	if post in line:
		inject(post)

	if get in line:
		inject(get)

	if cookie in line:
		inject(cookie)

	if "select" in line or "SELECT" in line and "from" in line or "FROM" in line:
		print PLUS + line.replace("  ","") + " / ligne " + str(i) + "\n"

	if "echo $_GET" in line or "echo $_POST" in line:
		print "\t" + WARN + "risk XSS / ligne " + str(i)

	if "include" in line:
		print PLUS + "include() found / line " + str(i)
		find = file.index(line) - 1
		if "file_exists" in file[find]:
			print "\t" + PFILTR + "filtre file_exists() "
		else:
			print "\t" + LESS + "no filtre in include() "
			print "\t" + WARN + "risk to faille include"

	i += 1
