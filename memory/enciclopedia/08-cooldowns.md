# 08 — Cooldowns no Forever

## A struct de cooldown deste cliente

```lua
-- C_Spell.GetSpellCooldown(spellID) / C_ActionBar.GetActionCooldown(slot)
{
    isEnabled = boolean,   -- cooldown habilitado (não desabilitado)
    isActive  = boolean,   -- resposta AUTORITATIVA: em cooldown ou não
    startTime = number?,
    duration  = number?,
    modRate   = number?,
    timeUntilEndOfStartRecovery = number?  -- remaining independente do relógio (valor autoritativo)
}
```

Armadilhas confirmadas em jogo:

- **`isActive = true` mesmo sem `startTime`/`duration`** — e os campos podem vir nil. Campo
  presente = cliente autoritativo. (H-0054)
- **`timeUntilEndOfStartRecovery`** é o valor confiável do "remaining" (ex.: trap mostrava 7.907).
  Aplicado em `s.SpellCooldown` e `s.ActionCooldown`. (H-0055)
- `startTime`/`duration` podem vir nil mesmo com CD real — por isso `isActive` vence a ausência.
- **Heurística de GCD quebrava CDs curtos**: `start == 0 and duration <= 1.5` liberava spells em CD
  real ≤ 1.5 s (a trap mostrava `duration=1`). Fix: CD ativo nunca devolve `≤ 1.5` (mín. 1.6, ou
  5 quando desconhecido). (H-0057)
- Campos podem se chamar diferente em versões: procurar ambos (`startTime` e
  `cooldownStartTime`) — H-0049/H-0050 documentaram o salto de nome.

## GCD por classe (Hunter = 3044, não 2973)

A verificação `globalcooldown > 0 and cooldown <= globalcooldown` anulava a proteção de cooldown
do Raptor Strike quando o GCD era o próprio Raptor (2973, 6 s no Forever). O GCD do Hunter passou
a ser **3044 (Arcane Shot)** no `Compat.lua`. (H-0056)

## Resolver rank conhecido — `FAMILIES` + `HighestKnownRank`

O Forever só tem o **rank atual** no livro de spells. Consultas por rank antigo devolvem nil.
A solução do Compat:

```lua
-- Compat.lua (SpellFlashForever):
s.IsSpellKnown(spellID)          -- entende famílias de rank (Spellbook/FAMILIES)
s.IsSpellKnownOrInSpellBook(id)  -- idem, exposta como API
s.HighestKnownRank(familyName)   -- maior rank conhecido da família
s.ResolveKnownID(spellID)        -- rank conhecido qualquer → id real no livro
s.SpellCooldown(spellID)         -- sempre pelo rank conhecido
```

- Consultar cooldown pelo rank conhecido → `/sfcd <id>` imprime o quadro completo (rank
  conhecido → `GetSpellCooldown` → slot da barra (`FindActionSlot`) →
  `C_ActionBar.GetActionCooldown(slot)`). (H-0057/H-0058)
- **`s.ActionCooldown(slot)`** usa a struct do **botão** (`C_ActionBar`) — independe
  de rank/nome; quando maior que a consulta por spell, vence (H-0049/H-0053).

## `/sfcd` — diagnóstico de CD

`/sfcd <id>` imprime:

1. rank conhecido (`ResolveKnownID`) e a consulta `GetSpellCooldown(rank)`;
2. o slot da barra e o CD pelo slot;
3. a simulação real de castabilidade (`CheckIfSpellCastable`) — o veredito `true/false` que a
   rotação usaria (H-0059).
Se o CD aparecer no rank/slot e a rotação ainda piscar, o problema está em
`CheckIfSpellCastable`; se mostrar 0, o problema está em `ResolveKnownID` ou na barra.

## LuaDurationObject

`C_Spell.GetSpellCooldownDuration(id[, ignoreGCD])` devolve um **userdata** (`LuaDurationObject`)
que **não** pode ser usado como número; para lógica de CD use a struct de
`GetSpellCooldown`/`GetActionCooldown`.

## Como o Castable decide

`CheckIfSpellCastable(z)` verifica, nesta ordem: usabilidade (`C_Spell.IsSpellUsable`), CD
(`s.SpellCooldown` combinado com `C_ActionBar.GetActionCooldown` — considerado o maior dos
dois), alcance (`s.SpellInRange`), alvo (`s.Enemy`), auras (`s.CheckBuff`/`s.CheckDebuff`),
GCD (`globalcooldown` da classe). Falha em qualquer um → não pisca.

## Nunca fazer

- Nunca dependa de `startTime`/`duration` sozinhos — trate `isActive` como autoritativo.
- Nunca devolva `duration ≤ 1.5` como "CD ativo" (alimenta a heurística de GCD).
- Nunca use `spellID` de evento como chave fria de comparação de CD (secret number) — resolva
  o nome antes.

## CFA: IsSpellOnCD — função booleana para valores secretos no combate

No cliente Forever, durante o combate os campos `startTime`/`duration` de `C_Spell.GetSpellCooldown`
podem vir como **secret value** (não comparáveis com `>` ou `<`). Isso fazia a função
`IsSpellOnCooldown` retornar `false` indevidamente, permitindo que skills em cooldown fossem
recomendadas e brilhassem na barra.

### Solução adotada (H-0213)

Foi criada a função `addon:IsSpellOnCD(spellID)` em `Core.lua`, usada como gate central em
`CheckIfSpellCastable`. Ela verifica cooldown por três caminhos, sem depender do campo `readable`:

1. `isActive == true` da struct `C_Spell.GetSpellCooldown` → cooldown autoritativo, mesmo sem
   `startTime`/`duration` numéricos válidos.
2. `C_Spell.GetSpellCooldownDuration` → `GetRemainingDuration`, protegido por `addon.SafeNumber`.
3. `startTime + duration > agora` (quando ambos são números válidos).

### Como aplicar em novas classes

Toda rotação declarativa passa por `CheckIfSpellCastable`, que chama `IsSpellOnCD`. Não é
necessário adicionar verificação de CD manualmente em cada nó. Basta adicionar o nó à lista de
rotação; o gate central bloqueia automaticamente skills em cooldown.

### Diagnóstico em jogo

Comando `/cfa cd` (CFA) — imprime para o spellID 1317257 (Chute de Moa):
- Nome da spell
- Resultado de `C_Spell.GetSpellCooldownDuration` e `GetSpellCooldown`
- `IsSpellKnown`, `IsSpellKnownOrInSpellBook`
- `CFA:IsSpellOnCooldown` (onCd, remaining, duration, readable)

Uso: `/cfa cd` fora de combate e durante cooldown ativo para comparar.

