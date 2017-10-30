import socket
import sys
import time
from scapy.all import *

url = sys.argv[1]

startTime = int(time.time())
endTime = int(time.time())
t = endTime-startTime

print url
print "scan..."
for port in range(1,65535):
	try:
		sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
		sock.settimeout(0.09)
		result = sock.connect_ex((url, port))
		sys.stdout.write("Port: "+str(port)+"\r")
		sys.stdout.flush()
		if result == 0:
			proto = socket.getservbyport(port)
			print "\033[32m[+] \033[0m Port: "+ str(port)+"/"+proto+" Open"
			sock.close()
		if port == 65534:
			print "scan finish"
	except socket.gaierror:
		print "impossible de se connecter a l'ip"
		sys.exit()
	except socket.error:
		print port
		print "impossible de se connecter au server"
		sys.exit()
	except socket.timeout:	
		print "timeout socket"	
		sys.exit()
