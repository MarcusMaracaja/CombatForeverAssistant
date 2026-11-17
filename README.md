# Combat Forever Assistant

> **[English](#english)** · **[Português (ptBR)](#português-ptbr)**

---

## English

Rotation assistant for **WoW Forever** (Interface `16001`, vanilla content on a modern
engine). When a class module suggests an ability, the addon highlights the
action-bar button that ability is bound to — with colors per function (damage, AoE,
interrupt, defensive, utility) or a single user-chosen color.

It does **not** press the key for you — it only highlights the button. You stay in
control.

### Status — early development, **not playable yet**

| Area | State |
|---|---|
| Addon loads, `/cfa` menu (General / Key button / About) | Working (tested in game) |
| Highlight: **circle** or **border** modes | Working (tested in game) |
| Border width slider (0–60 px), single-color option, per-function colors | Working (tested in game) |
| Key button (draggable widget showing the bound key, lock option, "always show", 6 fonts, size, background/text color, transparency, reset) | Working (tested in game) |
| **Buff library** (`CFA.BuffLib`) — all 9 vanilla classes, all ranks, aura/cast IDs, tier tracking, "outdated buff" flags | Implemented, data verified via wowhead classic/classicdb/wiki — **not yet verified in game** |
| Class modules (Hunter, Shaman, Warrior, Druid, Paladin) | **Not implemented yet** — zero rotation logic shipped so far |
| Visual rotation editor | Planned (Phase 3) |

> **Saved variables:** on the current Forever client, `/reload` does **not** flush addon
> SavedVariables. Settings only persist when you **fully exit the client**. This affects
> every configuration change made in the menu.

### Highlight modes (no glow, ever)

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

### Status — desenvolvimento inicial, **ainda não jogável**

| Área | Estado |
|---|---|
| Addon carrega, menu `/cfa` (Geral / Botão de tecla / Sobre) | Funcionando (testado em jogo) |
| Destaque: **círculo** ou **moldura** | Funcionando (testado em jogo) |
| Slider de largura da moldura (0–60 px), cor única, cores por função | Funcionando (testado em jogo) |
| Botão de tecla (widget arrastável mostrando a tecla, trava, "sempre exibir", 6 fontes, tamanho, cor de fundo/texto, transparência, restaurar padrões) | Funcionando (testado em jogo) |
| **Biblioteca de buffs** (`CFA.BuffLib`) — as 9 classes vanilla, todos os ranks, IDs de aura/cast, tiers, aviso de buff desatualizado | Implementada, dados verificados via wowhead classic/classicdb/wiki — **ainda não verificada em jogo** |
| Módulos de classe (Hunter, Shaman, Warrior, Druid, Paladin) | **Ainda não implementados** — zero rotação no pacote |
| Editor visual de rotação | Planejado (Fase 3) |

> **Variáveis salvas:** no cliente Forever atual, `/reload` **não** despeja as
> SavedVariables. As configurações só persistem quando você **sai completamente do jogo**.
> Isso vale para toda mudança feita no menu.

### Modos de destaque (sem glow, nunca)

- **Círculo** — anel segmentado colorido em volta do botão (texturas nativas).
- **Moldura** — moldura colorida em volta do botão (4 barras, 0–60 px de largura).

### Instalação

Copie a pasta `CombatForeverAssistant` para `Interface\AddOns\` e digite `/cfa`.

### Requisitos

WoW Forever, Interface **16001**. Sem dependências externas.

### Licença

[MIT](LICENSE) — © 2026 Marcus. Veja `LICENSE`.
