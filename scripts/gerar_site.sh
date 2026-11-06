#!/usr/bin/env bash
# Atualiza os arquivos gerados do site em docs/:
#   - docs/codigo/  cópia .txt do código-fonte (*.py e requirements*.txt)
#   - docs/logs/    cópia dos logs de logs/<cenario>/ (*.log e *.txt)
#   - docs/partidas/  cópia das saídas de partidas/<partida>/ (*.log e *.txt)
#   - docs/diario/  cópia do diário de diario/ (*.pdf, *.zip e *.tex como .tex.txt)
#   - listas das páginas HTML, entre os marcadores <!-- GERADO:nome:INICIO/FIM -->
#
# As duas pastas são recriadas do zero a cada execução. Os cenários são os
# marcadores GERADO:log-<cenario> de docs/logs.html e GERADO:partida-<partida> de docs/partidas.html;
# arquivos fora deles não são publicados.
set -euo pipefail
export LC_ALL=C

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ"

PAGINAS=(docs/index.html docs/relatorio.html docs/diario.html docs/partidas.html docs/logs.html docs/codigo.html)
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

rm -rf docs/codigo docs/logs docs/partidas docs/diario
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
	printf '<li>Nenhum arquivo de código encontrado.</li>\n' > "$frag_codigo"
	aviso "nenhum arquivo de código encontrado"
fi

#----------------------------------------------------------------------------------------------------------#
# Logs e partidas: um fragmento por item declarado na página
processa_itens() { # pagina prefixo origem texto_vazio
	local pagina="$1" prefixo="$2" origem="$3" vazio="$4"
	local itens=() item frag lista total caminho arquivo relativo conhecido
	while IFS= read -r item; do
		itens+=("$item")
	done < <(grep -o "GERADO:$prefixo-[a-z0-9-]*:INICIO" "$pagina" | sed -e "s/^GERADO:$prefixo-//" -e 's/:INICIO$//')

	for item in "${itens[@]}"; do
		frag="$TMP/$prefixo-$item"
		lista="$TMP/lista-$prefixo-$item"
		: > "$lista"
		total=0

		if [ -d "$origem/$item" ]; then
			while IFS= read -r -d '' caminho; do
				arquivo="${caminho#"$origem"/"$item"/}"
				if ! nome_seguro "$arquivo"; then
					aviso "ignorado (nome com caracteres não aceitos): $caminho"
					continue
				fi
				case "$arquivo" in
					*.log|*.txt) ;;
					*) aviso "ignorado (extensão diferente de .log/.txt): $caminho"; continue ;;
				esac
				if ! eh_texto "$caminho"; then
					aviso "ignorado (vazio ou binário): $caminho"
					continue
				fi
				mkdir -p "docs/$origem/$item/$(dirname "$arquivo")"
				copia_utf8 "$caminho" "docs/$origem/$item/$arquivo"
				printf '<li><a href="%s/%s/%s" data-visualizar>%s</a> <span class="meta">(%s linhas)</span></li>\n' \
					"$origem" "$item" "$arquivo" "$arquivo" "$(conta_linhas "$caminho")" >> "$lista"
				total=$((total + 1))
			done < <(find "$origem/$item" -type f -print0 | sort -z)
		fi

		if [ "$total" -eq 0 ]; then
			printf '<p>%s</p>\n' "$vazio" > "$frag"
			faltando=$((faltando + 1))
		else
			{
				printf '<ul class="arquivos" data-visualizador>\n'
				cat "$lista"
				printf '</ul>\n'
			} > "$frag"
		fi
	done
	total_itens=$((total_itens + ${#itens[@]}))

	# Tudo na origem que não pertence a um item declarado fica de fora e gera aviso
	if [ -d "$origem" ]; then
		while IFS= read -r -d '' caminho; do
			relativo="${caminho#"$origem"/}"
			conhecido=0
			for item in "${itens[@]}"; do
				case "$relativo" in "$item"/*) conhecido=1 ;; esac
			done
			[ "$conhecido" -eq 1 ] || aviso "fora de um item declarado, não publicado: $caminho"
		done < <(find "$origem" -type f -print0 | sort -z)
	fi
}

faltando=0
total_itens=0
processa_itens docs/logs.html log logs "Log ainda não disponível."
processa_itens docs/partidas.html partida partidas "Saída ainda não disponível."

#----------------------------------------------------------------------------------------------------------#
# Diário: só o PDF, o zip e o fonte LaTeX; os arquivos auxiliares da compilação ficam de fora
lista_diario="$TMP/lista-diario"
: > "$lista_diario"
total_diario=0

if [ -d diario ]; then
	while IFS= read -r -d '' caminho; do
		arquivo="${caminho#diario/}"
		if ! nome_seguro "$arquivo"; then
			aviso "diário ignorado (nome com caracteres não aceitos): $caminho"
			continue
		fi
		case "$arquivo" in
			*.pdf)
				if [ "$(head -c 4 "$caminho")" != "%PDF" ]; then
					aviso "diário ignorado (não é um PDF válido): $caminho"
					continue
				fi
				mkdir -p "docs/diario/$(dirname "$arquivo")"
				cp "$caminho" "docs/diario/$arquivo"
				printf '<li><a href="diario/%s">%s</a></li>\n' "$arquivo" "$arquivo" >> "$lista_diario"
				;;
			*.zip)
				if [ "$(head -c 2 "$caminho")" != "PK" ]; then
					aviso "diário ignorado (não é um zip válido): $caminho"
					continue
				fi
				mkdir -p "docs/diario/$(dirname "$arquivo")"
				cp "$caminho" "docs/diario/$arquivo"
				printf '<li><a href="diario/%s">%s</a></li>\n' "$arquivo" "$arquivo" >> "$lista_diario"
				;;
			*.tex)
				if ! eh_texto "$caminho"; then
					aviso "diário ignorado (vazio ou binário): $caminho"
					continue
				fi
				mkdir -p "docs/diario/$(dirname "$arquivo")"
				copia_utf8 "$caminho" "docs/diario/$arquivo.txt"
				printf '<li><a href="diario/%s.txt" data-visualizar>%s</a> <span class="meta">(%s linhas)</span></li>\n' \
					"$arquivo" "$arquivo" "$(conta_linhas "$caminho")" >> "$lista_diario"
				;;
		esac
		total_diario=$((total_diario + 1))
	done < <(find diario -type f \( -name '*.pdf' -o -name '*.zip' -o -name '*.tex' \) -print0 | sort -z)
fi

if [ -f docs/diario/diario.pdf ]; then
	cat > "$TMP/diario-render" <<'HTML'
<p><a href="diario/diario.pdf">Abrir o diário em outra aba</a></p>
<object class="pdf" data="diario/diario.pdf#navpanes=0&view=FitH" type="application/pdf" aria-label="Diário de desenvolvimento em PDF">
<p>Este navegador não mostra o PDF na página. <a href="diario/diario.pdf">Abra o diário por este link.</a></p>
</object>
HTML
else
	printf '<!-- diario/diario.pdf ainda não existe -->\n' > "$TMP/diario-render"
fi

if [ -s "$lista_diario" ]; then
	{
		printf '<ul class="arquivos" data-visualizador>\n'
		cat "$lista_diario"
		printf '</ul>\n'
	} > "$TMP/diario-arquivos"
else
	printf '<p>O PDF e o LaTeX do diário ainda não foram adicionados.</p>\n' > "$TMP/diario-arquivos"
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
echo "Logs e partidas: $((total_itens - faltando)) de $total_itens com arquivos em docs/logs/ e docs/partidas/"
echo "Diário: $total_diario arquivo(s) em docs/diario/"
[ "$avisos" -eq 0 ] || echo "Avisos: $avisos" >&2
