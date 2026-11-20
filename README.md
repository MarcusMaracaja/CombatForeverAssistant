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

### Status — early development (Hunter and Druid rotations implemented; other classes pending)

| Area | State |
|---|---|
| Addon loads, `/cfa` menu (General / Key button / About) | Working (tested in game) |
| Menu settings persist — fixes the orphan-table bug where changes were written to a table detached from the SV global | Corrected (user-authored fix) — not yet verified in game |
| Highlight: **circle** or **border** modes | Working (tested in game) |
| Border width slider (0–60 px), single-color option, per-function colors | Working (tested in game) |
| Key button (draggable widget showing the bound key, lock option, "always show", 6 fonts, size, background/text color, transparency, reset) | Working (tested in game) |
| **Buff library** (`CFA.BuffLib`) — all 9 vanilla classes, all ranks, aura/cast IDs, tier tracking | Implemented — **aura reads rewritten to `C_UnitAuras.GetAuraDataByIndex`** (H-0185): `UnitBuff`/`UnitDebuff` don't exist on Forever; **not yet verified in game** |
| **Hunter class module (SV / BM / MM)** — declarative rotation, spec detection via **C_Traits ordinals** (tested in game: `spec: C_Traits F=0 M=0 S=10`), Castable engine + aura beliefs + persistent aspect belief | Working — **rotation now recommends in game** (H-0196): the castability gate was called with the wrong convention (`self`/`z` mix-up), which silently rejected every combat spell and left only the aspect flashing |
| **Hunter rotation** — aspects (Cheetah/Hawk/Beast/Monkey/Pack), Hunter's Mark, Concussive Shot, pet management, spec rotation (Aimed Shot / Serpent Sting / Arcane Shot / Multi-Shot / Rapid Fire / Mongoose / Raptor / Disengage), racial, Auto Shot as filler | Working — **verified in game by the user** (H-0196/H-0197); dead zone (5–10 yd) now triggers **Disengage** |
| **Hunter spell range lookup** — reachability, cooldown and usability must not share the same rank identifier | **H-0201** corrects the post-H-0200 regression: range is queried by base name, while cooldown/usability use the resolved known ID. The differential regression and all local suites pass; **in-game recheck pending** |
| **Druid class module (Feral / Balance / Restoration)** — form-aware rotations (Cat/Bear), Moonkin/Insect Swarm/Moonfire, Frenzied Regeneration, Demoralizing Roar, auto-buffs and racial | Implemented (H-0199) and hardened (H-0200) — **48 numbered regression scenarios plus direct assertions pass**; in-game verification pending |
| **Global racial system** — every race/class combination of WoW Forever (Human, Dwarf, Night Elf, Gnome, Orc, Undead, Tauren, Troll, Skyborne) | Implemented (H-0189/H-0190) — shared by class modules with an enforced class whitelist; low priority: only suggests when the rotation has nothing else to say |
| **Debug commands** — `/cfa debug` (on/off + rotation report), `/cfa debug on|off`, `/cfa probe` (client API dump) | Implemented (H-0196/H-0199/H-0200) — prints the reason every node was rejected; Druid report also shows talent-tree points/signatures and respects each node's self-cast options |
| **Rotation editor window** (per-character node toggles, per-node conditions/filters via 6 cascade axes + special predicates, icon-click flash test, `^`/`v` reorder, class tabs, reset-to-default) | Implemented — **shared by Hunter and Druid** (H-0199); the Druid editor opens on the current spec/form tab (H-0200); **not yet verified in game** |
| Login welcome (spec bless + spec + detection source + race greeting) | Working (tested in game — prints on first tick) |
| Class modules (Shaman, Warrior, Paladin, Priest) | **Not implemented yet** — next phases |

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
- **H-0192 → H-0195** — castability engine rewritten to follow the clean-room reference
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
- **H-0198** — engineering lessons consolidated from the Hunter debugging round:
  strict dot/colon call conventions, fail-open only for unreadable values, three-state
  aura reads with cast beliefs, utility nodes as non-blocking fallbacks, and a Lua
  simulator (fengari + mocked Forever APIs) as the validation gate before delivery.
- **H-0199** — **Druid module implemented** with separate Cat/Bear/Balance/Restoration
  rotations, form and specialization detection, aura beliefs, utility priority and
  racial fallback. The rotation store/editor were extracted into shared components;
  Hunter now uses the same store/editor.
- **H-0200** — **Druid delivery hardening**: learned-spell state is tri-state
  (`true`/`false`/`nil`), spec detection now requires exclusive evidence and never
  guesses Feral, unknown form state preserves the last valid form, Moonkin state is
  invalidated on shape changes, self spells work without an enemy, and only
  interruptible casts enable Bash. Aura beliefs are keyed by unit and numeric spell
  ID; mana is measured only as mana; friendly buffs fail closed; the editor opens
  the current form tab; auto-buff spam pauses after 10 sustained seconds.
  **Validation:** 48 numbered Druid scenarios plus direct assertions, 22 Hunter
  scenarios, shared-store assertions, and all 30 Lua files parsed as Lua 5.1.
  In-game verification remains pending.
- **H-0201** — **Hunter range regression after H-0200**: reachability was queried with a
  numeric rank ID, and a stale rank could return `false` even when the current rank was in
  range. The gate now queries both `SpellHasRange` and `IsSpellInRangeEx` by **base name**;
  the resolved known ID remains in use for cooldown and usability. Physical target distance
  is unchanged. **Validation:** the differential fengari regression fails before the fix and
  passes after it; the Hunter, Druid and shared-store suites also pass, and all 30 Lua files
  parse as Lua 5.1. **In-game recheck pending.**

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

### Druid rotation

`/cfa` → **Druid** tab (visible only to Druids):
- enable/disable the module and choose the spec (**automatic / Feral / Balance / Restoration**);
- the automatic detector is strict: the manual choice wins; then `GetSpecialization()`;
  then exclusive signatures from active `C_Traits` nodes; then spells proven to be
  learned. If no exclusive evidence exists, the spec stays unknown instead of
  silently defaulting to Feral;
- Feral selects **Cat Form** or **Bear Form** from the current power type (Energy or
  Rage). Moonkin Form uses `GetShapeshiftForm()` when available, plus the Moonkin
  aura/cast belief; leaving the form invalidates that belief. An unreadable form
  preserves the last valid form rather than becoming caster form;
- Moonkin Form, Cat Form and Frenzied Regeneration are self casts and do not require
  an enemy target. In Restoration, Frenzied Regeneration is eligible only below
  35% health;
- combat rotation runs first; the racial and then self-buffs (Mark of the Wild, Thorns,
  Nature's Grasp) are only fallbacks, so a utility can never hide a combat ability;
- the shared racial system enforces the race/class whitelist; the Druid never offers
  a racial that is not allowed for that class;
- the rotation editor is shared with the Hunter, stores Druid overrides separately
  (`CombatForeverAssistantCharDB.druidRotation`) and opens on the current
  Cat/Bear/Balance/Restoration/Self tab.

> Automated validation passes, but in-game verification is still pending. Use
> `/cfa debug` to confirm the detected spec, current form and talent-tree signature.
> The exact client-side Lacerate ID still needs confirmation in game; the CFA accepts
> the local canonical candidates `54802` and `48574`.

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

### Highlight modes

- **Circle** — a dashed colored ring around the recommended button (native textures).
- **Border** — a colored frame around the button (4 edge bars, 0–60 px wide).

### Installation

Copy the `CombatForeverAssistant` folder into `Interface\AddOns\` and type `/cfa`.

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

### Status — desenvolvimento inicial (rotações do Hunter e Druid implementadas; outras classes pendentes)

| Área | Estado |
|---|---|
| Addon carrega, menu `/cfa` (Geral / Botão de tecla / Sobre) | Funcionando (testado em jogo) |
| Configurações do menu persistem — corrige o bug da tabela órfã (mudanças iam para uma tabela desconectada do global de SV) | Corrigido (correção do usuário) — ainda não verificado em jogo |
| Destaque: **círculo** ou **moldura** | Funcionando (testado em jogo) |
| Slider de largura da moldura (0–60 px), cor única, cores por função | Funcionando (testado em jogo) |
| Botão de tecla (widget arrastável mostrando a tecla, trava, "sempre exibir", 6 fontes, tamanho, cor de fundo/texto, transparência, restaurar padrões) | Funcionando (testado em jogo) |
| **Biblioteca de buffs** (`CFA.BuffLib`) — as 9 classes vanilla, todos os ranks, IDs de aura/cast, tiers, aviso de buff desatualizado | Implementada — **leitura de auras reescrita para `C_UnitAuras.GetAuraDataByIndex`** (H-0185): `UnitBuff`/`UnitDebuff` não existem no Forever; **ainda não verificada em jogo** |
| **Módulo Hunter (SV / BM / MM)** — rotação declarativa, detecção de spec via **ordinals de `treeIDs` do C_Traits** (testada em jogo: `spec: C_Traits F=0 M=0 S=10`), engine de Castable + crenças de aura + crença de aspecto persistente | Funcionando — **a rotação agora recomenda em jogo** (H-0196): o gate de castabilidade era chamado com a convenção errada (`self`/`z` trocados), recusando silenciosamente todas as spells de combate e deixando só o aspecto piscar |
| **Rotação do Hunter** — aspectos (Guepardo/Falcão/Fera/Macaco/Matilha), Marca do Caçador, Tiro Concussivo, gestão do pet, rotação da spec (Disparo Preciso / Mordida de Serpente / Disparo Arcano / Disparo Múltiplo / Disparo Rápido / Mordida de Mongoose / Golpe de Raptor / Fuga), racial e Tiro Automático como filler | Funcionando — **verificado em jogo pelo usuário** (H-0196/H-0197); a zona morta (5–10 yd) agora dispara o **Fuga (Disengage)** |
| **Consulta de alcance da spell do Hunter** — alcance, cooldown e usabilidade não devem usar o mesmo identificador de rank | A **H-0201** corrige a regressão posterior à H-0200: o alcance é consultado pelo nome-base, enquanto cooldown/usabilidade usam o ID conhecido resolvido. A regressão diferencial e todas as suítes locais passam; **revalidação em jogo pendente** |
| **Módulo Druid (Feral / Equilíbrio / Restauração)** — rotações por forma (Gato/Urso), Lua/Enxame de Insetos/Lua de Fogo, Regeneração Frenética, Rugido Demoralizador, auto-buffs e racial | Implementado (H-0199) e endurecido (H-0200) — **48 cenários numerados de regressão mais assertions diretas passam**; verificação em jogo pendente |
| **Sistema global de raciais** — todas as combinações de raça/classe do WoW Forever (Humano, Anão, Elfo Noturno, Gnomo, Orc, Morto-vivo, Tauren, Troll, Skyborne) | Implementado (H-0189/H-0190) — compartilhado pelos módulos de classe com whitelist de classe aplicada; baixa prioridade: só sugere quando a rotação não tem nada a dizer |
| **Comandos de debug** — `/cfa debug` (liga/desliga + relatório da rotação), `/cfa debug on|off`, `/cfa probe` (dump das APIs do cliente) | Implementado (H-0196/H-0199/H-0200) — mostra o motivo de cada nó recusado; o relatório do Druid também mostra pontos/assinatura das árvores e respeita as opções de spell self de cada nó |
| **Janela de edição de rotação** (liga/desliga nós por personagem, condições/filtros por nó via 6 eixos de filtro + predicados especiais, clique no ícone para testar o flash, `^`/`v` reordenar, abas por classe, restaurar padrão) | Implementada — **compartilhada pelo Hunter e Druid** (H-0199); o editor do Druid abre na aba da spec/forma atual (H-0200); **ainda não verificada em jogo** |
| Boas-vindas no login (bênção da spec + spec + origem da detecção + saudação racial) | Funcionando (testada em jogo — imprime no primeiro tick) |
| Módulos de classe (Shaman, Warrior, Paladin, Priest) | **Ainda não implementados** — próximas fases |

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
- **H-0192 → H-0195** — engine de castabilidade reescrito no padrão da referência clean-room:
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
- **H-0198** — lições de engenharia consolidadas da rodada de depuração do Hunter:
  convenção rígida de ponto/dois-pontos, *fail-open* somente para valores ilegíveis, leitura de
  aura em três estados com crença do cast, utilitários como fallback sem bloqueio e simulador Lua
  (fengari + APIs do Forever mockadas) como portão de validação antes da entrega.
- **H-0199** — **módulo Druid implementado** com rotações separadas de Gato/Urso/Equilíbrio/
  Restauração, detecção de forma e spec, crenças de aura, prioridade das habilidades de combate e
  fallback de racial/auto-buffs. O armazenamento e o editor de rotação foram extraídos para
  componentes compartilhados; o Hunter agora usa a mesma infraestrutura.
- **H-0200** — **endurecimento da entrega do Druid**: estado de aprendizagem da spell em três
  estados (`true`/`false`/`nil`), detecção de spec exigindo evidência exclusiva e sem palpite de
  Feral, forma desconhecida preservando a última forma válida, estado Moonkin invalidado na troca
  de forma, spells self funcionando sem inimigo e Bash exigindo cast realmente interrompível.
  Crenças de aura agora são por unidade e ID numérico; mana é medida somente quando o recurso é
  mana; alvo de buff com condição de aliado desconhecida falha fechado; o editor abre na aba da forma
  atual; anti-spam de auto-buff pausa após 10 segundos contínuos.
  **Validação:** 48 cenários numerados do Druid mais assertions diretas, 22 cenários do Hunter,
  assertions do store compartilhado e todos os 30 arquivos Lua validados como Lua 5.1.
  A verificação em jogo continua pendente.
- **H-0201** — **regressão de alcance do Hunter após a H-0200**: o alcance era consultado por um
  ID numérico de rank, e um rank antigo podia devolver `false` mesmo com o rank vigente em
  alcance. O gate agora consulta `SpellHasRange` e `IsSpellInRangeEx` pelo **nome-base**; o ID
  conhecido resolvido continua sendo usado para cooldown e usabilidade. A distância física do
  alvo não foi alterada. **Validação:** a regressão diferencial em fengari falha antes da correção
  e passa depois; as suítes do Hunter, Druid e store compartilhado também passam, e todos os 30
  arquivos Lua são analisados como Lua 5.1. **Revalidação em jogo pendente.**

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

### Rotação do Druid

`/cfa` → aba **Druid** (visível só para druids):
- ligar/desligar o módulo e escolher a spec (**automático / Feral / Equilíbrio / Restauração**);
- a detecção automática é estrita: a escolha manual vence; depois vêm
  `GetSpecialization()`, as assinaturas exclusivas dos nós `C_Traits` ativos e, por último,
  as spells comprovadamente aprendidas. Sem evidência exclusiva, a spec permanece
  desconhecida em vez de assumir Feral silenciosamente;
- Feral seleciona **Forma de Gato** ou **Forma de Urso** pelo tipo de poder atual (Energia ou
  Fúria). A Forma de Lua usa `GetShapeshiftForm()` quando disponível, além da aura/crença do
  cast; sair da forma invalida essa crença. Uma forma ilegível preserva a última forma válida
  em vez de virar Forma de Conjurador;
- Forma de Lua, Forma de Gato e Regeneração Frenética são spells self e não exigem alvo
  inimigo. Em Restauração, a Regeneração Frenética só é elegível abaixo de 35% de vida;
- a rotação de combate roda primeiro; a racial e depois os auto-buffs (Marca da Selva, Espinhos,
  Garras da Natureza) são apenas fallbacks, portanto uma utilidade nunca oculta uma habilidade
  de combate;
- o sistema global de racial aplica a whitelist de raça/classe; o Druid nunca oferece uma racial
  que não seja permitida para a classe;
- o editor de rotação é compartilhado com o Hunter, guarda os overrides do Druid separadamente
  (`CombatForeverAssistantCharDB.druidRotation`) e abre na aba atual
  Gato/Urso/Equilíbrio/Restauração/Auto-buffs.

> A validação automatizada passa, mas a verificação em jogo ainda está pendente. Use
> `/cfa debug` para conferir a spec detectada, a forma atual e a assinatura da árvore.
> O ID exato de Lacerate no cliente ainda precisa ser confirmado em jogo; o CFA aceita os
> candidatos canônicos locais `54802` e `48574`.

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

### Modos de destaque

- **Círculo** — anel segmentado colorido em volta do botão (texturas nativas).
- **Moldura** — moldura colorida em volta do botão (4 barras, 0–60 px de largura).

### Instalação

Copie a pasta `CombatForeverAssistant` para `Interface\AddOns\` e digite `/cfa`.

### Requisitos

WoW Forever, Interface **16001**. Sem dependências externas.

### Licença

[MIT](LICENSE) — © 2026 Marcus. Veja `LICENSE`.
