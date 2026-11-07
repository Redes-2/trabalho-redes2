# Dia 6 - Testes no laboratório

Passo a passo para rodar os testes nas máquinas do laboratório e colocar os logs no site.

## O que precisa

- Três máquinas na mesma rede do laboratório, com um servidor em cada uma
- Um terminal a mais em uma delas para o cliente

Use os UIDs 1, 2 e 3, um em cada máquina. Se quiser, troque as máquinas, mas mantenha os UIDs nos comandos.

## 1. Preparar

Faça uma vez em cada máquina. Se as máquinas compartilharem a mesma pasta de usuário, basta fazer em uma delas.

```bash
git clone git@github.com:Redes-2/trabalho-redes2.git
cd trabalho-redes2
git switch dia-6-laboratorio
scripts/lab.sh preparar
```

O final da saída mostra a interface usada pelo multicast. Ela precisa ser a da rede do laboratório.

## 2. Testar a rede

Antes de gerar os logs, veja se as máquinas se enxergam.

```bash
scripts/lab.sh servidor heartbeat-eleicao 1   # máquina 1
scripts/lab.sh servidor heartbeat-eleicao 2   # máquina 2
scripts/lab.sh servidor heartbeat-eleicao 3   # máquina 3
```

Depois de uns 5 segundos, **as três máquinas** precisam mostrar a linha `[ESTADO]` (`Eu sou o servidor N e meus vivos atuais são...`) com os UIDs 1, 2 e 3, e `Líder atual do grupo: 1`.

Olhar só o líder engana: um servidor sozinho com o UID 1 também se declara líder. Se alguma máquina mostrar só o próprio UID, o multicast está bloqueado. Nesse caso, veja com o professor ou com quem cuida do laboratório.

## 3. Rodar os cenários

Em todos os cenários:

1. Suba os três servidores com o nome do cenário e espere uns 5 segundos.
2. Quando o cenário usar cliente, abra-o em outro terminal.
3. No fim, encerre o cliente com `sair` e os servidores com Ctrl+C.

Se errar, é só repetir: o log do cenário é sobrescrito.

```bash
scripts/lab.sh servidor NOME_DO_CENARIO 1   # máquina 1
scripts/lab.sh servidor NOME_DO_CENARIO 2   # máquina 2
scripts/lab.sh servidor NOME_DO_CENARIO 3   # máquina 3
scripts/lab.sh cliente NOME_DO_CENARIO      # outro terminal da máquina 3
```

### `heartbeat-eleicao`
Sem cliente. Espere uns 15 segundos e encerre.

### `xadrez-replicacao`
Jogue `e2e4`, `e7e5` e `g1f3`.

### `lance-invalido`
Digite `e2e5` (ilegal), `abc` (malformado) e `e2e4` (válido).

### `falha-lider`
1. Jogue `e2e4` e `e7e5`.
2. Dê Ctrl+C no servidor da máquina 1, o líder.
3. Espere 5 segundos. As outras máquinas devem mostrar `Servidor 1 morreu por timeout` e `Líder atual do grupo: 2`.
4. Jogue `g1f3`. O tabuleiro deve continuar de onde estava.

### `falha-replica`
Este depende de tempo: o lance precisa sair menos de 3 segundos depois da queda.

1. Jogue `e2e4`.
2. Digite `e7e5`, mas **não aperte Enter**.
3. Dê Ctrl+C no servidor da máquina 2.
4. Aperte Enter no cliente logo em seguida.
5. A máquina 1 deve mostrar `Sem ACK de [2]`. Se não mostrar, repita mais rápido.

### `lider-volta`
1. Jogue `e2e4` e `e7e5`.
2. Dê Ctrl+C no servidor da máquina 1.
3. Espere 6 segundos e jogue `g1f3`.
4. Suba o servidor de novo na máquina 1:

   ```bash
   scripts/lab.sh servidor lider-volta 1 reinicio
   ```

5. Espere 5 segundos e jogue `b8c6`. O lance deve ser aceito, com o tabuleiro mantido.

## 4. Juntar os logs

Se as máquinas compartilham a pasta de usuário, os logs já estão no mesmo lugar. Se não, em cada máquina:

```bash
git add logs/lab-*
git commit -m "Adiciona logs do laboratorio"
git pull --rebase
git push
```

Se uma máquina não puder usar o Git, copie os arquivos dela com `scp` para a pasta `logs/lab-<cenario>/` da máquina onde você vai terminar.

## 5. Conferir e colocar no site

Com todos os logs juntos:

```bash
scripts/lab.sh conferir
scripts/gerar_site.sh
```

O `conferir` procura as mensagens esperadas e aponta o que falta. Ele não substitui ler os logs. O `gerar_site.sh` coloca os arquivos na seção "Testes no laboratório" da página de Logs. Para ver o resultado:

```bash
python3 -m http.server 8000 --directory docs
```

Depois abra `http://localhost:8000/logs.html`.

## 6. Escrever o dia 6

Escreva só o que aconteceu de verdade nos testes. Nestes arquivos:

- **`README.md`:** adicione `## Dia 6` antes de `## Como rodar`.
- **`docs/relatorio.html`** (página Relatório): repita o texto nas notas, depois do Dia 5.
- **`docs/logs.html`:** troque os textos da seção "Testes no laboratório" pelo que aconteceu.
- **`docs/secao-tecnica.html`** (página Seção técnica): em "8. Testes", inclua as máquinas usadas e os resultados.
- **LaTeX:** adicione `dia6.tex`, inclua `\input{dia6}` no `main.tex`, compile e troque `diario/relatorio.pdf` e `diario/latex.zip`. Rode `scripts/gerar_site.sh` de novo.

Para ajudar, responda estas perguntas no texto:

- Quais máquinas foram usadas?
- Precisou fazer algo diferente do que fizemos em casa, como liberar firewall?
- Algum cenário falhou? O que aconteceu e o que foi feito?
- O ACK continuou em multicast, ou vocês testaram unicast?

Antes de enviar, confira os logs e tire dados que não devem ficar públicos, como senhas e usuários.

## 7. Enviar

```bash
git add -A
git status
git commit -m "Adiciona testes do laboratorio"
git push
```

Confira o `git status` antes do commit. Depois, abra um PR de `dia-6-laboratorio` para `main`.
