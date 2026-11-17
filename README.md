# Combat Forever Assistant

> **[English](#english)** · **[Português (ptBR)](#português-ptbr)**

---

## English

Rotation assistant for **WoW Forever** (Interface `16001`, vanilla content on a modern
engine). Every 0.2 s the addon evaluates your spec, talents, target, mana, range and
combat state — and **highlights the action-bar button for the ability you should use
right now**, with colors per function (damage, AoE, interrupt, defensive, utility).

It does **not** press the key for you — it only highlights the button. You stay in
control.

### Highlight modes (no glow, ever)

- **Circle over the button** — a colored ring drawn on the recommended button.
- **Button frame (border)** — a colored frame around the recommended button
  (configurable border width, 0–60 px).

### Features

- Visual rotation editor per character (`/cfa`): enable/disable nodes, reorder
  priorities, add conditions per ability.
- **Buff library** (`CFA.BuffLib`) queried by rotation rules: knows the buff spell IDs
  for every vanilla class with all ranks, and tells a module whether the player/target
  already has a buff, at which tier, and whether it is outdated.
- Key button: small draggable widget showing the key bound to the recommended ability.
- Outdated-rank warnings on the action bar at login (toggleable).
- Bilingual: English / Português (ptBR) — auto-detected from the client locale.

### Status

Early development (0.1.0). Not yet tested in game. Modules are being rebuilt for all
supported classes: Hunter, Shaman, Warrior, Druid, Paladin.

### Installation

Copy the `CombatForeverAssistant` folder into `Interface\AddOns\` and type `/cfa`.

### Requirements

- WoW Forever, Interface **16001**. No external dependencies.

### License

[MIT](LICENSE) — © 2026 Marcus. See `LICENSE`.

---

## Português (ptBR)

Assistente de rotação para o **WoW Forever** (Interface `16001`, conteúdo vanilla em
engine moderna). A cada 0,2 s o addon avalia sua spec, talentos, alvo, mana, alcance e
estado de combate — e **destaca o botão da barra de ação da habilidade que você deveria
usar agora**, com cores por função (dano, área, interrupção, defensivo, utilidade).

Ele **não** aperta a tecla por você — apenas destaca o botão. Você continua no controle.

### Modos de destaque (sem glow, nunca)

- **Círculo sobre o botão** — anel colorido desenhado no botão recomendado.
- **Moldura no botão (borda)** — moldura colorida ao redor do botão recomendado
  (largura configurável, 0–60 px).

### Recursos

- Editor visual de rotação por personagem (`/cfa`): liga/desliga nós, reordena
  prioridades, adiciona condições por habilidade.
- **Biblioteca de buffs** (`CFA.BuffLib`) consultada pelas regras de rotação: conhece
  os IDs de buff de todas as classes vanilla com todos os ranks, e informa ao módulo
  se o jogador/alvo já tem o buff, em qual tier, e se está desatualizado.
- Botão de tecla: widget pequeno e arrastável mostrando a tecla ligada à habilidade
  recomendada.
- Aviso de rank desatualizado na barra ao logar (desligável).
- Bilíngue: Inglês / Português (ptBR) — detectado pelo locale do cliente.

### Status

Desenvolvimento inicial (0.1.0). Ainda não testado em jogo. Os módulos estão sendo
refeitos para todas as classes suportadas: Hunter, Shaman, Warrior, Druid, Paladin.

### Instalação

Copie a pasta `CombatForeverAssistant` para `Interface\AddOns\` e digite `/cfa`.

### Requisitos

- WoW Forever, Interface **16001**. Sem dependências externas.

### Licença

[MIT](LICENSE) — © 2026 Marcus. Veja `LICENSE`.
