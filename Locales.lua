-- Combat Forever Assistant — Locales (EN / ptBR).
-- English is the default for non-ptBR clients. If a key is missing, enUS is used.

local _, addon = ...

addon.L = {}

local LOCALE = GetLocale and GetLocale() or "enUS"
local PT = (LOCALE == "ptBR")

local strings = {
    ["addon_loaded"]            = { en = "Combat Forever Assistant loaded. Type /cfa for options.", pt = "Combat Forever Assistant carregado. Digite /cfa para as opcoes." },
    ["slash_help"]              = { en = "Commands: /cfa (options), /cfa status, /cfa key, /cfa minimap", pt = "Comandos: /cfa (opcoes), /cfa status, /cfa key, /cfa minimap" },
    ["status_no_module"]        = { en = "No module is active for your class/spec yet.", pt = "Nenhum modulo ativo para sua classe/spec ainda." },
    ["status_module"]           = { en = "Active module: %s", pt = "Modulo ativo: %s" },

    -- Options: window
    ["opt_title"]               = { en = "Combat Forever Assistant", pt = "Combat Forever Assistant" },
    ["opt_tab_general"]         = { en = "General", pt = "Geral" },
    ["opt_tab_equipment"]        = { en = "Equipment", pt = "Equipamentos" },
    ["opt_tab_about"]           = { en = "About", pt = "Sobre" },

    -- Options: general section
    ["opt_visual_mode"]         = { en = "Button highlight", pt = "Destaque do botao" },
    ["opt_visual_circle"]       = { en = "Circle over the button", pt = "Circulo sobre o botao" },
    ["opt_visual_border"]       = { en = "Button frame (border)", pt = "Moldura no botao (borda)" },
    ["opt_border_width"]        = { en = "Border width", pt = "Largura da moldura" },
    ["opt_key_button"]          = { en = "Key button (shows the bound key)", pt = "Botao de tecla (mostra a tecla ligada)" },
    ["opt_key_button_always"]   = { en = "Always show the key button", pt = "Sempre exibir o botao de tecla" },
    ["opt_lock_key_button"]     = { en = "Lock the key button position", pt = "Travar a posicao do botao de tecla" },
    ["opt_tab_key"]             = { en = "Key button", pt = "Botao de tecla" },
    ["opt_key_size"]            = { en = "Size", pt = "Tamanho" },
    ["opt_key_font"]            = { en = "Font", pt = "Fonte" },
    ["opt_key_bg"]              = { en = "Background color", pt = "Cor de fundo" },
    ["opt_key_alpha"]           = { en = "Background transparency", pt = "Transparencia de fundo" },
    ["opt_key_text_color"]      = { en = "Text color", pt = "Cor do texto" },
    ["opt_key_reset"]           = { en = "Reset to defaults", pt = "Restaurar padroes" },
    ["opt_key_hint"]            = { en = "Drag the key button to move it.", pt = "Arraste o botao de tecla para move-lo." },
    ["opt_warn_outdated"]       = { en = "Warn about outdated ability ranks on the action bar", pt = "Avisar sobre habilidades desatualizadas na barra de acao" },
    ["opt_single_color"]        = { en = "Use a single highlight color", pt = "Usar uma cor unica de destaque" },
    ["opt_save"]                = { en = "Save Settings", pt = "Salvar Configuracoes" },
    ["opt_save_done"]           = { en = "Settings saved.", pt = "Configuracoes salvas." },
    ["opt_test"]                = { en = "Test Highlight", pt = "Testar Destaque" },

    -- Outdated rank warning
    ["outdated_warning"]        = { en = "[CFA] %s: your action bar has rank %d, but your spellbook knows rank %d.", pt = "[CFA] %s: sua barra tem o rank %d, mas seu livro de magias conhece o rank %d." },

    -- Key button
    ["key_button_no_key"]       = { en = "No key bound to the suggested button.", pt = "Nenhuma tecla ligada ao botao sugerido." },
    ["key_button_shown"]        = { en = "Key button shown.", pt = "Botao de tecla exibido." },
    ["key_button_hidden"]       = { en = "Key button hidden.", pt = "Botao de tecla oculto." },

    -- Minimap
    ["minimap_shown"]           = { en = "Minimap button shown.", pt = "Botao do minimapa exibido." },
    ["minimap_hidden"]          = { en = "Minimap button hidden.", pt = "Botao do minimapa oculto." },

    -- About
    ["about_body"]              = { en = "Combat Forever Assistant highlights the ability you should press next, based on your spec, talents, target, mana, range and combat state.\n\nIt never presses keys or casts for you.\n\nAvailable modules: Hunter and Shaman.\n\nCreated by Marcus, with Inkling 2 Small Free (OpenCode) as technology partner.", pt = "O Combat Forever Assistant destaca (/cfa) a habilidade que voce deveria usar a seguir, com base na spec, talentos, alvo, mana, alcance e estado de combate.\n\nEle nunca aperta a tecla nem conjura por voce.\n\nModulos disponiveis: Hunter e Shaman.\n\nCriado por Marcus, com Inkling 2 Small Free (OpenCode) como parceiro de tecnologia." },
    ["about_version"]           = { en = "Version", pt = "Versao" },

    -- Equipment recommendations
    ["equip_hint"]              = { en = "Choose an item for each slot, add conditions, then place that item on your action bar. CFA only highlights it.", pt = "Escolha um item por slot, adicione condicoes e coloque o item na barra. O CFA apenas destaca o botao." },
    ["equip_select_item"]       = { en = "Select item", pt = "Selecionar item" },
    ["equip_no_item"]           = { en = "(no item selected)", pt = "(nenhum item selecionado)" },
    ["equip_no_items"]          = { en = "No matching items found in equipment or bags.", pt = "Nenhum item compativel encontrado no equipamento ou nas bolsas." },
    ["equip_slot_head"]         = { en = "Head", pt = "Cabeca" },
    ["equip_slot_neck"]         = { en = "Neck", pt = "Pescoco" },
    ["equip_slot_shoulder"]     = { en = "Shoulders", pt = "Ombros" },
    ["equip_slot_shirt"]        = { en = "Shirt", pt = "Camisa" },
    ["equip_slot_chest"]        = { en = "Chest", pt = "Torso" },
    ["equip_slot_waist"]        = { en = "Waist", pt = "Cintura" },
    ["equip_slot_legs"]         = { en = "Legs", pt = "Pernas" },
    ["equip_slot_feet"]         = { en = "Feet", pt = "Pes" },
    ["equip_slot_wrist"]        = { en = "Wrist", pt = "Pulsos" },
    ["equip_slot_hands"]        = { en = "Hands", pt = "Maos" },
    ["equip_slot_finger0"]      = { en = "Ring 1", pt = "Anel 1" },
    ["equip_slot_finger1"]      = { en = "Ring 2", pt = "Anel 2" },
    ["equip_slot_trinket0"]     = { en = "Trinket 1", pt = "Berloque 1" },
    ["equip_slot_trinket1"]     = { en = "Trinket 2", pt = "Berloque 2" },
    ["equip_slot_back"]         = { en = "Back", pt = "Costas" },
    ["equip_slot_mainhand"]     = { en = "Main hand", pt = "Mao principal" },
    ["equip_slot_offhand"]      = { en = "Off hand", pt = "Mao secundaria" },
    ["equip_slot_ranged"]       = { en = "Ranged", pt = "A distancia" },
    ["equip_slot_tabard"]       = { en = "Tabard", pt = "Tabardo" },

    -- Talent-independent Hunter recommendations
    ["extra_hint"]              = { en = "Aspects are separate from the rotation. Enable the ones CFA should recommend; usage conditions are automatic.", pt = "Aspectos sao independentes da rotacao. Ative os que deseja receber; as condicoes de uso sao automaticas." },
    ["extra_aspect_cheetah"]    = { en = "Aspect of the Cheetah", pt = "Aspecto do Guepardo" },
    ["extra_aspect_pack"]       = { en = "Aspect of the Pack", pt = "Aspecto da Matilha" },
    ["extra_aspect_monkey"]     = { en = "Aspect of the Monkey", pt = "Aspecto do Macaco" },
    ["extra_aspect_beast"]      = { en = "Aspect of the Beast", pt = "Aspecto da Fera" },
    ["extra_aspect_hawk"]       = { en = "Aspect of the Hawk", pt = "Aspecto do Falcao" },
    ["shaman_tab"]              = { en = "Shaman", pt = "Shaman" },
    ["shaman_enabled"]          = { en = "Enable Shaman recommendations", pt = "Ativar recomendacoes de Shaman" },
    ["shaman_spec_header"]      = { en = "Talent tree", pt = "Arvore de talentos" },
    ["shaman_spec_auto"]        = { en = "Automatic", pt = "Automatico" },
    ["shaman_spec_ele"]         = { en = "Elemental", pt = "Elemental" },
    ["shaman_spec_enh"]         = { en = "Enhancement", pt = "Enhancement" },
    ["shaman_spec_rest"]        = { en = "Restoration (caster DPS fallback)", pt = "Restauracao (rotacao caster basica)" },
    ["shaman_rotation_hint"]    = { en = "Elemental and Enhancement use separate priorities. Restoration currently uses the caster damage fallback; healing is not automated.", pt = "Elemental e Enhancement usam prioridades proprias. Restauracao usa uma rotacao caster basica; curas nao sao recomendadas." },
    ["shaman_extra_header"]     = { en = "Extra — buffs and support", pt = "Extra — buffs e suporte" },
    ["shaman_extra_hint"]       = { en = "These can be highlighted alongside a rotation ability. CFA never casts them.", pt = "Podem brilhar junto com uma habilidade da rotacao. O CFA nao conjura por voce." },
    ["shaman_buff_lightning_shield"] = { en = "Lightning Shield", pt = "Escudo Relampejante" },
    ["shaman_buff_flametongue"] = { en = "Flametongue Weapon (Elemental/Restoration)", pt = "Arma Flametongue (Elemental/Restauracao)" },
    ["shaman_buff_windfury"]    = { en = "Windfury Weapon (Enhancement)", pt = "Arma Windfury (Enhancement)" },
    ["shaman_buff_strength"]    = { en = "Strength of Earth Totem (group support)", pt = "Totem Forca da Terra (suporte ao grupo)" },
    ["shaman_buff_mana_spring"] = { en = "Mana Spring Totem (pre-combat / low mana / long fight)", pt = "Totem Fonte de Mana (pre-combate / pouca mana / luta longa)" },

    ["rotation_error"]          = { en = "[CFA] Rotation error (see /cfa status): %s", pt = "[CFA] Erro na rotação (veja /cfa status): %s" },

    -- Suggestion reasons (colors header, for debug)
    ["reason_damage"]           = { en = "Damage", pt = "Dano" },
    ["reason_aoe"]              = { en = "AoE", pt = "Area" },
    ["reason_interrupt"]        = { en = "Interrupt", pt = "Interrupcao" },
    ["reason_defensive"]        = { en = "Defensive", pt = "Defensivo" },
    ["reason_utility"]          = { en = "Utility", pt = "Utilidade" },

    -- Welcome message (login)
    ["welcome_loaded"]          = { en = "|cff33ff99[CFA]|r Combat Forever Assistant loaded — Class: %s", pt = "|cff33ff99[CFA]|r Combat Forever Assistant carregado — Classe: %s" },
    ["welcome_spec"]            = { en = "|cff33ff99[CFA]|r Spec: %s (%s)", pt = "|cff33ff99[CFA]|r Spec: %s (%s)" },
    ["spec_bm"]                 = { en = "Beast Mastery", pt = "Feras" },
    ["spec_mm"]                 = { en = "Marksmanship", pt = "Precisão" },
    ["spec_sv"]                 = { en = "Survival", pt = "Sobrevivência" },
    ["bless_bm"]                 = { en = "|cFFFF8000Beast Mastery:|r Your bond with your pet is your greatest weapon! Destroy them!", pt = "|cFFFF8000Mestre das Feras:|r O vínculo com seu pet é sua maior arma! Destrua-os!" },
    ["bless_mm"]                 = { en = "|cFF69CCF0Marksmanship:|r Deadly precision from miles away! Fire upon them!", pt = "|cFF69CCF0Atirador de Elite:|r Precisão mortal a quilômetros de distância! Fogo neles!" },
    ["bless_sv"]                 = { en = "|cFFABD473Survival:|r Master of traps and venom! Prepare the ambush!", pt = "|cFFABD473Sobrevivência:|r Mestre das armadilhas e do veneno! Prepare a emboscada!" },
    ["bless_low"]                = { en = "|cFFCCCCCCRecruit Hunter:|r Learning the ways of the wild... Survive!", pt = "|cFFCCCCCCRecruta Hunter:|r Aprendendo os caminhos da selva... Sobreviva!" },
    ["welcome_race"]            = { en = "|cff33ff99[CFA]|r %s", pt = "|cff33ff99[CFA]|r %s" },
    ["race_human"]              = { en = "Humans never quit.", pt = "Humanos nunca desistem." },
    ["race_dwarf"]              = { en = "Dwarves stand like stone.", pt = "Anões firmes como pedra." },
    ["race_nightelf"]           = { en = "The moon watches over you.", pt = "A lua vela por você." },
    ["race_gnome"]              = { en = "A gnome's genius at work.", pt = "A genialidade gnoma em ação." },
    ["race_orc"]                = { en = "For the Horde!", pt = "Pela Horda!" },
    ["race_undead"]             = { en = "Death is only the beginning.", pt = "A morte é só o começo." },
    ["race_tauren"]             = { en = "For the Earth Mother!", pt = "Pela Mãe Terra!" },
    ["race_troll"]              = { en = "Troll blood boils!", pt = "Sangue de troll ferve!" },
    ["race_highorder"]          = { en = "The High Order walks the ley lines.", pt = "A Alta Ordem segue as linhas de ley." },
    ["race_windshaper"]         = { en = "The Windshapers ride the wind.", pt = "Os Windshapers cavalgam o vento." },

    -- Rotation editor: cards, conditions, picker
    ["rot_click_test"]          = { en = "Click to test the flash on your bars.", pt = "Clique para testar o flash na barra." },
    ["rot_not_known"]           = { en = "|cff33ff99[CFA]|r You don't know this spell yet.", pt = "|cff33ff99[CFA]|r Você não conhece esta magia ainda." },
    ["rot_not_on_bar"]          = { en = "|cff33ff99[CFA]|r That spell is not on your action bars.", pt = "|cff33ff99[CFA]|r Essa magia não está na sua barra de ação." },
    ["rot_add_condition"]       = { en = "Add condition", pt = "Adicionar condição" },
    ["rot_remove_condition"]    = { en = "Remove condition", pt = "Remover condição" },
    ["rot_always"]              = { en = "Always", pt = "Sempre" },
    ["rot_special_header"]      = { en = "Special predicate", pt = "Predicado especial" },
    ["rot_clear_all"]           = { en = "Remove all conditions", pt = "Remover todas as condições" },
    ["rot_none_active"]         = { en = "(no condition active)", pt = "(nenhuma condição ativa)" },
    ["rot_no_condition"]        = { en = "- no conditions -", pt = "- sem condições -" },
    ["rot_conditions_prefix"]   = { en = "Conditions: ", pt = "Condições: " },
    ["rot_special_prefix"]      = { en = "Special: ", pt = "Especial: " },

    -- Filter axes (headers) + options
    ["rot_axis_combat"]         = { en = "1. Combat", pt = "1. Combate" },
    ["rot_axis_env"]            = { en = "2. Environment", pt = "2. Ambiente" },
    ["rot_axis_target"]         = { en = "3. Target", pt = "3. Alvo" },
    ["rot_axis_range"]          = { en = "4. Range", pt = "4. Alcance" },
    ["rot_axis_resource"]       = { en = "5. Resource", pt = "5. Recurso" },
    ["rot_axis_aoe"]            = { en = "6. Area", pt = "6. Área" },
    ["axis_both"]               = { en = "Both", pt = "Ambos" },
    ["axis_any"]                = { en = "Any", pt = "Qualquer" },
    ["axis_in_combat"]          = { en = "In combat", pt = "Em combate" },
    ["axis_out_combat"]         = { en = "Out of combat", pt = "Fora de combate" },
    ["axis_attackable"]         = { en = "Attackable enemy", pt = "Inimigo atacável" },
    ["axis_casting"]            = { en = "Target casting", pt = "Alvo conjurando" },
    ["axis_no_attack"]          = { en = "No attackable target", pt = "Sem alvo atacável" },
    ["axis_ranged"]             = { en = "Ranged", pt = "Ranged" },
    ["axis_melee"]              = { en = "Melee", pt = "Melee" },
    ["axis_dead_zone"]          = { en = "Dead zone", pt = "Zona morta" },
    ["axis_mana15"]             = { en = "Mana > 15%", pt = "Mana > 15%" },
    ["axis_mana40"]             = { en = "Mana > 40%", pt = "Mana > 40%" },
    ["axis_mana50"]             = { en = "Mana > 50%", pt = "Mana > 50%" },
    ["axis_rage40"]             = { en = "Rage >= 40", pt = "Raiva >= 40" },
    ["axis_energy40"]           = { en = "Energy >= 40", pt = "Energia >= 40" },
    ["axis_combo5"]             = { en = "Combo points >= 5", pt = "Pontos de combo >= 5" },
    ["axis_aoe_2"]              = { en = "AoE (2+)", pt = "Área (2+)" },
    ["axis_single"]             = { en = "Single target", pt = "Alvo único" },
}

for key, pair in pairs(strings) do
    addon.L[key] = PT and pair.pt or pair.en
end
