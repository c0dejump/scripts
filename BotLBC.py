#petit bot de recherche de voitures leboncoin

#!/usr/bin/env python
#-*- coding: utf-8 -*-

import requests
from bs4 import BeautifulSoup
import time
from fake_useragent import UserAgent
import sys

"""
		"Opel",
		"Peugeot",
		"Honda",
		"Citroen",
		"Skoda"
"""

ville = [
		"Angers",
		"Le Mans",
		"Nantes"
]


def resultat(soup): #resultat de nombre de voitures trouvees
	for x in soup.find_all('nav',{"class":"fl"}):
		result = x.find('span',{"class":"tabsSwitchNumbers small-hidden tiny-hidden"})
		print "resultats trouve : " + result.text.replace("	","").replace(" ","").replace("\n","") + "\n"

v = sys.argv[1]
voiture = sys.argv[2]
#python -v(sys1) NameCars(sys2)

page = "1"
kmax = "125000" #km max
location = "Nantes,Rennes"# city, more = "city,city,city"

while 1:
	if len(v) < 2 or len(voiture) < 2:
		print "Error arguments"
		break
	elif str(v) != "-v":
		print "Error syntax: file.py -v Nom_Voiture"
		break
	else:
		ua = UserAgent()
		user_agent = {'User-agent': ua.random} #changement d'user-agent (random)
		url = "https://www.leboncoin.fr/voitures/offres/?th="+ page +"&location=" + location + "&ps=3&pe=6&me="+ kmax + "&brd=" + voiture + "&gb=1"
		req = requests.get(url, headers=user_agent)
		stat = req.status_code
		if stat == 200:
			if "Urgentes" not in req.text:
				print "URL not found"
				break
			else:
				print "URL found"
				print "*" * 15
				if "Aucune" in req.text:
					print "Aucune annonce trouve"
					print "*" * 15
					break
				else:
					soup = BeautifulSoup(req.text,"html.parser")
					for p in soup.find_all('section', {"class":"item_infos"}):
						title = p.find("h2")
						price = p.find("h3")
						for i in ville:
							if i in p.text:
								t =  title.text.replace("	","").replace("\n","")
								print "\033[32m[+] \033[0m " + t.replace("  ","") + " : \033[41m" + price.text.replace("	","").replace(" ","").replace("\n","") + "\033[0m / " + i
								print "\033[34m-\033[0m" * 30 + "\n"
					print "*" * 15
					resultat(soup)
		time.sleep(600)# 5 min
