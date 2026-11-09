<h1 align="center">isaCloud para iOS</h1>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.pt-BR.md"><strong>Português (Brasil)</strong></a>
</p>

<p align="center">
  <img src="docs/logo-isacloud-im-liquidglass-1024.png" width="140" alt="isaCloud para iOS">
</p>

<p align="center"><strong>Mensagens instantâneas com a carinha do isaCloud.</strong><br>
Um cliente XMPP livre, bonito e brasileiro para iPhone, feito em cima do Monal.</p>

<p align="center">
  <a href="https://isacloud.com.br">isacloud.com.br</a> ·
  <a href="https://github.com/isaitgirl/isaCloud-iOS">Código no GitHub</a> ·
  <a href="CHANGELOG-USERS.md">Novidades</a> ·
  <a href="CHANGELOG.md">Changelog técnico</a>
</p>

## Sobre

O **isaCloud para iOS** é um fork do [Monal](https://monal-im.org), o cliente XMPP de código aberto
para iOS e macOS do Thilo Molitor e colaboradores. Ele usa o protocolo aberto **XMPP**, então você
pode conversar com qualquer pessoa em qualquer servidor federado — inclusive o seu. É o irmão para
iPhone do **isaCloud Messenger** para Android, que é feito em cima do Conversations.

O app é distribuído sob a licença **BSD 2-Clause** do Monal (ver [LICENSE](LICENSE)). O código
deste fork fica no [GitHub](https://github.com/isaitgirl/isaCloud-iOS).

## Sincronização com o Monal

O isaCloud para iOS acompanha o Monal e mantém a sincronização com o upstream. A branch de trabalho
é a `isaCloud`; a `develop` fica só como ponto de chegada dos commits do Monal. As modificações
deste fork são de **visual e usabilidade**, mais a paridade com o Android, e o núcleo do Monal é
preservado para deixar os merges futuros baratos. As atualizações do upstream continuam sendo
integradas.

## Recursos

O que o isaCloud acrescenta ao Monal (a lista completa está no [ROADMAP](ROADMAP.md)):

- Conversas 1:1, grupos privados e canais públicos, com **busca de canais** por servidor.
- Criptografia de ponta a ponta com **OMEMO**, com cadeado e aviso claros quando uma mensagem
  sairia sem criptografia.
- **Figurinhas** (XEP-0449), seletor de **GIF** e reações rápidas, com a **lista de quem reagiu**.
- **Figurinhas criadas por você**: recorte, texto, salvar e favoritar.
- **Citação com miniatura** de foto, GIF ou figurinha e **resposta com deslizar**.
- **Selecionar e encaminhar mensagens** (texto e mídia), além de compartilhar a partir de outros
  apps do iOS.
- Fotos e vídeos pela **câmera** ou galeria, **compressão de fotos** no envio, arquivos e
  localização.
- **Busca** por nome e pelo conteúdo das mensagens (texto completo, com pulo até a mensagem).
- Grupos e canais abrem na **primeira mensagem não lida**, com a linha "Lido até este ponto".
- **Apelido por sala**, **menções com @** e autocompletar, e **hats** (XEP-0317).
- Filtros de conversas (Não lidas, Contatos, Grupos, Canais), avatar da conta e **múltiplas
  contas**, com a conta aparecendo em cada conversa.
- Arquivamento local sincronizado com o Android e **mensagens privadas em canais**.
- Cor dos balões e tamanho do texto ao seu gosto, em Configurações → Aparência.
- Adaptado do iOS 18 ao iOS 27, inclusive o Liquid Glass.

## Instalação

O isaCloud para iOS é distribuído pelo **TestFlight** para quem for convidado pela mantenedora.
Ainda não está na App Store. Requer **iPhone com iOS 18** ou superior.

## Build

Requisitos:

- Um Mac com **Xcode 27.1**;
- **Rust** (o pacote `LibMonalRustSwiftBridge` é gerado a partir de `rust/`);
- **CocoaPods** (`pod install` dentro de `Monal/`);
- Se quiser o seletor de GIF, a chave do Giphy em `isaCloud/local/giphy-api-key.txt` (ignorado pelo
  git).

```bash
git clone --recurse-submodules git@github.com:isaitgirl/isaCloud-iOS.git
cd isaCloud-iOS && git switch isaCloud
cd Monal && pod install
open Monal.xcworkspace        # scheme "Monal"
```

Compile e teste nas duas pontas do intervalo suportado (iOS 18 e iOS 27). Os problemas de build mais
comuns (Rust, `Package.resolved`, SQLite com FTS5, Pods, assinatura) estão em
[docs/build-e-branches.md](docs/build-e-branches.md), e a publicação em
[docs/publicacao-testflight.md](docs/publicacao-testflight.md).

Os textos do isaCloud ficam em `isaCloud/localization/<idioma>.lproj/Localizable.strings` e são
mesclados por cima dos do Monal (gerenciados no
[Weblate](https://hosted.weblate.org/engage/monal/)) na hora do build, então a tradução do
isaCloud prevalece.

## Segurança e privacidade

- **OMEMO** para conversas criptografadas.
- Sem rastreamento de anúncios e sem serviço de análise. As métricas do aparelho ficam nele, a menos
  que você as exporte.
- Notificações push pelo serviço de push do isaCloud.

Encontrou um problema de segurança? Veja o [SECURITY.md](SECURITY.md).

## Créditos

- **Monal** — Thilo Molitor e colaboradores. Este fork não existiria sem o trabalho deles. A
  [wiki](https://github.com/monal-im/Monal/wiki) e as
  [XEPs suportadas](https://monal-im.org/install/#implemented-xeps) do upstream continuam valendo
  para o núcleo do app.
- **ExyteChat** — a tela de conversa, usada por meio de um [fork](docs/exytechat-fork.md) pequeno.
- **isaCloud para iOS** — mantido por Isadora / [isacloud.com.br](https://isacloud.com.br).
- Licença: **BSD 2-Clause** — ver [LICENSE](LICENSE). Contribuições precisam ser compatíveis com
  ela (**sem GPL**).

## Contribuindo

Encontrou um bug ou tem uma ideia? Abra uma issue no
[GitHub](https://github.com/isaitgirl/isaCloud-iOS/issues). Toda mudança nasce em uma branch nova a
partir da `isaCloud` e volta por pull request para a `isaCloud`; veja o
[Código de Conduta](CODE_OF_CONDUCT.md). Este fork não envia PRs para o upstream do Monal; as
mudanças ficam por aqui.

O changelog e a documentação interna estão em português.
