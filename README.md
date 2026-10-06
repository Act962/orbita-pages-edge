# orbita-pages-edge

Portaria dos **domínios próprios** do ÓRBITA Pages. É um Caddy que fica na frente só dos
domínios de clientes (`www.cliente.com`), cuida do HTTPS de cada um e repassa ao app apenas
o que um site publicado precisa.

A página **não** é desenhada aqui: quem monta o HTML é o app (`nasa.ex`), com o mesmo código
do editor. Este repositório não tem banco, não tem sessão e não conhece nenhum segredo do app
além do `PAGES_EDGE_SECRET`.

## Como uma visita anda

1. O visitante abre `www.cliente.com`; o DNS do cliente aponta para o IP desta portaria.
2. O HTTPS do domínio é resolvido antes de chegar às regras: no modo A pelo Coolify, no
   modo B pelo próprio Caddy, que antes pergunta ao app
   `GET /api/pages/edge/allow?domain=…` e só emite com resposta 200 (domínio verificado).
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

Há dois modos. O que está em uso é o **A**.

### Modo A — dentro do Coolify, no mesmo servidor e IP do app

A portaria roda como mais um serviço do Coolify, atrás do proxy dele. Quem emite o
certificado de cada domínio é o Coolify; a portaria recebe HTTP puro e só aplica as regras
de repasse (`Caddyfile.coolify` + `routes.caddy`, empacotados pelo `Dockerfile`).

1. No Coolify, criar um recurso a partir deste repositório, com build por **Dockerfile** e
   porta exposta **80**.
2. Variáveis do recurso:
   - `APP_ORIGIN` — origem do app que desenha os sites, com protocolo e sem barra no fim
     (a segunda instância, ver "Isolar o tráfego do app principal").
   - `PAGES_EDGE_SECRET` — o mesmo valor configurado no app.
3. Checagem de saúde: `GET /edge-healthz` na porta 80.
4. Criar o registro `A` de `pages.nasaex.com` para o IP do servidor.
5. No app, definir `PAGES_EDGE_SECRET`, `PAGES_EDGE_HOST=pages.nasaex.com` e
   `PAGES_EDGE_IP=<IP do servidor>`.

**Para cada domínio de cliente**, depois que ele aparecer como verificado no editor:
adicionar `https://www.cliente.com` e `https://cliente.com` na lista de domínios deste
recurso no Coolify. É esse passo que faz o Coolify emitir o certificado e entregar o tráfego
à portaria. Um domínio que não esteja nessa lista nem chega aqui.

### Modo B — servidor próprio, com certificado automático

Para quando houver uma máquina (ou um IP) só para a portaria. O Caddy assume as portas 80 e
443 e emite o certificado sozinho na primeira visita de cada domínio verificado, sem passo
manual por cliente (`Caddyfile` + `docker-compose.yml`). Não funciona no mesmo IP do Coolify,
porque as duas coisas disputariam as mesmas portas.

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
| A | `@` | IP da portaria (no modo A, o IP do servidor) |

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
