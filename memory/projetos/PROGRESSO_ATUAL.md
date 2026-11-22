# Progresso — Combat Forever Assistant (2026-11-21)

## Contexto
Usuário reportou: erro `PLAYER_TALENT_CHANGED` (evento inexistente no Forever), skill não brilhava, rotação parada. Diferença de comportamento entre PDV (grupo PvE) e BG.

## Arquivos modificados nesta sessão

1. **`CombatForeverAssistant\Modules\Hunter\Scripts_SV.lua`**
   - Adicionado nó `strider_kick` (Chute de Moa, spellID 1317257) em `HunterMeleeNodes`
   - Condition: `melee_only`, opts: `{noRange = true}`, passthrough: `true`
   - Alterada condition da `immolation_trap` de `within_8_st` para `trap_melee_or_close`

2. **`CombatForeverAssistant\Modules\Hunter\Predicates.lua`**
   - Adicionado predicado `trap_melee_or_close`: aceita se `hasActiveEnemy` E (`isMelee` ou `tooCloseForRanged`)
   - Adicionado label correspondente na seção `LABELS`

3. **`CombatForeverAssistant\Core.lua`**
   - Adicionada função booleana `addon:IsSpellOnCD(spellID)` (não depende do campo `readable`; usa `SafeNumber` para valores secretos do Forever)
   - Aplicada `IsSpellOnCD` em `CheckIfSpellCastable` (substituiu `IsSpellOnCooldown` para bloqueio de cooldown)
   - Modificado `RunDeclaredRotation`: após nó com `passthrough`, reseta `module.TickFlashUsed = nil` para não travar próximos nós
   - Adicionado comando `/cfa cd` para diagnóstico de cooldown do Chute de Moa

4. **Backup criado**: `_backup_20261121_strider_kick_sv` (cópia completa da pasta CombatForeverAssistant)

## Problemas identificados e corrigidos

| Problema | Causa | Correção |
|----------|-------|----------|
| Chute de Moa travava outras skills | `TickFlashUsed` não resetado para nós `passthrough` | Resetar `TickFlashUsed = nil` após nó passthrough |
| Skills em cooldown brilhavam em combate | Valores de cooldown são `secret` no Forever → `readable=false` → `IsSpellOnCooldown` nunca bloqueia | Nova `IsSpellOnCD` não depende de `readable` |
| Armadilha Imolante não recomendava | Condition `within_8_st` exigia `targetDistance` válido (pode ser nil) | Nova condition `trap_melee_or_close` mais permissiva |

## Pendente (para quando voltar)

1. **Testar `/cfa cd` em combate com cooldown ativo**: usar Chute de Moa uma vez, esperar entrar em cooldown (8s), rodar `/cfa cd` e confirmar que mostra `remaining > 0` sem erro Lua.

2. **Corrigir `env.isPvP`** (`Modules/Hunter/Scripts.lua` linha 234): atualmente usa `module.IsPvPTarget()` (checa se alvo é jogador PvP). Deveria usar `isPvPEnvironment()` (checa `GetInstanceInfo()` para "pvp"/"arena"). Isso causa comportamento inconsistente entre PDV e BG.

3. **Validar em jogo**: Chute de Moa deve brilhar apenas quando não está em cooldown e alvo está em melee; Armadilha Imolante deve brilhar em curta distância.

4. **Registrar mudanças no histórico** (`historico/HISTORICO_MODIFICACOES.md` com ID sequencial H-XXXX).

## Comandos úteis no jogo
- `/cfa cd` — diagnóstico de cooldown do Chute de Moa
- `/cfa debug on` — ativa logs detalhados da rotação
- `/cfa status` — mostra status do módulo Hunter
- `/reload` — recarregar interface após alterações

## Local dos arquivos
- Addon: `D:\World of Warcraft\_forever_\Interface\AddOns\CombatForeverAssistant\`
- Backup: `D:\World of Warcraft\_forever_\Interface\AddOns\_backup_20261121_strider_kick_sv\`
- Progresso: `D:\World of Warcraft\_forever_\Interface\AddOns\memory\projetos\PROGRESSO_ATUAL.md`
