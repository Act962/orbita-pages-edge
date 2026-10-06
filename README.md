# orbita-pages-edge

Portaria dos **domínios próprios** do ÓRBITA Pages. É um Caddy que fica na frente só dos
domínios de clientes (`www.cliente.com`), cuida do HTTPS de cada um e repassa ao app apenas
o que um site publicado precisa.

A página **não** é desenhada aqui: quem monta o HTML é o app (`nasa.ex`), com o mesmo código
do editor. Este repositório não tem banco, não tem sessão e não conhece nenhum segredo do app
além do `PAGES_EDGE_SECRET`.

## Como uma visita anda

1. O visitante abre `www.cliente.com`; o DNS do cliente aponta para o IP desta portaria.
2. Na primeira visita de um domínio, o Caddy pergunta ao app
   `GET /api/pages/edge/allow?domain=…`. Só com resposta 200 (domínio verificado) ele emite
   o certificado no Let's Encrypt.
3. O pedido segue para o app com dois cabeçalhos: `X-Pages-Site-Host` (o domínio digitado)
   e `X-Pages-Edge-Secret`.
4. No app, o `proxy.ts` confere o segredo e reescreve para a rota interna
   `/edge-sites/<domínio>/…`, que desenha o site e fica em cache por 2 minutos.

## O que passa e o que não passa

| Caminho | Destino |
|---|---|
| `/_next/static/*`, `/_next/image*`, arquivos de imagem/fonte/CSS | app, sem alteração |
| `/api/in-chat/*` | chat do site |
| `/api/rpc/pages/registerVisit` | contagem de visitas |
| demais `/api/*`, `/_next/*`, `/edge-sites/*` | **404 na portaria** |
| qualquer outro caminho | página do site daquele domínio (ou 404 do app) |

Login, painel e o resto da API não são alcançáveis por domínio de cliente. Cabeçalhos
`X-Pages-*` enviados pelo visitante são descartados antes do repasse.

## Subir em produção

Pré-requisitos:

- Um **IP dedicado** para a portaria (o segundo IP do servidor). O proxy do Coolify
  (Traefik) precisa escutar **só no IP principal**: se ele estiver em `0.0.0.0:80/443`,
  este container não consegue abrir as mesmas portas no segundo IP.
- Um registro `A` de `pages.nasaex.com` para esse IP.
- No app, as variáveis `PAGES_EDGE_SECRET` (igual à daqui), `PAGES_EDGE_HOST=pages.nasaex.com`
  e `PAGES_EDGE_IP=<o IP dedicado>`.

```bash
cp .env.example .env   # preencher os quatro valores
docker compose up -d
```

O volume `caddy_data` guarda os certificados. Não apague: reemitir tudo de uma vez esbarra
no limite do Let's Encrypt.

## O que o cliente configura no DNS dele

A tela **Domínio** do editor mostra os valores prontos:

| Tipo | Nome | Valor |
|---|---|---|
| TXT | `_nasa-verify.<domínio>` | código gerado para o site |
| CNAME | `www` | `pages.nasaex.com` |
| A | `@` | IP da portaria |

Depois ele clica em **Verificar**. O app confere o TXT e se o domínio aponta para cá.

## Isolar o tráfego do app principal

`APP_ORIGIN` pode apontar para o app principal ou para uma **segunda instância da mesma
imagem** (`ghcr.io/act962/nasa.ex`) dedicada aos sites, sem domínio público. Nesse caso as
visitas dos sites não consomem CPU nem memória do app que os clientes usam para trabalhar.

Essa segunda instância sobe com as mesmas variáveis do app **mais `SKIP_MIGRATIONS=1`**, para não
disputar as migrations do banco com o app principal no boot.

## Testar localmente

Com o app em `http://localhost:3000` e `PAGES_EDGE_SECRET` igual nos dois lados:

```bash
docker compose -f docker-compose.local.yml --env-file .env.local up -d
curl -k --resolve site-teste.example:8443:127.0.0.1 https://site-teste.example:8443/
```

Para abrir no navegador sem aviso de certificado, cadastre no site um domínio terminado em
`.localhost` e acesse `http://<domínio>:8080`.
