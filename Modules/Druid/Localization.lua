-- Combat Forever Assistant — Druid module: textos (EN / ptBR).
--
-- O L do Druid é uma tabela própria que HERDA as chaves do core (rot_axis_*,
-- axis_*, rot_click_test...) e pode sobrescrever com textos do módulo.
-- Assim o editor de rotação compartilhado encontra tudo o que precisa.
local addonName, addon = ...
local module = addon.Druid

-- rawget evita herdar a tabela L do Core: as traduções druid_* precisam
-- ficar isoladas das traduções do Hunter e do addon principal.
local DL = rawget(module, "L")
if type(DL) ~= "table" then
    DL = setmetatable({}, { __index = addon.L })
    module.L = DL
end

local LOCALE = GetLocale and GetLocale() or "enUS"
local PT = (LOCALE == "ptBR")

local strings = {
    -- Aba / status
    ["druid_tab"]             = { en = "Druid", pt = "Druid" },
    ["druid_enable"]          = { en = "Enable Druid rotation", pt = "Habilitar rotação do Druid" },
    ["druid_spec_header"]     = { en = "Spec", pt = "Spec" },
    ["druid_spec_auto"]       = { en = "Automatic (talents / abilities)", pt = "Automático (talentos / habilidades)" },
    ["druid_spec_feral"]      = { en = "Feral (Cat / Bear)", pt = "Feral (Gato / Urso)" },
    ["druid_spec_balance"]    = { en = "Balance", pt = "Equilíbrio" },
    ["druid_spec_restoration"]= { en = "Restoration", pt = "Restauração" },
    ["druid_rotation_header"] = { en = "Rotation", pt = "Rotação" },
    ["druid_open_editor"]     = { en = "Open rotation editor", pt = "Abrir editor de rotação" },
    ["druid_editor_hint"]     = { en = "The editor shows the abilities of your spec / form and lets you toggle each one (per character).",
                                   pt = "O editor mostra as habilidades da sua spec / forma e permite ligar/desligar cada uma (por personagem)." },

    -- Formas
    ["druid_form_cat"]        = { en = "Cat Form", pt = "Forma de Gato" },
    ["druid_form_bear"]       = { en = "Bear Form", pt = "Forma de Urso" },
    ["druid_form_caster"]     = { en = "Caster / Moonkin", pt = "Conjurador / Lua" },
    ["druid_form_moonkin"]    = { en = "Moonkin Form", pt = "Forma de Lua" },

    -- Editor: abas
    ["druid_tab_cat"]         = { en = "Cat Form", pt = "Gato" },
    ["druid_tab_bear"]        = { en = "Bear Form", pt = "Urso" },
    ["druid_tab_balance"]     = { en = "Balance", pt = "Equilíbrio" },
    ["druid_tab_restoration"] = { en = "Restoration", pt = "Restauração" },
    ["druid_tab_self"]        = { en = "Self-buffs", pt = "Auto-buffs" },
}

for key, pair in pairs(strings) do
    DL[key] = PT and pair.pt or pair.en
end
