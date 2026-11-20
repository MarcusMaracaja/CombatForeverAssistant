# Combat Forever Assistant

<p align="center">
  <img src="CombatForeverAssistantLOGO.jpg" alt="Combat Forever Assistant" width="900">
</p>

> **[English](#english)** · **[Português (ptBR)](#português-ptbr)**

---

## English

Rotation assistant for **WoW Forever** (Interface `16001`, vanilla content on a modern
engine). When a class module suggests an ability, the addon highlights the
action-bar button that ability is bound to — with colors per function (damage, AoE,
interrupt, defensive, utility) or a single user-chosen color.

It does **not** press the key for you — it only highlights the button. You stay in
control.

### Status — early development (Hunter working; Shaman available for testing)

| Area | State |
|---|---|
| Addon loads, `/cfa` menu (General / Key button / class / Equipment / About) | Working (tested in game); new Equipment tab needs in-game validation |
| Menu settings persist — fixes the orphan-table bug where changes were written to a table detached from the SV global | Corrected (user-authored fix) — not yet verified in game |
| Highlight: **circle** or **border** modes | Working (tested in game) |
| Border width slider (0–60 px), single-color option, per-function colors | Working (tested in game) |
| Key button (draggable widget showing the bound key, lock option, "always show", 6 fonts, size, background/text color, transparency, reset) | Working (tested in game) |
| **Buff library** (`CFA.BuffLib`) — all 9 vanilla classes, all ranks, aura/cast IDs, tier tracking | Implemented — **aura reads rewritten to `C_UnitAuras.GetAuraDataByIndex`** (H-0185): `UnitBuff`/`UnitDebuff` don't exist on Forever; **not yet verified in game** |
| **Hunter class module (SV / BM / MM)** — declarative rotation, spec detection via **C_Traits ordinals** (tested in game: `spec: C_Traits F=0 M=0 S=10`), Castable engine + aura beliefs + persistent aspect belief | Working — **rotation now recommends in game** (H-0196): the castability gate was called with the wrong convention (`self`/`z` mix-up), which silently rejected every combat spell and left only the aspect flashing |
| **Hunter rotation** — aspects (Cheetah/Hawk/Beast/Monkey/Pack), Hunter's Mark, Concussive Shot, pet management, spec rotation (Aimed Shot / Serpent Sting / Arcane Shot / Multi-Shot / Rapid Fire / Mongoose / Raptor / Disengage), racial, Auto Shot as filler | Working — **verified in game by the user** (H-0196/H-0197); dead zone (5–10 yd) now triggers **Disengage** |
| **Global racial system** — every race/class combination of WoW Forever (Human, Dwarf, Night Elf, Gnome, Orc, Undead, Tauren, Troll, Skyborne) | Implemented (H-0189/H-0190) — low priority: only suggests when the rotation has nothing else to say |
| **Debug commands** — `/cfa debug` (on/off + rotation report), `/cfa debug on|off`, `/cfa probe` (client API dump) | Implemented (H-0196) — prints the reason every node was rejected |
| **Equipment recommendations** (19 gear slots, select equipped/bag items, per-item conditions, highlights the action-bar item without using/equipping it) | Implemented (H-0208) — **not yet verified in game** |
| **Rotation editor window** (per-character node toggles, per-node conditions/filters via 6 cascade axes + special predicates, icon-click flash test, `^`/`v` reorder, BM/MM/SV/Extra tabs, reset-to-default) | Implemented — color codes fixed (H-0186/0187) — **not yet verified in game** |
| **Hunter Extra tab** (per-character toggles for Cheetah, Pack, Monkey, Beast and Hawk suggestions) | Implemented (H-0208) — **not yet verified in game** |
| **Shaman module** (Elemental and Enhancement damage priorities, Restoration caster fallback, configurable Extra buffs) | Implemented (H-0213) — **not yet verified in game**; Restoration healing is not automated |
| Login welcome (spec bless + spec + detection source + race greeting) | Working (tested in game — prints on first tick) |
| Class modules (Warrior, Druid, Paladin) | **Not implemented yet** — next phases |

### Development log (2026-11-17/18/19/20)

- **H-0178** — SavedVariables never persisted (orphan table) — user-authored fix via `ADDON_LOADED` re-anchoring.
- **H-0179/0180/0181/0182** — official logo, minimap button, addon-list icon, source art.
- **H-0183/0184** — Hunter module (SV/BM/MM declarative rotation) + rotation editor;
  silent rotation crash fixed (secret numbers, `duration` global, `checked` flag).
- **H-0185** — `UnitBuff`/`UnitDebuff` don't exist → BuffLib crash every tick; rewritten
  to `C_UnitAuras`; opaque panels; flash shows Key Button and turns off properly.
- **H-0186** — 6 user-reported bugs: spec by `treeIDs` ordinal, persistent aspect belief
  (rotation starvation), picker floating/cut off, `|c` prefix, `^`/`v` reorder, ESC closes.
- **H-0187** — rotation dead again: spellbook scan (`GetSpellBookItemInfo`) doesn't respond
  on this client → "known" now via `C_SpellBook.IsSpellKnownOrInSpellBook` + rank-family
  table (Hunter); castable decisions by ID; color codes fully fixed.
- **H-0189/H-0190** — **global racial system** for every race/class combination of WoW
  Forever; secret-value guard in the cooldown reader.
- **H-0192 → H-0195** — castability engine rewritten to follow the SpellFlash Forever
  pattern: spell known / cooldown / GCD / range / auras / enemy target, all fail-open
  where the client can't read a value.
- **H-0196** — **the rotation was dead because of a single call convention**: the
  castability gate is a method (`self` implicit) but was called with `.`, so the
  argument arrived as `nil` and *every* combat spell was rejected — only the aspect
  flashed. Fixed, plus: aspect detection by **localized name** (BuffLib only matched
  English names), aspect no longer blocks the rotation (3 ignored suggestions → 30 s
  pause), `nil` spell-name crash fixed, and the new `/cfa debug` + `/cfa probe` commands.
- **H-0197** — **Disengage never fired**: `isMelee` and `tooCloseForRanged` were always
  identical (`≤ 10 yd`), so "dead zone" was a contradiction. Now the real Hunter
  dead zone (5–10 yd) is detected (measured distance, or *Atacar* vs *Corte de Asa*
  probes) and Disengage triggers; pet utilities (Mend/Call/Revive Pet) moved **after**
  the spec rotation so they can no longer starve the combat rotation.
- **H-0208** — Added per-character equipment-item rules and a Hunter **Extra** tab for
  optional aspect suggestions. Items are only highlighted on the action bar; the player
  still clicks them normally. Both features need in-game validation.
- **H-0209** — Guarded optional icon-texture cropping during rotation-card redraws and made
  the options and Hunter editor windows slightly transparent (85% opacity). Needs in-game
  validation.
- **H-0210** — Kept the item/condition picker fully opaque by parenting it to `UIParent`
  instead of inheriting the options window's alpha; it now closes when the options window
  closes or changes tabs.
- **H-0211** — Fixed both rotation reorder buttons: `selectSpec` now assigns to its forward-
  declared local instead of shadowing it. The buttons need in-game validation.
- **H-0212** — Fixed rotation skill re-enabling (the Lua `and nil or false` expression always
  selected `false`) and corrected the Extra checkboxes' colon-method call, which made saved
  enabled aspects appear unchecked. Extra remains a toggle list: its recommendation conditions
  are automatic and fixed by the Hunter aspect logic.
- **H-0213** — Added the Shaman module: Elemental/Enhancement priorities, automatic or manual
  talent-tree selection, and independently configurable buff recommendations. The Restoration
  tree currently uses a caster-DPS fallback (no healing). Needs in-game testing.

> **Saved variables:** settings persist on `/reload` (and on logout/clean exit), like any
> Blizzard client. An earlier bug made menu changes persist nowhere: `addon.db` was bound
> to a table created at load time instead of the global the client writes to. Fixed by
> re-anchoring `addon.db` / `addon.charDb` to the real globals inside `ADDON_LOADED` (see
> `memory/enciclopedia/12-savedvariables-e-persistencia.md` in the project archive).

### Hunter rotation

`/cfa` → **Hunter** tab (visible only to Hunters):
- toggle the module on/off, pick the spec (**auto / BM / MM / SV**)
- click **Open rotation editor** to open the rotation window (cards with every
  skill of the rotation — click to enable/disable individual nodes, per character)
- each card: **[+]** adds conditions under which the ability fires (6 cascade
  filter axes — combat / environment / target / range / resource / area — plus
  special predicates), **[-]** removes them, per character
- clicking a node's **icon flashes the button** it is bound to on your action bars (test)
- rotations are declared as data (`Modules\Hunter\Scripts_SV|BM|MM.lua`) and the
  per-character overrides are stored in the character DB
  (`CombatForeverAssistantCharDB.hunterRotation`)

> Engine: declarative rotation runner in `Core.lua` (`ConcatCommonNodes` /
> `RunDeclaredRotation`), spec detection via `C_Traits` (override respected first),
> rank resolution via the spell book, aura beliefs for secret auras in combat, and
> press-suppression so the highlight dies the instant you press the key.

### Debugging the rotation

| Command | What it does |
|---|---|
| `/cfa debug` | toggles debug mode and prints the rotation report |
| `/cfa debug on` / `/cfa debug off` | enables / disables it explicitly |
| `/cfa probe` | dumps the client APIs the rotation relies on (class, race, combat, distance, `C_Spell*`, `C_SpellBook`, auras, cooldowns) |
| `/cfa status` | active module, detected spec and the last rotation error |

With debug mode on, every tick prints the environment (enemy / combat / melee / dead
zone / distance / AoE), every node with the result of its condition, and — for each
rejected spell — the exact reason (`out of range`, `on cooldown (12.0s of 15.0s)`,
`spell unknown`, `no enemy target`, …).

### Hunter dead zone (Disengage)

In WotLK the hunter's melee abilities need **5 yd** and the ranged ones stop working
between **5 and 10 yd**. The addon measures the distance to the target and, when the
client can't report it, compares the *Atacar* action (≤5 yd) with *Wing Clip* (≤10 yd)
to detect the dead zone — where **Disengage** is the right pick.

### Equipment item suggestions

Open `/cfa` → **Equipment** (above **About**). Choose an item for a gear slot from the
equipped items and bags, use **[+] / [-]** to add or remove conditions, then place that item
on an action bar. CFA highlights the matching item action when the conditions pass; clicking
it remains the game's normal item use. CFA never uses, equips or swaps items automatically.
Rules are saved per character. Availability depends on the client exposing the item's slot
metadata, so new/custom items still need a real client test.

The Hunter rotation editor's **Extra** tab lets you enable or disable Cheetah, Pack, Monkey,
Beast and Hawk suggestions independently of the talent specialization. Other class-specific
buff controls are not implemented until those class modules return to the build.

### Highlight modes

- **Circle** — a dashed colored ring around the recommended button (native textures).
- **Border** — a colored frame around the button (4 edge bars, 0–60 px wide).

### Installation

On GitHub, select **Code > Download ZIP** for the `main` branch and extract the archive.
GitHub names the extracted folder `CombatForeverAssistant-main`; rename it to
`CombatForeverAssistant` and place it in `Interface\AddOns\`. Verify that
`CombatForeverAssistant.toc` is directly inside the addon folder:
`Interface\AddOns\CombatForeverAssistant\CombatForeverAssistant.toc`. Do not keep the
`-main` suffix or nest a second `CombatForeverAssistant` folder inside it. Launch WoW,
enable the addon in the AddOns list if needed, and type `/reload`.

### Requirements

WoW Forever, Interface **16001**. No external dependencies.

### License

[MIT](LICENSE) — © 2026 Marcus. See `LICENSE`.

---

## Português (ptBR)

Assistente de rotação para o **WoW Forever** (Interface `16001`, conteúdo vanilla em
engine moderna). Quando um módulo de classe sugere uma habilidade, o addon destaca o
botão da barra de ação onde a habilidade está ligada — com cores por função (dano, área,
interrupção, defensivo, utilidade) ou uma cor única escolhida por você.

Ele **não** aperta a tecla por você — apenas destaca o botão. Você continua no controle.

### Status — desenvolvimento inicial (rotação do Hunter funcionando, outras classes pendentes)

| Área | Estado |
|---|---|
| Addon carrega, menu `/cfa` (Geral / Botão de tecla / Equipamentos / Sobre) | Funcionando (testado em jogo); aba Equipamentos precisa de validação em jogo |
| Configurações do menu persistem — corrige o bug da tabela órfã (mudanças iam para uma tabela desconectada do global de SV) | Corrigido (correção do usuário) — ainda não verificado em jogo |
| Destaque: **círculo** ou **moldura** | Funcionando (testado em jogo) |
| Slider de largura da moldura (0–60 px), cor única, cores por função | Funcionando (testado em jogo) |
| Botão de tecla (widget arrastável mostrando a tecla, trava, "sempre exibir", 6 fontes, tamanho, cor de fundo/texto, transparência, restaurar padrões) | Funcionando (testado em jogo) |
| **Biblioteca de buffs** (`CFA.BuffLib`) — as 9 classes vanilla, todos os ranks, IDs de aura/cast, tiers, aviso de buff desatualizado | Implementada — **leitura de auras reescrita para `C_UnitAuras.GetAuraDataByIndex`** (H-0185): `UnitBuff`/`UnitDebuff` não existem no Forever; **ainda não verificada em jogo** |
| **Módulo Hunter (SV / BM / MM)** — rotação declarativa, detecção de spec via **ordinals de `treeIDs` do C_Traits** (testada em jogo: `spec: C_Traits F=0 M=0 S=10`), engine de Castable + crenças de aura + crença de aspecto persistente | Funcionando — **a rotação agora recomenda em jogo** (H-0196): o gate de castabilidade era chamado com a convenção errada (`self`/`z` trocados), recusando silenciosamente todas as spells de combate e deixando só o aspecto piscar |
| **Rotação do Hunter** — aspectos (Guepardo/Falcão/Fera/Macaco/Matilha), Marca do Caçador, Tiro Concussivo, gestão do pet, rotação da spec (Disparo Preciso / Mordida de Serpente / Disparo Arcano / Disparo Múltiplo / Disparo Rápido / Mordida de Mongoose / Golpe de Raptor / Fuga), racial e Tiro Automático como filler | Funcionando — **verificado em jogo pelo usuário** (H-0196/H-0197); a zona morta (5–10 yd) agora dispara o **Fuga (Disengage)** |
| **Sistema global de raciais** — todas as combinações de raça/classe do WoW Forever (Humano, Anão, Elfo Noturno, Gnomo, Orc, Morto-vivo, Tauren, Troll, Skyborne) | Implementado (H-0189/H-0190) — baixa prioridade: só sugere quando a rotação não tem nada a dizer |
| **Comandos de debug** — `/cfa debug` (liga/desliga + relatório da rotação), `/cfa debug on|off`, `/cfa probe` (dump das APIs do cliente) | Implementado (H-0196) — mostra o motivo de cada nó recusado |
| **Recomendações de itens de equipamento** (19 slots, seleção de itens equipados/bolsas, condições por item, destaca o item na barra sem usá-lo/equipá-lo) | Implementadas (H-0208) — **ainda não verificadas em jogo** |
| **Janela de edição de rotação** (liga/desliga nós por personagem, condições/filtros por nó via 6 eixos de filtro + predicados especiais, clique no ícone para testar o flash, `^`/`v` reordenar, abas BM/MM/SV/Extra, restaurar padrão) | Implementada — códigos de cor corrigidos (H-0186/0187) — **ainda não verificada em jogo** |
| **Aba Extra do Hunter** (liga/desliga por personagem as recomendações de Guepardo, Matilha, Macaco, Fera e Falcão) | Implementada (H-0208) — **ainda não verificada em jogo** |
| **Módulo Shaman** (prioridades de dano Elemental e Enhancement, fallback caster para Restauração, buffs Extra configuráveis) | Implementado (H-0213) — **ainda não verificado em jogo**; curas de Restauração não são automatizadas |
| Boas-vindas no login (bênção da spec + spec + origem da detecção + saudação racial) | Funcionando (testada em jogo — imprime no primeiro tick) |
| Módulos de classe (Warrior, Druid, Paladin) | **Ainda não implementados** — próximas fases |

### Log de desenvolvimento (2026-11-17/18/19/20)

- **H-0178** — SavedVariables nunca persistem (tabela órfã) — correção do usuário via re-âncora no `ADDON_LOADED`.
- **H-0179/0180/0181/0182** — logo oficial, botão do minimapa, ícone na lista de addons, arte-fonte.
- **H-0183/0184** — módulo Hunter (rotação declarativa SV/BM/MM) + editor de rotação; rotação morta em silêncio
  corrigida (números secret, global `duration`, flag `checked` do `UnitDistanceSquared`).
- **H-0185** — `UnitBuff`/`UnitDebuff` não existem no Forever → BuffLib estourava todo tick; reescrito para
  `C_UnitAuras`; painéis opacos; flash mostra o botão de tecla e apaga de verdade.
- **H-0186** — 6 bugs do usuário: spec por ordinal de `treeIDs`, crença de aspecto persistente
  (a rotação starveava), picker cortado/flutuando, prefixo `|c`, botões `^`/`v`, ESC fecha.
- **H-0187** — rotação morta de novo: a varredura do spellbook (`GetSpellBookItemInfo`) não responde neste
  cliente → "conhecido" agora via `C_SpellBook.IsSpellKnownOrInSpellBook` + tabela FAMILIES de ranks do Hunter;
  decisões de castable por ID; códigos de cor definitivamente corrigidos.
- **H-0189/H-0190** — **sistema global de raciais** para todas as combinações de raça/classe do WoW Forever;
  proteção contra *secret values* na leitura de cooldown.
- **H-0192 → H-0195** — engine de castabilidade reescrito no padrão do SpellFlash Forever:
  spell conhecida / cooldown / GCD / alcance / auras / alvo inimigo, tudo *fail-open* quando o
  cliente não consegue ler um valor.
- **H-0196** — **a rotação estava morta por causa de uma única chamada**: o gate de castabilidade é um
  método (`self` implícito) mas era chamado com `.`, então o argumento chegava `nil` e *todas* as spells
  de combate eram recusadas — só o aspecto piscava. Corrigido, mais: detecção de aspecto pelo **nome
  localizado** (o BuffLib só casava nome em inglês), o aspecto não trava mais a rotação (3 sugestões
  ignoradas → pausa de 30 s), crash de nome `nil` corrigido e novos comandos `/cfa debug` e `/cfa probe`.
- **H-0197** — **o Fuga (Disengage) nunca disparava**: `isMelee` e `tooCloseForRanged` eram sempre
  iguais (`≤ 10 yd`), então a "zona morta" era uma contradição. Agora a zona morta real (5–10 yd) é
  detectada (distância medida, ou sondagem *Atacar* × *Corte de Asa*) e o Fuga dispara; as utilidades
  de pet (Curar/Chamar/Reviver Ajudante) passaram para **depois** da rotação da spec, para não
  mais bloquearem as habilidades de combate.
- **H-0208** — Adicionadas regras por personagem para itens de equipamento e uma aba **Extra** do
  Hunter para controlar recomendações de aspectos. O addon apenas destaca o item na barra; não o
  usa, equipa nem troca automaticamente. As duas funções ainda precisam ser testadas em jogo.
- **H-0209** — Protegido o recorte opcional das texturas dos ícones ao redesenhar os cards e
  aplicada transparência leve (85% de opacidade) às janelas de opções e do editor Hunter. Precisa
  de validação em jogo.
- **H-0210** — O seletor de itens/condições agora fica opaco, sem herdar a transparência da janela
  principal, e fecha ao fechar a janela ou trocar de aba.
- **H-0211** — Corrigidas as duas setas da rotação: `selectSpec` agora preenche a variável local
  declarada antecipadamente, sem sombreá-la. Os botões ainda precisam de validação em jogo.
- **H-0212** — Corrigido o re-ligar de habilidades (a expressão Lua `and nil or false` sempre
  resultava em `false`) e a chamada por ponto na aba Extra, que mostrava os aspectos ativos como
  desmarcados. Extra continua sendo uma lista de ativação: as condições dos aspectos são automáticas.
- **H-0213** — Adicionado o módulo Shaman: prioridades Elemental/Enhancement, seleção automática
  ou manual da árvore e recomendações de buffs Extra independentes. Restauração usa fallback
  caster de dano (sem cura automatizada). Precisa de teste em jogo.

> **Variáveis salvas:** as configurações persistem no `/reload` (e no logout/saída limpa),
> como em qualquer cliente Blizzard. Um bug anterior fazia as mudanças sumirem: `addon.db`
> ficava ligado a uma tabela criada ao carregar o arquivo, não ao global que o client
> grava. Corrigido re-ancorando `addon.db` / `addon.charDb` aos globals reais dentro do
> `ADDON_LOADED` (veja `memory/enciclopedia/12-savedvariables-e-persistencia.md` no
> arquivo do projeto).

### Rotação do Hunter

`/cfa` → aba **Hunter** (visível só para caçadores):
- ligar/desligar o módulo e escolher a spec (**automático / BM / MM / SV**)
- clique em **Abrir editor de rotação** para abrir a janela com os cards de
  todas as habilidades da rotação — clique para ligar/desligar cada nó, por personagem
- cada card: **[+]** adiciona condições para a habilidade disparar (6 eixos de
  filtro em cascata — combate / ambiente / alvo / alcance / recurso / área — além
  dos predicados especiais), **[-]** remove, por personagem
- clicar no **ícone** do nó faz o botão ligado a ele piscar nas suas barras (teste)
- as rotações são declaradas como dados (`Modules\Hunter\Scripts_SV|BM|MM.lua`) e os
  overrides por personagem ficam no DB do personagem
  (`CombatForeverAssistantCharDB.hunterRotation`)

> Motor: runner de rotação declarativa no `Core.lua` (`ConcatCommonNodes` /
> `RunDeclaredRotation`), detecção de spec via `C_Traits` (override tem prioridade),
> resolução de rank pelo spell book, crenças de aura para as auras secretas em combate
> e supressão do brilho assim que você aperta a tecla.

### Depurando a rotação

| Comando | O que faz |
|---|---|
| `/cfa debug` | liga/desliga o modo debug e imprime o relatório da rotação |
| `/cfa debug on` / `/cfa debug off` | liga / desliga explicitamente |
| `/cfa probe` | despeja as APIs do cliente usadas pela rotação (classe, raça, combate, distância, `C_Spell*`, `C_SpellBook`, auras, cooldowns) |
| `/cfa status` | módulo ativo, spec detectada e o último erro da rotação |

Com o modo debug ligado, cada tick imprime o ambiente (inimigo / combate / melee / zona
morta / distância / AoE), cada nó com o resultado da sua condição e — para cada spell
recusada — o motivo exato (`fora de alcance`, `em cooldown (12.0s de 15.0s)`,
`spell desconhecida`, `sem alvo inimigo`, …).

### Zona morta do Hunter (Fuga / Disengage)

Em WotLK as habilidades corpo a corpo do caçador precisam de **5 yd** e as de longo
alcance param de funcionar entre **5 e 10 yd**. O addon mede a distância do alvo e,
quando o cliente não consegue informar, compara a ação *Atacar* (≤5 yd) com o *Corte de
Asa* (≤10 yd) para detectar a zona morta — onde o **Fuga** é a habilidade certa.

### Recomendações de itens de equipamento

Abra `/cfa` → **Equipamentos** (acima de **Sobre**). Escolha um item daquele slot entre os itens
equipados e das bolsas, use **[+] / [-]** para adicionar ou remover condições e coloque o item em
uma barra de ações. O CFA destaca a ação do item quando as condições são satisfeitas; clicar nela
continua usando o item normalmente pelo jogo. O CFA não usa, equipa ou troca itens automaticamente.
As regras são salvas por personagem. Itens novos/customizados dependem de o cliente fornecer os
metadados do slot, então ainda precisam de teste real.

Na aba **Extra** do editor de rotação Hunter, é possível ativar ou desativar independentemente da
especialização as recomendações de Guepardo, Matilha, Macaco, Fera e Falcão. Essa aba não usa cards
com condições editáveis: aspectos são avaliados pela lógica global do Hunter, com regras automáticas
de grupo/combate/alvo. Controles de buffs específicos de outras classes ficam pendentes até esses
módulos voltarem ao build.

### Modos de destaque

- **Círculo** — anel segmentado colorido em volta do botão (texturas nativas).
- **Moldura** — moldura colorida em volta do botão (4 barras, 0–60 px de largura).

### Instalação

No GitHub, escolha **Code > Download ZIP** para baixar a branch `main` e extraia o arquivo.
A pasta extraída se chamará `CombatForeverAssistant-main`; renomeie-a para
`CombatForeverAssistant` e coloque-a em `Interface\AddOns\`. Confira se
`CombatForeverAssistant.toc` ficou diretamente dentro da pasta do addon:
`Interface\AddOns\CombatForeverAssistant\CombatForeverAssistant.toc`. Não mantenha o sufixo
`-main` nem crie outra pasta `CombatForeverAssistant` dentro dela. Abra o WoW, habilite o
addon na lista se necessário e digite `/reload`.

### Requisitos

WoW Forever, Interface **16001**. Sem dependências externas.

### Licença

[MIT](LICENSE) — © 2026 Marcus. Veja `LICENSE`.
