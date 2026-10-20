# trabalho-redes2

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
