import hashlib
import re
#
def all():
    error = "hash introuvable"
    mot = raw_input("entrez un hash:")
    longueur = str(len(mot))
    print "longueur: " + longueur
    print mot
    print("recherche du type de hash...")
#---------sha1----------------------
    if re.match("^[0-9a-fA-F]{40}$",mot):
        print "ceci est un sha1"
        dico = raw_input("entrez le nom du dico:")
        payloads = open(dico,"r").read().split("\n")
        for payl in payloads:
            #translate dico -> hash -- hash -> dico
            m = hashlib.sha1()
            m.update(payl)
            ok = m.hexdigest()
            if ok == mot:
                print "SUCCESS with:",payl
                break
            elif ok != mot:
                print "echec with:",payl
            else:
                print "mot introuvable dans le dico"
#--------sha256---------------------
    elif re.match("^[0-9a-fA-F]{64}$",mot):
        print "ceci est un sha256"
        dico = raw_input("entrez le nom du dico:")
        payloads = open(dico,"r").read().split("\n")
        for payl in payloads:
        #translate dico -> hash -- hash -> dico
            m = hashlib.sha256()
            m.update(payl)
            ok = m.hexdigest()
            if ok == mot:
                print "SUCCESS with:",payl
                break
            elif ok != mot:
                print "echec with:",payl
            else:
                print "mot introuvable dans le dico"
#------------md5--------------------
    elif re.match("^[0-9a-fA-F]{32}$",mot):
        print "ceci est un md5"
        dico = raw_input("entrez le nom du dico:")
        payloads = open(dico,"r").read().split("\n")
        for payl in payloads:
            #translate dico -> hash -- hash -> dico
            m = hashlib.md5()
            m.update(payl)
            ok = m.hexdigest()
            if ok == mot:
                print "SUCCESS with:",payl
                break
            elif ok != mot:
                print "echec with:",payl
            else:
                print "mot introuvable dans le dico"
#---------nothing-------------------
    else:
        print error
        while error:
            mot
            if mot != error:
                all()

all()