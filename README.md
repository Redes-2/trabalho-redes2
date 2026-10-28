# trabalho-redes2

## Dia 1

- Usar o serviço de chess do python: pythonchess
- UID do servidor dado no argumento do comando run do servidor.
- Pré computar a divisão de grupos e colocar os membros de cada grupo nas tabelas individuais de cada servidor.
- Interessante: várias formas de divisão de grupos.
	- Primeira divisão: mod alternado.
	- Segunda divisão: bloco.
	- Terceira divisão: random*

- Como atualizar tabuleiro dos outros grupos?
	- O líder faz multicast para todas as máquinas fora do próprio grupo
	- Cada grupo é um serviço?

- Como randomizar os grupos?
	- Mesma seed?
	- Mock de uma randomização pré-feita

## Dia 2 - Redefinição de Arquitetura e Escopo

- Arquitetura de grupo único
	- Decisão: A especificação exige um único grupo de servidores que trabalham em conjunto para manter a mesma aplicação no ar
	- Motivo: O objetivo não é criar um lobby de xadrez, mas sim a tolerância de falhas com heartbeat
- Comunicação e Sockets
	- Uso exclusivo de Sockets `UDP` com multicast IP/Ethernet (ex IP: 224.0.0.1)
	- Infraestrutura: Os testes finais para geração de Logs serão feitos nas máquinas do dinf/c3sl ? -> Isso é uma pergunta Toninho, atualize ai se sim.

- Tolerância de Falhas
	- Heartbeat: Cada servidor tem uma thread separada enviando uma mensagem `ALIVE <UID>` via multicast a cada X segundos
	- Detecção de Falhas: Se um servidor parar de mandar o heartbeat, os outros dão `timeout` e o `removem` da lista interna de ativos.
	- Eleição: O servidor vivo com o `menor UID` se reconhece automaticamente como o líder
- O serviço de xadrez
	- Só leitura (consulta): O cliente envia `READ` no multicast. O líder responde diretamente o cliente com o tabuleiro atual.
	- Escrita (movimento): 
		- Cliente manda o movimento via multicast (ex: `MOVE` e2e4)
		- Líder aplica o movimento no python-chess + faz movimento de resposta da máquina (ou podemos também fazer de controlar os dois lados do tabuleiro).
		- Líder gera string `FEN` e envia `SYNC <FEN>` (multicast).
		- Réplicas atualizam o estado local e mandam `ACK` manual para o líder (unicast)
		- Líder recebe as confirmações e devolve OK para o cliente

- Fluxo
	- Cliente primeiramente consulta (Inicia tabuleira)
	- Cliente manda movimento
	- Servidor manda OK
	- Após o Cliente receber o OK, consulta o tabuleiro
	- OBS: precisamps mandar "textinhos" sobre a situação se houve checkmate, stalemate e etc.

- Observações
    - FEN é o jeito oficial do python-chess exportar o tabuleiro (serializa tudo em uma string com menos de 100 caracteres).
    - Tamanho do Payload: Como o FEN é muito menor que o MTU da rede (~1500 bytes), não corremos nenhum risco de fragmentação de pacotes no UDP durante o SYNC.
    - O UDP não garante entrega: Por isso, o mecanismo de ACK na operação de escrita tem que ser feito manualmente na nossa camada de aplicação (Two-Phase Commit simplificado).
    - Prevenção de Deadlocks: Ao aguardar os ACKs das réplicas, o líder precisa obrigatoriamente usar um `timeout`. Se uma réplica morrer uma fração de segundo após receber o SYNC, o líder não pode ficar travado em um loop infinito esperando ela confirmar.
    - Multicast vs Broadcast (C3SL): Usar Multicast (Classe D) ativa o IGMP Snooping nos switches do laboratório. O tráfego só vai para as portas dos nossos nós, evitando o "broadcast storm" que aconteceria se usássemos IPs com final .255.
    - Testes Locais (Localhost): Para conseguir rodar mais de um servidor na mesma máquina durante o desenvolvimento, é obrigatório setar as flags `SO_REUSEADDR` (e possivelmente `SO_REUSEPORT`) na criação do socket, senão o SO bloqueia a porta.
	- Esses dois pontos de cima eu perguntei pro gemini, é bom a gnt dar uma estudada nisso, o resto eu folheei a documentação do python-chess e os tipos de mensagem a gnt faz um ENUM só.