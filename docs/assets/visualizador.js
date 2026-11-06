// Mostra na própria página os arquivos das listas marcadas com data-visualizador.
// Sem JavaScript, ou se o fetch falhar, os links continuam abrindo os arquivos.
(function () {
	"use strict";

	function criarVisor(lista) {
		var visor = document.createElement("section");
		visor.hidden = true;
		visor.setAttribute("aria-live", "polite");

		var titulo = document.createElement("p");
		titulo.className = "visor-titulo";

		var pre = document.createElement("pre");
		pre.tabIndex = 0;
		var codigo = document.createElement("code");
		pre.appendChild(codigo);

		visor.appendChild(titulo);
		visor.appendChild(pre);
		lista.insertAdjacentElement("afterend", visor);

		return { raiz: visor, titulo: titulo, pre: pre, codigo: codigo, pedido: 0, botao: null };
	}

	function mostrarTitulo(visor, link, mensagem, ehErro) {
		var abrir = document.createElement("a");
		abrir.href = link.getAttribute("href");
		abrir.textContent = "abrir o arquivo";

		visor.titulo.textContent = "";
		visor.titulo.classList.toggle("visor-erro", ehErro);
		visor.titulo.appendChild(document.createTextNode(mensagem + " ("));
		visor.titulo.appendChild(abrir);
		visor.titulo.appendChild(document.createTextNode(")"));
	}

	function carregar(visor, link, botao) {
		var nome = link.textContent;
		var pedido = ++visor.pedido;

		if (visor.botao) {
			visor.botao.setAttribute("aria-pressed", "false");
		}
		visor.botao = botao;
		botao.setAttribute("aria-pressed", "true");

		visor.raiz.hidden = false;
		visor.pre.hidden = true;
		mostrarTitulo(visor, link, "Carregando " + nome + "…", false);

		fetch(link.getAttribute("href"))
			.then(function (resposta) {
				if (!resposta.ok) {
					throw new Error("HTTP " + resposta.status);
				}
				return resposta.text();
			})
			.then(function (texto) {
				if (pedido !== visor.pedido) {
					return;
				}
				// textContent: o conteúdo do arquivo nunca é interpretado como HTML
				visor.codigo.textContent = texto;
				visor.pre.hidden = false;
				mostrarTitulo(visor, link, nome, false);
			})
			.catch(function () {
				if (pedido !== visor.pedido) {
					return;
				}
				mostrarTitulo(visor, link, "Não foi possível exibir " + nome + " aqui. Use o link direto", true);
			});
	}

	document.querySelectorAll("[data-visualizador]").forEach(function (lista) {
		var visor = criarVisor(lista);
		var primeiro = null;

		lista.querySelectorAll("a[data-visualizar]").forEach(function (link) {
			var botao = document.createElement("button");
			botao.type = "button";
			botao.textContent = "Ver aqui";
			botao.setAttribute("aria-pressed", "false");
			botao.setAttribute("aria-label", "Ver " + link.textContent + " nesta página");
			botao.addEventListener("click", function () {
				carregar(visor, link, botao);
			});
			link.parentNode.appendChild(botao);
			primeiro = primeiro || { link: link, botao: botao };
		});

		if (primeiro && lista.hasAttribute("data-abrir-primeiro")) {
			carregar(visor, primeiro.link, primeiro.botao);
		}
	});
})();
