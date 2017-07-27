import sys
import requests
from bs4 import BeautifulSoup
import re

url = ""
rep = raw_input("go/stop\n")


if rep == "go":
	for date in range(1999,2018):
		print "type DoS"
		url = "https://www.cvedetails.com/vulnerability-list/year-"+str(date)+"/opdos-1/denial-of-service.html"
		req = requests.get(url)
		soup = BeautifulSoup(req.text,"html.parser")
		urls, scores = [cve["href"] for cve in soup.select(".srrowns td[nowrap] a")], [float(cve.text) for cve in soup.select(".cvssbox")]
		a = [(u, s) for (u, s) in zip(urls, scores) if s >= 5.0]
		b = "\n"+str(a)+"\n"
		fichier = open("DoS.txt", "a")
		fichier.write(b.replace("u","").replace("(","").replace(")","").replace("'","").replace("[","").replace("]",""))
		fichier.close()
		print b
		payl = open("DoS.txt","r").read().split(",")
		for payload in payl:
			urli = "http://wwww.cvedetails.com/cve"+payload[5:]
			rq = requests.get(urli)
			soup = BeautifulSoup(rq.text,"html.parser")
			title = soup.find_all("h1")
			detail = soup.find_all('table', id="cvssscorestable", class_="details")
			fichi = open("DoS_info.html","a")
			ok = str(title)+str(url)+str(detail)
			fichi.write(str(str(ok.replace("[","").replace("]","")).split('\n')))
			fichi.close()
			print detail	
	


