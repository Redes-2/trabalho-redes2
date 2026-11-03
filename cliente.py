import socket
import struct
import sys

import chess


grupo_multicast = ('224.3.29.71', 10000)

#socket de datagrama (udp):
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

#tive que aumentar
sock.settimeout(2.0)

#definindo ttl como 1:
ttl = struct.pack('b', 1)
sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, ttl)


# função para enviarmos requisições aos servidores
def envia_e_espera(mensagem):
	print(f'Enviando "{mensagem}"', file=sys.stderr)
	sock.sendto(mensagem.encode(),grupo_multicast)
	try:
		data, server = sock.recvfrom(1024) #o FEN não cabe e 16 bytes
	except socket.timeout:
		print("Timeout alcançado, nenhum líder respondeu", file=sys.stderr)
		return None
	print(f'Recebido de {server}', file=sys.stderr)
	return data.decode().split("|")


# MAIN

try:
	while True:
		#1. Consulta o tabuleiro
		resposta = envia_e_espera("READ")
		if resposta is None:
			if input("Tentar de novo? (s/n) ").strip().lower() != "s":
				break
			continue
		_, fen, situacao = resposta
		print(chess.Board(fen))
		print(situacao)
		if chess.Board(fen).is_game_over():
			break

		#2. Manda movimento (estamos controlando os dois lados por enqunanto)
		lance = input("Lance (ex: e2e4) ou 'sair': ").strip()
		if lance == "sair":
			break
		resposta = envia_e_espera(f"MOVE|{lance}")
		if resposta is not None and resposta[0] == "ERRO":
			print(resposta[1])
		#se veio ok, volta o laço

finally:
	print('Fechando socket', file=sys.stderr)
	sock.close()