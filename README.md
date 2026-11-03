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

## Dia 3 - Heartbeat e eleição de líder

- `servidor.py`:
	- UID passado como argumento (`python3 servidor.py <UID>`)
	- Socket UDP entrando no grupo multicast `224.3.29.71:10000` (`IP_ADD_MEMBERSHIP`), com `SO_REUSEADDR` para rodar vários servidores na mesma máquina
	- Duas threads:
		- `background`: a cada 1s manda o heartbeat `Estou vivo e sou <UID>` por multicast, remove quem está há mais de 3s sem dar sinal e recalcula o líder
		- `foreground`: escuta a rede e atualiza o dicionário `servidores_vivos` (uid → hora do último heartbeat)
	- Eleição: o menor UID vivo é o líder (cada servidor calcula sozinho, a partir da sua lista de vivos)
- `cliente.py`: cliente de teste que manda uma mensagem para o grupo e espera respostas até dar timeout

## Dia 4 - Xadrez replicado funcionando

- Cliente controla os dois lados por enquanto (depois: lance aleatório ou Stockfish em `lance_adversario()`)
- Mensagens no formato `TIPO|campo1|campo2` (`|` porque o FEN tem espaços):

| Mensagem | Quem → Quem | Formato |
|---|---|---|
| READ | cliente → grupo | `READ` |
| MOVE | cliente → grupo | `MOVE\|e2e4` |
| SYNC | líder → grupo | `SYNC\|seq\|uid_lider\|fen` |
| ACK | réplica → grupo | `ACK\|seq\|uid` |
| STATE | líder → cliente | `STATE\|fen\|situacao` |
| OK | líder → cliente | `OK\|fen\|situacao` |
| ERRO | líder → cliente | `ERRO\|motivo` |

- Mudanças em relação ao Dia 2:
	- MOVE roda numa thread separada, senão o líder travava esperando ACKs que chegam pela própria thread que escuta a rede
	- ACK por multicast (decisão provisória):
		- Deixei o ACK indo por multicast para conseguir testar em localhost: na mesma máquina todos os servidores usam (IP, 10000), então um unicast podia cair no servidor errado
		- Nas máquinas do lab (um servidor por máquina) o unicast funciona. A diferença é só tráfego: no multicast todo servidor recebe todos os ACKs, no unicast só o líder recebe
		- Toninho, se quiser trocar para unicast: no `foreground` passar `address` para `trata_sync(campos, address)` e no fim do `trata_sync` mandar o ACK para `address` em vez de `MULTICAST_ADDRESS` (o `address` do SYNC já é o IP do líder)

## Como rodar


```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

Em terminais separados (cada um com o `source .venv/bin/activate`):

```bash
python3 servidor.py 1
python3 servidor.py 2
python3 servidor.py 3
python3 cliente.py
```

Lances no formato UCI (`e2e4`, `g1f3`...). Para testar a tolerância a falhas: Ctrl+C no líder (menor UID) no meio da partida e esperar ~4s.

## Meu ambiente
- Ambiente onde testei:
	- Testei no pc do trabalho, no WSL, e só em localhost (3 servidores e o cliente tudo na mesma máquina). Funcionou de boa, inclusive derrubando o líder no meio da partida
	- Usei venv porque o pip não deixava instalar o chess direto e no apt não tinha o pacote. Se na tua máquina o `pip install chess` funcionar, nem precisa do venv