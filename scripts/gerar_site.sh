#!/usr/bin/env bash
# Atualiza os arquivos gerados do site em docs/:
#   - docs/codigo/  cópia .txt do código-fonte (*.py e requirements*.txt)
#   - docs/logs/    cópia dos logs de logs/<cenario>/ (*.log e *.txt)
#   - listas das páginas HTML, entre os marcadores <!-- GERADO:nome:INICIO/FIM -->
#
# As duas pastas são recriadas do zero a cada execução. Os cenários são os
# marcadores GERADO:log-<cenario> de docs/logs.html; arquivos fora deles não são publicados.
set -euo pipefail
export LC_ALL=C

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ"

PAGINAS=(docs/index.html docs/relatorio.html docs/logs.html docs/codigo.html)
for pagina in "${PAGINAS[@]}"; do
	[ -f "$pagina" ] || { echo "Erro: $pagina não encontrada" >&2; exit 1; }
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

avisos=0
aviso() {
	echo "AVISO: $*" >&2
	avisos=$((avisos + 1))
}

# Só aceita nomes que dispensam escape em HTML e URL; ocultos (.env etc.) ficam de fora.
nome_seguro() {
	[[ "$1" =~ ^[A-Za-z0-9_-][A-Za-z0-9._-]*(/[A-Za-z0-9_-][A-Za-z0-9._-]*)*$ ]]
}

eh_texto() {
	grep -Iq . "$1"
}

# Com o BOM, o navegador lê o .txt como UTF-8 mesmo se o servidor não informar o charset
copia_utf8() {
	if [ "$(head -c 3 "$1" | od -An -tx1 | tr -d ' ')" = "efbbbf" ]; then
		cp "$1" "$2"
	else
		{ printf '\xEF\xBB\xBF'; cat "$1"; } > "$2"
	fi
}

conta_linhas() {
	awk 'END { print NR }' "$1"
}

rm -rf docs/codigo docs/logs
mkdir -p docs/codigo docs/logs
: > docs/logs/.gitkeep

#----------------------------------------------------------------------------------------------------------#
# Código-fonte: arquivos versionados ou novos, respeitando o .gitignore
frag_codigo="$TMP/codigo-arquivos"
: > "$frag_codigo"
total_codigo=0

while IFS= read -r -d '' arquivo; do
	case "$arquivo" in
		docs/*|venv/*|.venv/*|*/__pycache__/*) continue ;;
	esac
	[ -f "$arquivo" ] && [ ! -L "$arquivo" ] || continue
	if ! nome_seguro "$arquivo"; then
		aviso "código ignorado (nome com caracteres não aceitos): $arquivo"
		continue
	fi
	if ! eh_texto "$arquivo"; then
		aviso "código ignorado (vazio ou binário): $arquivo"
		continue
	fi
	mkdir -p "docs/codigo/$(dirname "$arquivo")"
	copia_utf8 "$arquivo" "docs/codigo/$arquivo.txt"
	printf '<li><a href="codigo/%s.txt" data-visualizar>%s</a> <span class="meta">(%s linhas)</span></li>\n' \
		"$arquivo" "$arquivo" "$(conta_linhas "$arquivo")" >> "$frag_codigo"
	total_codigo=$((total_codigo + 1))
done < <(git ls-files --cached --others --exclude-standard -z -- '*.py' 'requirements*.txt' | sort -z)

if [ "$total_codigo" -eq 0 ]; then
	printf '<li class="todo">TODO: nenhum arquivo de código encontrado.</li>\n' > "$frag_codigo"
	aviso "nenhum arquivo de código encontrado"
fi

#----------------------------------------------------------------------------------------------------------#
# Logs: um fragmento por cenário declarado em docs/logs.html
cenarios=()
while IFS= read -r cenario; do
	cenarios+=("$cenario")
done < <(grep -o 'GERADO:log-[a-z0-9-]*:INICIO' docs/logs.html | sed -e 's/^GERADO:log-//' -e 's/:INICIO$//')

faltando=0
for cenario in "${cenarios[@]}"; do
	frag="$TMP/log-$cenario"
	lista="$TMP/lista-$cenario"
	: > "$lista"
	total=0

	if [ -d "logs/$cenario" ]; then
		while IFS= read -r -d '' caminho; do
			arquivo="${caminho#logs/"$cenario"/}"
			if ! nome_seguro "$arquivo"; then
				aviso "log ignorado (nome com caracteres não aceitos): $caminho"
				continue
			fi
			case "$arquivo" in
				*.log|*.txt) ;;
				*) aviso "log ignorado (extensão diferente de .log/.txt): $caminho"; continue ;;
			esac
			if ! eh_texto "$caminho"; then
				aviso "log ignorado (vazio ou binário): $caminho"
				continue
			fi
			mkdir -p "docs/logs/$cenario/$(dirname "$arquivo")"
			copia_utf8 "$caminho" "docs/logs/$cenario/$arquivo"
			printf '<li><a href="logs/%s/%s" data-visualizar>%s</a> <span class="meta">(%s linhas)</span></li>\n' \
				"$cenario" "$arquivo" "$arquivo" "$(conta_linhas "$caminho")" >> "$lista"
			total=$((total + 1))
		done < <(find "logs/$cenario" -type f -print0 | sort -z)
	fi

	if [ "$total" -eq 0 ]; then
		printf '<p class="todo">TODO: log ainda não coletado. Salve os arquivos em <code>logs/%s/</code> e execute <code>scripts/gerar_site.sh</code>.</p>\n' \
			"$cenario" > "$frag"
		faltando=$((faltando + 1))
	else
		{
			printf '<ul class="arquivos" data-visualizador>\n'
			cat "$lista"
			printf '</ul>\n'
		} > "$frag"
	fi
done

# Tudo em logs/ que não pertence a um cenário declarado fica de fora e gera aviso
if [ -d logs ]; then
	while IFS= read -r -d '' caminho; do
		relativo="${caminho#logs/}"
		conhecido=0
		for cenario in "${cenarios[@]}"; do
			case "$relativo" in "$cenario"/*) conhecido=1 ;; esac
		done
		[ "$conhecido" -eq 1 ] || aviso "fora de um cenário declarado, não publicado: $caminho"
	done < <(find logs -type f -print0 | sort -z)
fi

if [ "$faltando" -eq 0 ]; then
	printf '<p>Há logs nos %s cenários. Veja a <a href="logs.html">página de logs</a>.</p>\n' \
		"${#cenarios[@]}" > "$TMP/status-logs"
else
	printf '<p class="todo">TODO: faltam logs de %s dos %s cenários. Veja a <a href="logs.html">página de logs</a>.</p>\n' \
		"$faltando" "${#cenarios[@]}" > "$TMP/status-logs"
fi

#----------------------------------------------------------------------------------------------------------#
# Reescreve o conteúdo entre cada par de marcadores das páginas
for pagina in "${PAGINAS[@]}"; do
	awk -v dir="$TMP" -v pagina="$pagina" '
		fim != "" {
			if (index($0, fim)) { print; fim = "" }
			next
		}
		match($0, /<!-- GERADO:[a-z0-9-]+:INICIO -->/) {
			nome = substr($0, RSTART + 12, RLENGTH - 12 - 11)
			arquivo = dir "/" nome
			if ((getline linha < arquivo) <= 0) {
				print "Erro: marcador sem conteúdo em " pagina ": " nome > "/dev/stderr"
				erro = 1
				exit 1
			}
			print
			do { print linha } while ((getline linha < arquivo) > 0)
			close(arquivo)
			fim = "<!-- GERADO:" nome ":FIM -->"
			next
		}
		{ print }
		END {
			if (erro) exit 1
			if (fim != "") {
				print "Erro: falta o marcador " fim " em " pagina > "/dev/stderr"
				exit 1
			}
		}
	' "$pagina" > "$TMP/pagina"
	cat "$TMP/pagina" > "$pagina"
done

echo "Código: $total_codigo arquivo(s) em docs/codigo/"
echo "Logs: $((${#cenarios[@]} - faltando)) de ${#cenarios[@]} cenário(s) com arquivos em docs/logs/"
[ "$avisos" -eq 0 ] || echo "Avisos: $avisos" >&2
