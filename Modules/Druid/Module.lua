-- Combat Forever Assistant — Druid module: bootstrap da tabela do módulo.
--
-- Lição do Hunter (H-0196): o módulo do Hunter É a própria tabela do addon
-- (CFA.Hunter = CFA). Isso NÃO pode se repetir no Druid: o módulo precisa de
-- uma tabela PRÓPRIA, senão sobrescreveria GetSuggestion / RotationSpecs /
-- TickFlashUsed / Suggest do Hunter (e os dois módulos quebrariam).
--
-- Solução: tabela nova + metatable {__index = addon}. Assim o módulo herda
-- tudo que já existe no core (L, Compat, BuffLib, Options, FilterAxes,
-- CheckIfSpellCastable, FlashSpell, DebuffPrint...) e sobrescreve apenas o
-- que é do Druid.
--
-- Referência canônica: addon.Druid (e _G.CFA_Druid para diagnóstico).
local addonName, addon = ...

local module = addon.Druid
if not module then
    module = {}
    addon.Druid = module
    setmetatable(module, { __index = addon })
end

-- Estado e tabelas mutáveis PRÓPRIOS. Não usar "module.X = module.X or {}"
-- aqui: por causa de __index = addon, isso reutilizaria as tabelas do Hunter.
module.RotationSpecs = {}
module.RotationPredicates = {}
module.Beliefs = { player = {}, target = {} }
module.BeliefSlot = 0
module.SuggestedUnits = {}
module.LastKnownForm = nil
module.ShapeshiftForm = nil
module.MoonkinFormActive = false
module.PressSuppress = {}
module.HooksDone = false
module.UtilitySuggestCount = {}
module.UtilityFirstSeen = {}
module.UtilityIgnore = {}
module.TickFlashUsed = nil
module.PendingSuggestion = nil

-- O Core já inicializa os SavedVariables antes do carregamento dos módulos.
module.db = addon.db
module.charDb = addon.charDb

module.classTag = "DRUID"
_G.CFA_Druid = module
