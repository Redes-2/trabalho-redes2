import  socket
import  struct
import  sys
import time
import threading

#VARIÁVEIS GLOBAIS:
MULTICAST_IP = '224.3.29.71'
MULTICAST_PORT = 10000
MULTICAST_ADDRESS = (MULTICAST_IP, MULTICAST_PORT)
servidores_vivos = {}

#lgc para pegar o uid do servidor passado no argumento:
if len(sys.argv) < 2:
    print(f"Uso correto: python3 {sys.argv[0]} <MEU_ID>", file=sys.stderr)
    sys.exit(1)
MEU_ID = int(sys.argv[1])

#----------------------------------------------------------------------------------------------------------#
#FUNÇÃO DE ELEGE O LÍDER:
def elege_lider():
	menor = 100000
	for uid, ultimo_tempo in list(servidores_vivos.items()):
		if (uid < menor):
			menor = uid

	if menor==100000:
		return -1

	return menor


#----------------------------------------------------------------------------------------------------------#
#FUNÇÕES DO DICIONÁRIO:
#atualiza dicionário com o momento exato que o ID deu um pulso:
def atualiza_visto(uid):
	servidores_vivos[uid] = time.time()

#varre dicionário e remove quem estourou o tempo:
def confere_timeouts(limite=3.0):
	tempo_atual = time.time()

	for uid, ultimo_tempo in list(servidores_vivos.items()):
		if tempo_atual - ultimo_tempo > limite:
			print(f"[ALERTA] Servidor {uid} morreu por timeout!", file=sys.stderr)
			del servidores_vivos[uid] #remove da lista


#----------------------------------------------------------------------------------------------------------#
#thread responsável pelo heartbeat:
def background():
	while True:
		time.sleep(1) #envia a cada 1 segundo

		atualiza_visto(MEU_ID)

		mensagem = f'Estou vivo e sou {MEU_ID}'.encode()
		confere_timeouts()
		sock.sendto(mensagem, MULTICAST_ADDRESS)

		lider_atual = elege_lider()
		print(f"[ELEIÇÃO] Líder atual do grupo: {lider_atual}", file=sys.stderr)

#----------------------------------------------------------------------------------------------------------#
#thread responsável por escutar a rede continuamente:
def foreground():
	while True:
		data, address = sock.recvfrom(1024)
		mensagem = data.decode()
		print(f'Recebido de {address}: {mensagem}', file=sys.stderr)

		#tratando mensagens de heartbeat:
		if "Estou vivo e sou" in mensagem:
			uid_remetente = int(mensagem.split()[-1])

			atualiza_visto(uid_remetente)

			print(f"[ESTADO] Vivos atuais: {servidores_vivos}", file=sys.stderr)

		#TRATAR AQUI DPS SE É UM ALIVE, UM SYNC de xadrez ou sla.


#----------------------------------------------------------------------------------------------------------#
#MAIN:
#cria o socket udp:
sock  =  socket.socket (socket.AF_INET,socket.SOCK_DGRAM)

#IMPORTANTE DEMAIS: permite rodar múltiplos servidores na mesma máquina
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

#vincula socket ao end e porta de escuta
sock.bind(('', MULTICAST_PORT))

#informa ao SO que queremos entrar no grupo multicast
grupo = socket.inet_aton(MULTICAST_IP)
mreq = struct.pack('4sL', grupo, socket.INADDR_ANY)
sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)

print(f'Servidor UID {MEU_ID} iniciado e aguardando...', file=sys.stderr)

#dispara threads:
b = threading.Thread(name='background_heartbeat', target=background, daemon=True)
f = threading.Thread(name='foreground_listener', target=foreground, daemon=True)

b.start()
f.start()

#mantém a thread principal viva para o programa n encerrar:
try:
	while True:
		time.sleep(0.5)
except KeyboardInterrupt:
	print('Encerrando servidor...', file=sys.stderr)
	sock.close()






