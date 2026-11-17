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
    ["opt_tab_about"]           = { en = "About", pt = "Sobre" },

    -- Options: general section
    ["opt_visual_mode"]         = { en = "Button highlight", pt = "Destaque do botao" },
    ["opt_visual_circle"]       = { en = "Circle over the button", pt = "Circulo sobre o botao" },
    ["opt_visual_border"]       = { en = "Button frame (border)", pt = "Moldura no botao (borda)" },
    ["opt_border_width"]        = { en = "Border width", pt = "Largura da moldura" },
    ["opt_key_button"]          = { en = "Key button (shows the bound key)", pt = "Botao de tecla (mostra a tecla ligada)" },
    ["opt_warn_outdated"]       = { en = "Warn about outdated ability ranks on the action bar", pt = "Avisar sobre habilidades desatualizadas na barra de acao" },
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
    ["about_body"]              = { en = "Combat Forever Assistant highlights the ability you should press next, based on your spec, talents, target, mana, range and combat state.\n\nIt never presses keys or casts for you.\n\nModules: Hunter, Shaman, Warrior, Druid, Paladin.\n\nCreated by Marcus, with Inkling 2 Small Free (OpenCode) as technology partner.", pt = "O Combat Forever Assistant destaca (/cfa) a habilidade que voce deveria usar a seguir, com base na spec, talentos, alvo, mana, alcance e estado de combate.\n\nEle nunca aperta a tecla nem conjura por voce.\n\nModulos: Hunter, Shaman, Warrior, Druid, Paladin.\n\nCriado por Marcus, com Inkling 2 Small Free (OpenCode) como parceiro de tecnologia." },

    -- Suggestion reasons (colors header, for debug)
    ["reason_damage"]           = { en = "Damage", pt = "Dano" },
    ["reason_aoe"]              = { en = "AoE", pt = "Area" },
    ["reason_interrupt"]        = { en = "Interrupt", pt = "Interrupcao" },
    ["reason_defensive"]        = { en = "Defensive", pt = "Defensivo" },
    ["reason_utility"]          = { en = "Utility", pt = "Utilidade" },
}

for key, pair in pairs(strings) do
    addon.L[key] = PT and pair.pt or pair.en
end
