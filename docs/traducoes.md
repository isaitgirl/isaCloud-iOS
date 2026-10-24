# Traduções do isaCloud

O isaCloud segue o esquema de tradução do Monal:

1. **Base: Weblate do Monal.** As strings vêm do projeto do Monal no Weblate, copiadas para `Monal/localization/external/<idioma>.lproj/`.
2. **Traduções próprias do isaCloud têm precedência.** Quando uma chave existe em `isaCloud/localization/<idioma>.lproj/<Tabela>.strings`, o valor do isaCloud é usado no lugar do valor do Monal. Chaves que só existem no isaCloud são adicionadas.
3. **Marca:** no momento do build, a palavra "Monal" nos valores é trocada por "isaCloud" (ver `scripts/isacloud-merge-localizations.sh`). As chaves não mudam.

Na prática:

- Para traduzir um texto novo do app, adicione a chave no arquivo do isaCloud (`isaCloud/localization/pt-BR.lproj/Localizable.strings`), com o texto em inglês da chave e a tradução no valor.
- Não edite as strings de `Monal/localization/external/`: elas são atualizadas pelo Weblate e seriam sobrescritas.
- Se a chave já existe no Weblate do Monal com outra tradução, a do isaCloud prevalece e não precisa ser alterada no Weblate.
- Textos de marca (como "isaCloud") não se traduzem.
