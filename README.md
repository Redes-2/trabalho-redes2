# trabalho-redes2

Trabalho de Redes 2 desenvolvido por Antonio da Ressurreição Filho e Nathan Endo: um grupo de servidores com heartbeat por multicast UDP, eleição pelo menor UID e um serviço de xadrez replicado.

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

## Dia 5 - Testes em três máquinas

- Até aqui só tínhamos testado em localhost. Agora rodamos o grupo em três computadores da mesma rede local:
	- Desktop com o UID 1, servidor com o UID 2 e notebook com o UID 3
	- Cliente rodando no notebook
	- Logs em `logs/`, separados por cenário, e partidas em `partidas/`
- Primeiro problema: as máquinas não se enxergavam direito
	- O notebook não recebia ninguém e se elegia líder sozinho, com UID 3
	- O desktop parecia certo, mas só porque tem o menor UID: ele também estava sozinho. Só vimos isso olhando que não aparecia nenhum `Recebido de` no log dele
	- No desktop o bloqueio era o firewall, e liberar o UDP da rede local resolveu
	- Lição: não dá para olhar só o líder, tem que conferir o `[ESTADO] Vivos atuais` em cada máquina
- Cenários que testamos:

| Cenário | O que fizemos | Resultado |
|---|---|---|
| Heartbeat e eleição | Subimos os três servidores | Todos receberam os três heartbeats e elegeram o UID 1 |
| Lances e replicação | Jogamos `e2e4`, `e7e5` e `g1f3` | O líder aplicou e as duas réplicas receberam, de seq 1 a 3 |
| Lance inválido | Mandamos `e2e5` e `abc` | Os dois recusados, sem mudar o tabuleiro |
| Queda do líder | Derrubamos o desktop no meio da partida | O UID 2 assumiu e aceitou `g1f3` no mesmo tabuleiro |
| Queda de réplica | Derrubamos o UID 2 e logo mandamos `e7e5` | O líder avisou `Sem ACK de [2]` e respondeu OK mesmo assim |
| Líder que volta | O desktop caiu e voltou no meio da partida | Primeiro falhou, depois da correção funcionou |

- Erro que os testes mostraram: o líder que voltava zerava a partida
	- Quando o UID 1 voltou, virou líder de novo por ter o menor UID, só que com o tabuleiro inicial
	- O cliente mandou `b8c6`, levou `Lance inválido` e o tabuleiro voltou para o começo
	- A primeira ideia foi mandar um SYNC quando o líder mudasse, mas até ele chegar o servidor já se acharia líder
	- O que fizemos: quem sobe manda `JOIN|uid` e só pode ser líder depois de receber o tabuleiro. Responde quem é o líder sem contar com ele (`elege_lider(ignorar=uid)`). Se ninguém responder em 3s, é porque não tem partida em andamento
	- Testamos de novo: o UID 1 recebeu `seq=3` do líder 2, assumiu e aceitou `b8c6` no tabuleiro certo. Uma réplica reiniciada também recebeu o tabuleiro
	- Depois da correção, refizemos todos os cenários. Só o log `reentrada-lider-antes` é da versão antiga
	- Efeito colateral: subindo todos juntos, o grupo leva 3s para começar a responder
- Partidas que jogamos para ver as situações de jogo:
	- Mate do pastor: `Xeque-mate! Brancas venceram`
	- Mate do tolo: `Xeque-mate! Pretas venceram`
	- Afogamento: `Empate por afogamento (stalemate)`
	- Lances especiais: en passant, roque e promoção foram aceitos, e a promoção deu `Xeque! Vez das pretas`
	- Repetição: o líder anunciou `Fim de jogo: 1/2-1/2`, mas o cliente continuou pedindo lance, porque o FEN não guarda o histórico de repetições

## Dia 6 - Testes no laboratório

- Sexta à noite no laboratório 3 do DINF, com 10 máquinas: 9 servidores e 1 cliente
- Em cada máquina: uma conta do DINF, o repositório clonado, um venv e o `chess` instalado
- Antes dos testes, mudamos as mensagens do log do `servidor.py`:
	- `[HEARTBEAT]` e `[TABULEIRO]` separados, para achar as mensagens de xadrez no meio dos heartbeats
	- O `[ESTADO]` agora diz qual servidor está falando: `Eu sou o servidor N e meus vivos atuais são...`
- Teste 1, servidores subindo em ordem crescente:
	- Os UIDs 1 a 9 entraram um por um. Cada um mandou `JOIN`, e o líder 1 respondeu com o tabuleiro
	- Seis lances (seq 1 a 6), sempre esperando o ACK das 8 réplicas, sem nenhum `Sem ACK`
	- O log era do servidor 1, então parou quando ele foi encerrado
- Teste 2, entradas fora de ordem e duas quedas:
	- Ordem de entrada: 5, 3, 1 e 7. A liderança foi de 5 para 3 e depois para 1, porque cada um que entrava tinha UID menor
	- Derrubamos o 1 e o 3 assumiu. Depois derrubamos o 3 e o 5 assumiu
	- A partida não se perdeu: o seq foi de 1 a 4 com o líder 1, 5 e 6 com o 3, e 7 e 8 com o 5
	- Desta vez o log foi gravado no servidor 5, que ficou até o fim
- Os dois testes levaram mais de duas horas
- Logs em `logs/lab-entrada-1-a-9/` e `logs/lab-entrada-5-3-1-7/`

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