# Lista de Testes em Jogo — Combat Forever Assistant

Checklist mantida a cada implementação para validação posterior no cliente **WoW Forever (Interface 16001)**.

---

## H-0233 — Camada Global de Recursos (`Shared/Functions.lua`) + Correção do Malho (Druida Feral)

### Comandos de diagnóstico disponíveis no chat
- `/cfa res` — dump completo de todos os recursos do personagem (`MANA`, `RAGE`, `FOCUS`, `ENERGY`, `COMBO_POINTS`, `RUNIC_POWER`), `UnitPowerType`, `GetShapeshiftFormID`, `GetShapeshiftForm` e, no Druida, sondagem automática do **Malho (6807)**.
- `/cfa maul` — atalho direto para `/cfa res 6807` (sondagem completa do Malho).
- `/cfa res <spellID>` — sondagem de qualquer spell por ID (custo, `C_Spell.IsSpellUsable`, `IsUsableAction`, `HasEnoughPowerForSpell`, CD, alcance, `IsCurrentSpell`, `CheckIfSpellCastable`).
- `/cfa debug on` / `/cfa debug off` — ativa/desativa logs de cada tick + imprime o relatório completo da rotação (com `cond`, `id`, `cast` e motivo de recusa de cada nó).
- `/cfa probe` — dump geral das APIs do cliente (agora inclui também o dump de recursos).

### Checklist de testes (Druida Feral — Forma de Urso)
1. **[ ] Carregamento sem erros Lua**
   - Fazer `/reload` logado no Druida.
   - Esperado: nenhum erro Lua; mensagem de boas-vindas do CFA aparece no chat.
2. **[ ] Detecção da Forma de Urso (`activeForm` / `DetectSpec`)**
   - Entrar em **Forma de Urso** (ou **Forma de Urso Terrível**) e rodar `/cfa status` e `/cfa maul` fora de combate.
   - Esperado:
     - `/cfa status` mostra `Druid - Feral (Bear) (form)`.
     - `/cfa maul` mostra `form=BEAR`, `spec=BEAR` e informa os valores de `GetShapeshiftFormID` e `GetShapeshiftForm`.
3. **[ ] Leitura de Raiva (`UnitPower`) fora de combate vs em combate**
   - Fora de combate (0 de raiva): rodar `/cfa maul`.
   - Em combate (com pouca raiva, ex. `< 15`, e depois com raiva suficiente, ex. `>= 15`): rodar `/cfa maul`.
   - Esperado:
     - Verificar no chat se `RAGE` aparece com `readable=true secret=false` ou `readable=false secret=true`.
     - Verificar se `C_Spell.IsSpellUsable` e `IsUsableAction` retornam `spellNoPower=true` (sem raiva) e `spellUsable=true spellNoPower=false` (com raiva), ou se algum vem `secret=true`.
4. **[ ] Recomendação do Malho com Raiva suficiente (15+)**
   - Em Forma de Urso, mirar um inimigo em alcance melee e entrar em combate.
   - Quando tiver **15+ de Raiva** (e prioridades mais altas como Demoralizing Roar / Mangle / Faerie Fire já estiverem aplicadas ou indisponíveis/em CD), observar o destaque na barra.
   - Esperado: o botão do **Malho (Maul)** passa a brilhar e aparece no Botão de Tecla.
5. **[ ] Bloqueio do Malho sem Raiva suficiente (< 15)**
   - Com **menos de 15 de Raiva** (ex: 0–10 de raiva), observar se o Malho **não** brilha (ou rodar `/cfa debug on` para confirmar `bear_maul: ok=false` ou `sem mana/poder`).
   - Esperado: Malho não é recomendado quando o cliente consegue confirmar falta de raiva; se todas as APIs vierem secret, o modo fail-open evita travar a rotação.
6. **[ ] Supressão quando o Malho já está enfileirado (`notIfActive`)**
   - Apertar o botão do Malho antes do próximo ataque corpo a corpo (enquanto o ícone do Malho está iluminado/enfileirado pelo jogo).
   - Esperado: o destaque do CFA some enquanto o Malho já está enfileirado (`isCurrent=true`) e nenhum erro Lua aparece (bug antigo da variável `lag`).
7. **[ ] Troca para Forma Felina (Gato) e Humanoide**
   - Trocar para **Forma de Felino** e mirar um inimigo -> `/cfa debug` deve mostrar `spec=CAT`, `form=CAT`, `catOK=true` e habilidades de Gato passando nas condições.
   - Voltar para **Humanoide** com spec Feral -> `/cfa status` deve respeitar a preferência de forma (`CAT` ou `BEAR`) e recomendar virar Urso/Gato ao mirar um inimigo.
8. **[ ] Regressão em Hunter e Shaman (se tiver tempo)**
   - Logar no Hunter (ou Shaman), rodar `/cfa res` e verificar se `MANA` (e `FOCUS`/`RAGE`/`ENERGY`) lê corretamente sem erros Lua e se a rotação continua recomendando normalmente.

### Se algo não funcionar como esperado
- Copie e cole na próxima sessão a saída completa de `/cfa maul` (em combate, com 0–10 de raiva e com 20+ de raiva) e de `/cfa debug` (em combate, mirando o inimigo em Forma de Urso).

---

## H-0234 — Menu **Food, Potions, Itens** (`Consumables.lua` + Destaque nas Bolsas em `Visuals.lua`)

### Comandos de diagnóstico disponíveis no chat
- `/cfa items` (aliases: `/cfa food`, `/cfa consumables`, `/cfa potions`) — imprime no chat:
  - Estado atual: `combat`, `moving`, `mounted`, `bagOpen`, `hp`, `mana`, `hasMana`, `eating`, `drinking`, `aurasReadable`, `swimming`, `breath`, `lastCast`;
  - Melhor Comida e melhor Bebida detectadas na bolsa (com `itemID`, nome, preço em cobre, restauração, nível mínimo, se está na barra e CD);
  - Todas as poções de bônus / elixires / frascos / pergaminhos de 5+ min encontradas na bolsa (categoria, duração, preço, `buffAtivo`, `onBar`, `cd`);
  - Todas as regras personalizadas criadas no `[+]` (se passa na condição, motivo se recusada, `inBag`, `onBar`, `cd`, gatilho de habilidade);
  - Lista final de sugestões ativas neste tick.

### Checklist de testes (Menu Food, Potions, Itens)
1. **[ ] Abertura da aba e persistência após `/reload`**
   - Abrir `/cfa` -> clicar na nova aba **Food, Potions, Itens** (entre **Equipamentos** e **Sobre**).
   - Verificar que o título cabe bem na barra lateral e que a janela rola normalmente com a roda do mouse.
   - Marcar checkboxes, ajustar sliders de % (arrastando ou com scroll do mouse), fazer `/reload` e confirmar que tudo ficou salvo por personagem.
2. **[ ] Visibilidade da opção de Água/Mana por classe**
   - Em classe com Mana (Druida, Hunter, Shaman, etc.): devem aparecer **ambas** as linhas (Comida/Vida + Água/Mana) com seus respectivos sliders.
   - Em classe sem Mana (Warrior, Rogue — se testar em alt): a linha de Água/Mana e o eixo "5. Mana do jogador" no picker **não** devem aparecer.
3. **[ ] Comida e Água — bolsa fechada vs. bolsa aberta + simultâneos**
   - Ativar Comida (ex: `< 90%`) e Água (ex: `< 90%`) para facilitar o teste.
   - Ficar **fora de combate**, **parado**, com Vida e Mana abaixo do limite escolhido (ex: após uma luta).
   - **Bolsa fechada** (com comida e água na barra de ações): ambos os botões na barra devem brilhar **ao mesmo tempo** (o de maior valor caso haja mais de um na barra).
   - **Bolsa aberta**: o item de maior valor de Comida e o de maior valor de Água devem brilhar **na bolsa** (e **também na barra** se estiverem nela!).
   - **Começar a andar**: o brilho deve sumir imediatamente ao se mover e voltar quando parar.
   - **Entrar em combate**: o brilho de comida/água deve sumir imediatamente.
4. **[ ] Parada imediata ao comer / beber**
   - Clicar na comida e na água ao mesmo tempo.
   - Esperado: o brilho de cada um some **imediatamente** assim que começa a comer/beber (e `/cfa items` deve mostrar `eating=true` / `drinking=true`).
5. **[ ] Poções de Bônus, Elixires e Pergaminhos (5+ min)**
   - Colocar na bolsa 1 ou 2 elixires/pergaminhos de longa duração (ex: 2 elixires de Armadura de valores diferentes, ou Pergaminho de Vigor/Armadura) e ativar a checkbox da seção 2.
   - Com a bolsa aberta (ou item na barra): deve brilhar **apenas o mais caro** de cada categoria cujo buff esteja faltando.
   - Usar o elixir/pergaminho: o brilho deve sumir **imediatamente** e `/cfa items` deve mostrar `buffAtivo=true`.
6. **[ ] Regras Personalizadas (`+ Adicionar item / regra`)**
   - Clicar em **`+ Adicionar item / regra`**, escolher um item da bolsa (ex: Poção de Vida, Poção de Respiração Aquática, Bomba de Engenharia ou Elixir).
   - Testar condições no botão `[+]`:
     - **Poção de vida**: `Combate: Em combate` + `Vida <= 60%` -> só brilha em combate quando a vida cai; some ao usar ou entrar em CD.
     - **Respiração aquática**: `Ambiente: Na água / submerso` + `Fôlego < 50%` -> mergulhar até o fôlego cair abaixo de 50%, rodar `/cfa items` e confirmar `swimming=true breath=<50%` e o item brilhando.
     - **Bomba de engenharia**: `Combate: Em combate` + `Alvo: Em alcance melee` -> só brilha em combate corpo a corpo; some durante o cooldown.
     - **Gatilho de habilidade X**: em `[+]` -> `7. Gatilho de habilidade` -> `Escolher habilidade X...` -> escolher uma habilidade da sua barra; lançar essa habilidade e confirmar que o item vinculado brilha imediatamente (por até 8s ou até ser usado/entrar em CD).
   - Testar desmarcar a checkbox da regra (para de brilhar), remover uma condição no `[-]` e excluir uma regra no `[X]`.
7. **[ ] Independência da rotação de classe**
   - Confirmar que durante combate (ou fora dele), o destaque de comida/poções/itens brilha **junto** com a habilidade recomendada pela rotação sem travar nem roubar o **Botão de Tecla**.

### Se algo não funcionar como esperado
- Copie e cole a saída completa de `/cfa items` no momento em que o comportamento divergir (ex: com a bolsa aberta, comendo/bebendo, mergulhado, ou com um elixir customizado do Forever na bolsa).

---

## H-0235 — Módulo **Xamã (Shaman)** refeito do zero no padrão global (DPS: Elemental & Enhancement)

### Comandos de diagnóstico disponíveis no chat
- `/cfa shaman` — relatório completo do módulo Xamã: spec detectada e origem (`C_Traits ELE=.. ENH=.. REST=..`), `enemy`, `combat`, `melee`, `moving`, `AoE`, `mana` (`ok`), `maelstrom` stacks, `clearcast`, `flameShock`, `stormstrike`, estado real do encantamento de arma (`GetWeaponEnchantInfo` -> `has`, `id`, `rem`), `shield`, todos os 4 slots de totem (`F`/`E`/`W`/`A`), e avaliação nó-a-nó (`en`, `cond`, `id`, `cast`, motivo de recusa).
- `/cfa debug on` / `/cfa debug off` — ativa logs contínuos da rotação por tick.
- `/cfa status` — confirma spec detectada do Xamã.

### Checklist de testes (Xamã — Elemental & Enhancement DPS)
1. **[ ] Carregamento, boas-vindas e detecção de spec (`C_Traits` global)**
   - Logar no Xamã, fazer `/reload` e rodar `/cfa status` + `/cfa shaman`.
   - Esperado: nenhum erro Lua; spec detectada corretamente (`ELE` ou `ENH`) via pipeline global `C_Traits` (ou fallback de signature spell).
2. **[ ] Aba Shaman e Editor de Rotação compartilhado**
   - Abrir `/cfa` -> aba **Shaman**.
   - Testar rolagem da aba, troca de override de spec (`Automático` / `Elemental` / `Aperfeiçoamento` / `Restauração`) e clicar em **Abrir editor de rotação**.
   - Esperado: o editor abre com as abas `Elemental`, `Enhancement`, `Restoration (DPS fallback)` e `Extra`; botões `^`/`v`, `[+]`/`[-]`, clique no ícone para testar flash e checkboxes funcionam e persistem após `/reload`.
3. **[ ] Detecção real de Encantamento de Arma (`GetWeaponEnchantInfo`)**
   - Sem encantamento na arma principal -> deve recomendar **Flametongue Weapon** (Elemental) ou **Windfury Weapon** (Enhancement; ou **Rockbiter Weapon** se nível baixo antes do 30).
   - Aplicar o encantamento na arma e rodar `/cfa shaman`: confirmar `armaMH: has=true id=... rem=...` e que o brilho do encantamento **some imediatamente** (não fica preso em loop).
4. **[ ] Escudos e Totens (Extra)**
   - Sem escudo ativo -> recomenda **Lightning Shield** (ou **Water Shield** se habilitado na aba Extra / mana baixa).
   - Totens configuráveis (`Strength of Earth`, `Windfury / Grace of Air` no Enhancement, `Mana Spring` pré-combate/mana baixa) -> confirmar em `/cfa shaman` que `totens: F=.. E=.. W=.. A=..` detecta corretamente cada slot e para de sugerir enquanto ativo.
5. **[ ] Rotação Elemental (DPS)**
   - Em combate com alvo único: **Lightning Mastery** (CD burst, se conhecido) -> **Searing Totem** -> **Flame Shock** -> **Chain Lightning** (com Clearcasting / Maestria / mana >= 50%) -> **Lightning Bolt** como filler.
   - Em movimento: recomenda **Earth Shock**.
   - Alvo conjurando: **Earth Shock** assume prioridade máxima (`Interrupt`).
   - Em AoE (2+ inimigos): **Magma Totem** -> **Fire Nova** (só quando houver totem de fogo ativo!) -> **Chain Lightning**.
6. **[ ] Rotação Enhancement (DPS)**
   - Em combate melee: **Rage of the Farseer** (se conhecido) -> **Maelstrom Weapon** em 5 stacks (**Lightning Bolt** ST / **Chain Lightning** AoE; verificar em `/cfa shaman` se `maelstrom=` sobe até 5!) -> **Stormstrike** em CD -> **Searing/Magma Totem** + **Fire Nova** (AoE) -> **Flame Shock** -> **Earth Shock** (com Flame Shock/Stormstrike ativo).
   - Em PvP com alvo sem slow: **Frost Shock**.
   - Alvo fora de alcance melee: **Lightning Bolt** como filler à distância.

### Se algo não funcionar como esperado
- Copie e cole a saída completa de `/cfa shaman` (especialmente em combate com Maelstrom ativo, com encantamento na arma aplicado e com totens no chão) para ajustarmos qualquer Spell ID específico do WoW Forever.

---

## H-0236 — Módulo **Sacerdote (Priest DPS)** (Shadow, Discipline Smite DPS e Holy DPS fallback)

### Comandos de diagnóstico disponíveis no chat
- `/cfa priest` — imprime o relatório completo do módulo Priest DPS: spec detectada e origem (`C_Traits DISC=.. HOLY=.. SHAD=..` ou `Shadowform`), `enemy`, `combat`, `moving`, `AoE`, `hp`, `mana(ok)`, `shadowform`, `shield`, `weakSoul`, `wand`, DoTs (`SW:P`, `DP`, `VT`, `HF`) e avaliação nó-a-nó (`en`, `cond`, `id`, `cast`, motivo de recusa).
- `/cfa debug on` / `/cfa debug off` — logs contínuos da rotação por tick.
- `/cfa status` — confirma spec detectada do Sacerdote.

### Checklist de testes (Sacerdote — DPS)
1. **[ ] Carregamento, boas-vindas e detecção de spec (`C_Traits` global)**
   - Logar no Sacerdote, fazer `/reload` e rodar `/cfa status` + `/cfa priest`.
   - Esperado: nenhum erro Lua; detecção automática via `C_Traits` (árvores `DISC` / `HOLY` / `SHAD`), com prioridade para `SHAD` quando **Forma de Sombra** estiver ativa.
2. **[ ] Aba Sacerdote e Editor de Rotação compartilhado**
   - Abrir `/cfa` -> aba **Sacerdote** -> testar rolagem, override de spec (`Automático` / `Sombras` / `Disciplina` / `Sagrado`) e clicar em **Abrir editor de rotação**.
   - Esperado: editor abre com as abas `Shadow`, `Discipline (Smite DPS)`, `Holy (DPS fallback)` e `Extra`; reordenação `^`/`v`, condições `[+]`/`[-]` e checkboxes persistem após `/reload`.
3. **[ ] Buffs Extra (fora de combate e combate)**
   - Sem **Inner Fire**, **Power Word: Fortitude** ou **Divine Spirit** -> devem ser sugeridos até ficarem ativos.
   - Checar que **Shadow Protection** e **Fear Ward** vêm desmarcados por padrão e passam a ser sugeridos se você marcá-los.
4. **[ ] Rotação Shadow DPS (`SHAD`)**
   - Mirar inimigo fora de Forma de Sombra (se conhecido) -> recomenda **Shadowform** primeiro.
   - Alvo conjurando -> recomenda **Silence** (`Interrupt`).
   - Em combate com vida <= 60% e sem *Weakened Soul* -> recomenda **Power Word: Shield** (`Defensive`); confirmar que **não** repete enquanto *Weakened Soul* estiver ativo (`weakSoul=true` no `/cfa priest`).
   - Prioridade de dano parado: **Inner Focus** (passthrough) -> **Shadowfiend** (mana <= 65%) -> **Vampiric Embrace** -> **Shadow Word: Pain** -> **Devouring Plague** -> **Vampiric Touch** (se conhecido) -> **Mind Blast** -> **Shadow Word: Death** (só se vida > 35%!) -> **Mind Flay**.
   - Em movimento: não recomenda *Mind Blast* / *Mind Flay*, recomendando instantâneos (*SW:P*, *Devouring Plague*, *SW:D*).
   - Em Forma de Sombra: confirmar que **nunca** sugere **Smite** (não quebra a Shadowform!).
   - Com mana crítica (<= 12%) e varinha equipada: recomenda **Shoot (Wand)**.
5. **[ ] Rotação Discipline Smite DPS (`DISC`) e Holy DPS fallback (`HOLY`)**
   - Selecionar `DISC` (ou testar em char Discipline): **Power Infusion** / **Inner Focus** -> **Holy Fire** (ativa *Power in Light*) -> **Shadow Word: Pain** -> **Devouring Plague** -> **Penance** (se conhecido) -> **Holy Nova** (AoE 2+ melee) -> **Shadow Word: Death** -> **Smite** -> **Shoot (Wand)**.

### Se algo não funcionar como esperado
- Copie e cole a saída completa de `/cfa priest` em combate (e fora de combate com buffs) para ajustarmos qualquer Spell ID específico do WoW Forever (como *Penance*, *Devouring Plague* ou *Shadow Word: Death*).

---

## H-0237 — Módulo **Guerreiro (Warrior)** completo (Arms, Fury e Protection)

### Comandos de diagnóstico disponíveis no chat
- `/cfa warrior` — imprime o relatório completo do Guerreiro: spec e origem (`C_Traits ARMS=.. FURY=.. PROT=..`), `stance` (`BATTLE` / `DEFENSIVE` / `BERSERKER`), `shield`, `enemy`, `combat`, `melee`, `AoE`, `rage(ok)`, `hp`, `tgtHP`, `bShout`, `sBlock`, `rend`, `demo`, `tc`, `sunder` stacks, e avaliação nó-a-nó (`en`, `cond`, `id`, `cast`, motivo de recusa).
- `/cfa res` — verifica leitura da Raiva (`RAGE cur/max/readable/secret`).
- `/cfa debug on` / `/cfa debug off` — logs contínuos por tick.
- `/cfa status` — confirma spec detectada do Guerreiro.

### Checklist de testes (Guerreiro — Arms, Fury e Protection)
1. **[ ] Carregamento, detecção de spec e detecção de Postura (`stance`)**
   - Logar no Guerreiro, fazer `/reload` e rodar `/cfa status` + `/cfa warrior`.
   - Alternar entre **Battle Stance**, **Defensive Stance** e **Berserker Stance** rodando `/cfa warrior` em cada uma -> confirmar que `stance=` acompanha corretamente (`BATTLE` / `DEFENSIVE` / `BERSERKER`) e `shield=` detecta escudo equipado.
2. **[ ] Aba Guerreiro, Editor de Rotação e Menu Food/Potions (sem Mana)**
   - Abrir `/cfa` -> aba **Guerreiro** -> testar override de spec (`Automático` / `Armas` / `Fúria` / `Proteção`) e abrir o **Editor de rotação** (abas `Arms`, `Fury`, `Protection` e `Extra`).
   - Aproveitar no Guerreiro para abrir a aba **Food, Potions, Itens** e confirmar que a opção de **Água/Mana** **NÃO** aparece (classe sem mana!).
3. **[ ] Extra — Brados (`Battle Shout` / `Commanding Shout`)**
   - Com 10+ de raiva e sem **Battle Shout**, confirmar recomendação do brado; após usar, o brilho deve sumir imediatamente.
4. **[ ] Rotação Arms (`ARMS`)**
   - Fora de combate longe do alvo em Battle Stance -> **Charge**.
   - Em combate: **Victory Rush** (logo após matar um mob, nível 20+) -> **Execute** (alvo <= 20% vida) -> **Sweeping Strikes** (AoE 2+) -> **Overpower** (quando acender por dodge/Bloodthrill) -> **Mortal Strike** (em CD) -> **Rend** (alvo > 25% vida) -> **Slam** (parado) -> **Cleave** (AoE, 40+ raiva) / **Heroic Strike** (45+ raiva, ou 15+ em níveis baixos antes de Mortal Strike).
   - Confirmar que **Heroic Strike** / **Cleave** param de brilhar quando já enfileirados (`notIfActive = true`).
5. **[ ] Rotação Fury (`FURY`)**
   - Postura **Berserker Stance** (ou Battle antes do nível 30) -> **Charge** / **Intercept** -> **Pummel** (alvo conjurando) -> **Bloodrage** (raiva < 25) -> **Death Wish** (passthrough) -> **Victory Rush** -> **Execute** (<= 20% HP) -> **Bloodthirst** (CD) -> **Whirlwind** (CD) -> **Cleave** / **Heroic Strike** (excesso de raiva).
6. **[ ] Rotação Protection (`PROT`)**
   - Postura **Defensive Stance** -> **Shield Wall** (<= 25% HP) / **Last Stand** (<= 30% HP) -> **Taunt** (quando mob bater em aliado) -> **Shield Bash** / **Concussion Blow** (interrupt) -> **Shield Block** (off-GCD *passthrough*, quando tankando com 10+ raiva) -> **Revenge** (imediato quando acender!) -> **Shield Slam** (CD) -> **Thunder Clap** (AoE / sem debuff) -> **Demoralizing Shout** -> **Sunder Armor** (até 5 cargas; conferir `sunder=` no `/cfa warrior`) -> **Devastate** (se conhecido) -> **Cleave** / **Heroic Strike** (excesso de raiva).

### Se algo não funcionar como esperado
- Copie e cole a saída completa de `/cfa warrior` (e `/cfa res` se a questão envolver leitura de raiva) durante o combate para afinarmos qualquer Spell ID ou postura no Forever.

---

## H-0239 — Correção de Comida & Água nas Bolsas + Catálogo de IDs/Tiers + Expansão Automática para Poções de Combate

### O que foi corrigido / expandido
- **`Consumables.lua`**:
  - Corrigido falso-positivo em `nameLooksLikeDrink` (antes casava `"água"` / `"agua"`, fazendo buffs como *Escudo de Água* / *Andar sobre a Água* travarem `drinking=true` e suprimirem recomendações fora de combate).
  - Adicionado dobramento UTF-8 (`foldPT`) para acentos em ptBR (`Á/É/Í/Ó/Ú/Ç`) e reconhecimento de `"comer"` / `"beber"` / `"sentada"`.
  - Corrigido envenenamento de cache quando o tooltip do item ainda não tinha carregado (`tipText == ""`).
  - Adicionado catálogo explícito por `itemID` com `tier` e `restore` (`KNOWN_FOODS`, `KNOWN_DRINKS`, `KNOWN_HEAL_POTIONS` incluindo Pedras de Vida, `KNOWN_MANA_POTIONS`, e `LONG_BUFF_ITEMS` com `tier` + correção do ID `13444` -> `13453` para *Elixir of Brute Force*), combinado com fallback dinâmico por tooltip para itens customizados do WoW Forever.
  - **Nova seção na aba Food, Potions, Itens**: **Poções de Combate** (checkbox + slider de % para **Poção de Vida** e, em classes com mana, **Poção de Mana**), escolhendo automaticamente a poção mais valiosa/forte usável na bolsa/barra durante o combate.
- **`Visuals.lua`**:
  - Corrigida detecção de botões de bolsa (`GetSlotAndBagID()`, `EnumerateValidItems` 1 ou 2 retornos, `container.Items`, `ContainerFrame<N>Item<slot>`, **ElvUI** e **Bagnon**).
  - Corrigido `SetFrameStrata` / `SetFrameLevel(+10)` em `DashRing`, moldura e texturas para o brilho nunca ficar escondido atrás do ícone do slot da bolsa.
- **`Core.lua`**:
  - Corrigido `Visuals.Hide()` rodando a cada tick de 0,2s (que destruía e recriava overlays 5x/s).
  - Corrigido `IsEatingOrDrinking()` para suprimir a rotação de classe sem apagar o brilho do par faltante (ex.: permite Comida + Água brilharem juntas e a Água continuar brilhando enquanto começa a comer).

### Comandos de diagnóstico disponíveis no chat
- `/cfa items` — agora mostra também:
  - Frames de bolsa abertos detectados (`bagOpen=true (ContainerFrameCombinedBags)` ou `ElvUI_ContainerFrame` etc.);
  - Melhor Comida, Melhor Bebida, Melhor Poção de Vida e Melhor Poção de Mana (com `tier`, `valor`, `restore`, `bagBtns=N` e `barBtns=M`);
  - Quantos botões de bolsa (`bagBtns`) e de barra (`barBtns`) foram encontrados para cada sugestão ativa;
  - Lista completa de **todos os consumíveis (`classID=0`) na bolsa** com `[itemID] nome | sub | price | spell | flags=F/D/HP/MP/LB | tipLen`, facilitando diagnosticar instantaneamente qualquer item exclusivo do WoW Forever.

### Checklist de testes (Comida, Água e Poções)
1. **[ ] Diagnóstico inicial com bolsa aberta (`/cfa items`)**
   - Fazer `/reload`, abrir a bolsa com comida, água e poções dentro e rodar `/cfa items`.
   - Esperado:
     - `bagOpen=true (<nome do frame da bolsa>)` aparece no chat (tanto na UI padrão quanto com ElvUI/Bagnon);
     - `Melhor Comida`, `Melhor Bebida`, `Melhor Poção de Vida` e `Melhor Poção de Mana` aparecem com `bagBtns >= 1`;
     - Mesmo com **Escudo de Água** ativo (no Xamã), `drinking=false`!
2. **[ ] Comida e Água brilhando na bolsa (fora de combate, parado)**
   - Em `/cfa` -> **Food, Potions, Itens**, marcar **Recomendar Comida (Vida)** (ex.: `90%`) e **Recomendar Água (Mana)** (ex.: `90%`).
   - Ficar fora de combate, parado, com Vida e Mana abaixo do limite e abrir a bolsa.
   - Esperado: o item de Comida mais forte/valioso e o item de Água mais forte/valioso brilham **visivelmente por cima do ícone da bolsa** (testar nos estilos Círculo, Moldura, Chama, Raio e Zoom).
   - Se colocar mais de uma comida/água na bolsa (ex.: água conjurada + água barata de NPC), confirmar que brilha a de maior tier/restauração (e que itens acima do seu nível são ignorados).
3. **[ ] Comida + Água simultâneos e parada ao comer/beber**
   - Com ambos brilhando, clicar primeiro na Comida: o brilho da Comida deve apagar imediatamente, enquanto a Água **continua brilhando** até você clicar nela também.
   - Assim que estiver comendo e bebendo: nenhum brilho de rotação de classe nem de poção de bônus deve aparecer.
4. **[ ] Poções de Combate (Vida e Mana — automático)**
   - Na nova seção **Poções de Combate**, marcar **Recomendar Poção de Vida** (ex.: `75%` para testar fácil) e, em classe com mana, **Recomendar Poção de Mana** (ex.: `75%`).
   - Em classe sem mana (Guerreiro/Ladino): confirmar que **Recomendar Poção de Mana** fica oculta.
   - Entrar em combate e deixar a vida/mana cair abaixo do % configurado (com a bolsa aberta ou com a poção na barra).
   - Esperado: a poção de vida/mana (ou Pedra de Vida) de maior tier/restauração usável no seu nível brilha automaticamente; ao beber a poção, o brilho some imediatamente durante a recarga.
5. **[ ] Poções de Bônus / Elixires / Pergaminhos (5+ min)**
   - Marcar a seção de poções de bônus (5+ min) com 2 elixires/pergaminhos da mesma categoria de tiers diferentes na bolsa (ex.: Pergaminho de Vigor II e IV).
   - Esperado: brilha apenas o de maior tier; ao usar, o brilho some imediatamente.

### Se algo não funcionar como esperado
- Abra a bolsa com as comidas/águas/poções, fique na situação em que deveria brilhar e cole na próxima sessão a saída completa de `/cfa items` (a nova seção `Todos consumíveis (classID=0) escaneados na bolsa` e os valores de `bagBtns` / `bagOpen` vão mostrar a causa exata na hora).
