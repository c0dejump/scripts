import socket
import sys

url = sys.argv[1]

for port in range(1,9999):
	try:
		sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
		result = sock.connect_ex((url, port))
		sys.stdout.write("Port: "+str(port)+"\r")
		sys.stdout.flush()
		if result == 0:
			proto = socket.getservbyport(port)
			print "Port: "+str(port)+"/"+proto+" Open"
			sock.close()
	except socket.gaierror:
		print "impossible de se connecter a l'ip"
		sys.exit()
	except socket.error:
		print "impossible de se connecter au server"
		sys.exit()
