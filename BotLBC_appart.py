#bot recherche appartement à paris sur leboncoin

#!/usr/bin/env python
#-*- coding: utf-8 -*-

import requests
import sys
import time
from bs4 import BeautifulSoup
from fake_useragent import UserAgent
from datetime import date

"""
https://www.leboncoin.fr/locations/offres/ile_de_france/hauts_de_seine/?th=1&mre=600&sqe=1&ret=2&furn=1
https://www.leboncoin.fr/locations/offres/?th=1&location=Meudon&mre=600&sqe=2&ret=2&furn=1
sqe=1 = 20m2
"""


today = date.today()
a_h = today.day - 2 #avant hier
a_ah = today.day - 3# avant avant hier

#département "pays_de_la_loire".....
depart = "ile_de_france/hauts_de_seine"

#Villes :
ville = [
		u"Sèvre",
		u"Boulogne-Billancourt",
		u"Issy-les-Moulineaux",
		u"Saint-Cloud",
		u"Meudon",
		u"Ville-d'Avray",
		u"Clamart",
		u"Puteaux",
		u"Nanterre"
]

#les dernieres annonces sur 4 jours
date_post = [
		"Aujourd'hui",
		"Hier",
		str(a_h),
		str(a_ah)
]

prix_max = "600"
surface = "1" #surface max : 1 = 20m2 ; 2 = 25m2; 3 = 30m2; 4 = 35m2; 5 = 40m2; 6 = 50m2.....
m = "1" #1 = meublé; 2 = non meublé

page = "1"
res = 0

while 1:
	ua = UserAgent()
	user_agent = {'User-agent': ua.random} #changement d'user-agent (random)
	for c in ville:
		url = "https://www.leboncoin.fr/locations/offres/" + depart + "/?th=" + page + "&mre=" + prix_max + "&sqe=" + surface + "&ret=2&furn=" + m
		print url
		req = requests.get(url, headers=user_agent)
		stat = req.status_code
		if stat == 200:
			if "Urgentes" not in req.text:
				print "URL not found"
				break
			else:
				print "\033[42m URL found \033[0m"
				print "*" * 15
				if "Aucune" in req.text: #si aucune annonce trouver
					print "Aucune annonce trouve"
					print "*" * 15
					break
				else:
					soup = BeautifulSoup(req.text,"html.parser")
					resultats = soup.find('section', {"class":"tabsContent block-white dontSwitch"})
					annonces = resultats.find_all("li")
					for p in annonces:
						tag_a = p.find("a")
						lien_annonce = tag_a.get("href") # prend les liens
						title = p.find("h2").text.strip()
						price = p.find("h3").find(text=True, recursive=False).strip()
						for i in ville:
							for d in date_post:
								if d in p.text:
									if i in p.text:	
										print "\033[32m[+] \033[0m " + title + " : \033[41m" + price + "\033[0m / " + i + " | date : "+ d  
										# affiche du titre de l'annonce, du prix, de la ville et de la date
										print lien_annonce.replace("//","--> ")
										print "\033[34m-\033[0m" * 30 + "\n"
										res = res + 1							
									else:
										break

					print "*" * 15
					print "resultat : " + str(res) #nombre de resultat trouver

		scd = 1200
		tim = scd / 60
		i = tim - 1
		s = 60
		while i != 0:
			while s != 0:
				sys.stdout.write(str(tim) +" min avant renvoi : " + str(i) + "m" + str(s) + " ... \r")
				sys.stdout.flush()
				time.sleep(10)
				s -= 10
			s = 60
			i -= 1
		res = 0
		i = 0
