import socket
import struct
import sys

mensagem = b'dados aquiii'
grupo_multicast = ('224.3.29.71', 10000)

#socket de datagrama (udp):
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

sock.settimeout(0.2)

#definindo ttl como 1:
ttl = struct.pack('b', 1)
sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, ttl)

try:
	print(f'Enviando "{mensagem.decode()}"', file=sys.stderr)

	#enviando msg para o end multicast:
	sock.sendto(mensagem, grupo_multicast)

	while True:
		try:
			data, server = sock.recvfrom(16)
		except socket.timeout:
			print("Timeout alcançado, não tem mais resposta", file=sys.stderr)
			break
		else:
			print(f'Recebido, "{data.decode()}" de {server}', file=sys.stderr)

finally :
	print('Fechando socket', file=sys.stderr)
	sock.close()
