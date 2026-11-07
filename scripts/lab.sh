#!/usr/bin/env bash
# Ajuda a coletar os logs do laboratório. O passo a passo está em LABORATORIO.md.
#
# Uso:
#   scripts/lab.sh preparar
#   scripts/lab.sh servidor <cenario> <uid> [reinicio]
#   scripts/lab.sh cliente <cenario>
#   scripts/lab.sh conferir
set -u

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ"

CENARIOS=(heartbeat-eleicao xadrez-replicacao lance-invalido falha-lider falha-replica lider-volta)

uso() {
	sed -n '4,8p' "${BASH_SOURCE[0]}" | sed 's/^# *//' >&2
	echo "Cenários: ${CENARIOS[*]}" >&2
	exit 1
}

valida_cenario() {
	local c
	for c in "${CENARIOS[@]}"; do
		[ "$c" = "$1" ] && return 0
	done
	echo "Cenário desconhecido: $1" >&2
	uso
}

python_do_projeto() {
	if [ -x .venv/bin/python ]; then
		echo .venv/bin/python
	else
		echo "Rode antes: scripts/lab.sh preparar" >&2
		exit 1
	fi
}

nome_maquina() {
	local nome
	nome="$(uname -n | cut -d. -f1 | tr -cd 'A-Za-z0-9_-')"
	echo "${nome:-maquina}"
}

#----------------------------------------------------------------------------------------------------------#
preparar() {
	python3 -m venv .venv && .venv/bin/pip install -r requirements.txt || exit 1
	local c
	for c in "${CENARIOS[@]}"; do
		mkdir -p "logs/lab-$c"
	done
	echo
	echo "Máquina: $(nome_maquina)"
	echo "Rota do multicast (precisa ser a interface da rede do laboratório):"
	ip route get 224.3.29.71 2>/dev/null | head -1
}

# tee -i: o Ctrl+C encerra só o programa, e a última linha ainda entra no log
servidor() {
	[ "$#" -ge 2 ] || uso
	valida_cenario "$1"
	case "$2" in ''|*[!0-9]*) echo "UID inválido: $2" >&2; exit 1 ;; esac
	local py sufixo="" log
	py="$(python_do_projeto)"
	if [ "${3:-}" = "reinicio" ]; then
		sufixo="_reinicio"
	elif [ -n "${3:-}" ]; then
		uso
	fi
	mkdir -p "logs/lab-$1"
	log="logs/lab-$1/$(nome_maquina)_uid$2$sufixo.log"
	echo "Gravando em $log (Ctrl+C para encerrar)"
	"$py" servidor.py "$2" 2>&1 | tee -i "$log"
}

cliente() {
	[ "$#" -eq 1 ] || uso
	valida_cenario "$1"
	local py log
	py="$(python_do_projeto)"
	mkdir -p "logs/lab-$1"
	log="logs/lab-$1/$(nome_maquina)_cliente.log"
	echo "Gravando em $log (digite sair para encerrar)"
	"$py" -u cliente.py 2>&1 | tee -i "$log"
}

#----------------------------------------------------------------------------------------------------------#
falhas=0

confere() { # descricao (0 = passou)
	if [ "$2" -eq 0 ]; then
		echo "  ok    $1"
	else
		echo "  FALTA $1"
		falhas=$((falhas + 1))
	fi
}

tem_texto() { # pasta texto
	grep -rqF -- "$2" "$1"
	echo $?
}

tem_arquivo() { # padrao
	compgen -G "$1" >/dev/null
	echo $?
}

# Três máquinas diferentes, nos nomes dos logs dos servidores (ignora os reinícios)
tres_maquinas() { # pasta
	local total
	total="$(find "$1" -maxdepth 1 -name '*_uid*.log' ! -name '*_reinicio.log' -printf '%f\n' 2>/dev/null | sed 's/_uid.*//' | sort -u | wc -l)"
	[ "$total" -ge 3 ]
	echo $?
}

# Cada servidor precisa ter visto os três UIDs numa mesma linha
todos_viram_todos() { # pasta
	local f achou=1
	for f in "$1"/*_uid*.log; do
		[ -e "$f" ] || { echo 1; return; }
		case "$f" in *_reinicio.log) continue ;; esac
		grep -iF 'vivos atuais' "$f" | grep -E '[{ ]1: ' | grep -E '[{ ]2: ' | grep -qE '[{ ]3: ' || { echo 1; return; }
		achou=0
	done
	echo "$achou"
}

sem_erro_python() { # pasta
	if grep -rqF 'Traceback' "$1"; then echo 1; else echo 0; fi
}

conferir() {
	local c pasta
	for c in "${CENARIOS[@]}"; do
		pasta="logs/lab-$c"
		echo "$c"
		if [ -z "$(find "$pasta" -type f -name '*.log' 2>/dev/null | head -1)" ]; then
			confere "nenhum log ainda" 1
			continue
		fi
		confere "servidores em 3 máquinas diferentes" "$(tres_maquinas "$pasta")"
		confere "sem erro do Python nos logs" "$(sem_erro_python "$pasta")"
		case "$c" in
			heartbeat-eleicao)
				confere "cada servidor viu os UIDs 1, 2 e 3" "$(todos_viram_todos "$pasta")"
				confere "líder 1 eleito" "$(tem_texto "$pasta" 'Líder atual do grupo: 1')"
				;;
			xadrez-replicacao)
				confere "líder aplicou lance ([MOVE])" "$(tem_texto "$pasta" '[MOVE]')"
				confere "réplica recebeu tabuleiro ([SYNC])" "$(tem_texto "$pasta" '[SYNC] Tabuleiro atualizado')"
				confere "log do cliente" "$(tem_arquivo "$pasta/*_cliente.log")"
				;;
			lance-invalido)
				confere "lance recusado" "$(tem_texto "$pasta" 'Lance inválido')"
				confere "log do cliente" "$(tem_arquivo "$pasta/*_cliente.log")"
				;;
			falha-lider)
				confere "queda detectada" "$(tem_texto "$pasta" 'Servidor 1 morreu por timeout')"
				confere "UID 2 assumiu" "$(tem_texto "$pasta" 'Líder atual do grupo: 2')"
				confere "lance aceito pelo novo líder" "$(tem_texto "$pasta" 'esperando ACK de [3]')"
				;;
			falha-replica)
				confere "aviso de ACK faltando" "$(tem_texto "$pasta" 'Sem ACK de')"
				;;
			lider-volta)
				confere "servidor reiniciado gravado" "$(tem_arquivo "$pasta/*_reinicio.log")"
				confere "UID 2 enviou o tabuleiro" "$(tem_texto "$pasta" '[JOIN] Servidor 1 entrou')"
				if grep -rqF 'Lance inválido' "$pasta"; then
					confere "nenhum lance recusado depois da volta" 1
				else
					confere "nenhum lance recusado depois da volta" 0
				fi
				;;
		esac
	done
	echo
	if [ "$falhas" -eq 0 ]; then
		echo "Tudo certo. Agora rode scripts/gerar_site.sh."
	else
		echo "Faltam $falhas item(ns). Refaça só os cenários marcados com FALTA."
		return 1
	fi
}

#----------------------------------------------------------------------------------------------------------#
[ "$#" -ge 1 ] || uso
comando="$1"
shift
case "$comando" in
	preparar) preparar ;;
	servidor) servidor "$@" ;;
	cliente) cliente "$@" ;;
	conferir) conferir ;;
	*) uso ;;
esac
