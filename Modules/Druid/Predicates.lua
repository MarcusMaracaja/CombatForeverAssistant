-- Combat Forever Assistant — Druid module: predicados da rotação.
--
-- Cada predicado responde "este nó deve piscar?" a partir do (env).
-- Os nomes são referenciados pelos dados em Scripts_CAT/BEAR/BAL/REST/SELF.
--
-- Nota de paridade: o modelo clean-room usava "MyDebuff"/"Debuff" dentro da função de
-- castabilidade. No CFA isso NÃO funciona em combate (as auras são secretas
-- e o gate do Core reprovaria sempre) -> a verificação de debuff mora aqui,
-- com CRENÇA do próprio cast (ver Functions.lua).
local addonName, addon = ...
local module = addon.Druid

module.RotationPredicates = module.RotationPredicates or {}
local P = module.RotationPredicates

local function hasActiveEnemy(env) return env.hasActiveEnemy and true or false end

P["always"] = { fn = function(env) return true end }

P["has_enemy"] = { fn = function(env) return hasActiveEnemy(env) end }

-- AoE + inimigo. No modelo clean-room esse predicado NÃO existia (a condição "aoe_and_enemy"
-- ficava sem definição e passava sempre). Aqui ele é real, mas com
-- fail-open: sem detector de AoE disponível (env.aoeKnown == false) ele
-- passa, para não deixar o Urso sem Suggestions por falta de plugin externo.
P["aoe_and_enemy"] = {
    fn = function(env)
        if not env.hasActiveEnemy then return false end
        if env.aoeKnown then return env.isAoE and true or false end
        return true
    end,
}

P["not_cat_form"] = { fn = function(env) return env.form == module.FORM_CASTER and true or false end }

P["cat_form"] = { fn = function(env) return env.form == module.FORM_CAT and true or false end }

P["bear_form"] = { fn = function(env) return env.form == module.FORM_BEAR and true or false end }

P["not_moonkin"] = {
    fn = function(env) return (not env.isMoonkin) and true or false end,
}

P["target_casting"] = { fn = function(env) return env.targetCasting and true or false end }

P["target_interruptible"] = {
    fn = function(env) return env.targetInterruptible and true or false end,
}

P["behind"] = {
    -- Ver Functions.lua: o cliente não expõe a direção do modelo, então a
    -- condição é inerte (igual no modelo clean-room).
    fn = function(env) return module.IsBehindTarget() and true or false end,
}

P["combo5"] = { fn = function(env) return (env.combo or 0) >= 5 and true or false end }

P["energy40"] = { fn = function(env) return (env.energy or 0) >= 40 and true or false end }

P["my_hp35"] = { fn = function(env) return (env.myHP or 100) < 35 and true or false end }

P["pounce_condition"] = {
    fn = function(env)
        return env.form == module.FORM_CAT and (env.energy or 0) >= 40 and not env.isPvP and true or false
    end,
}

-- ---------------------------------------------------------------------------
-- Self-buffs (utilidade): só fora de Gato/Urso, nunca montado.
-- ---------------------------------------------------------------------------
P["mark_missing"] = {
    fn = function(env)
        if env.form == module.FORM_CAT or env.form == module.FORM_BEAR then return false end
        if env.mounted then return false end
        if env.targetExists and env.targetFriendlyAlive then
            -- Aliado selecionado: buff na unidade efetiva.
            return not module.IsBuffUp("target", 1126)
        end
        -- Sem alvo ou alvo hostil/desconhecido: buff no próprio jogador.
        return not module.IsBuffUp("player", 1126)
    end,
}

P["thorns_missing"] = {
    fn = function(env)
        if env.form == module.FORM_CAT or env.form == module.FORM_BEAR then return false end
        if env.mounted then return false end
        if env.targetExists and env.targetFriendlyAlive then
            return not module.IsBuffUp("target", 467)
        end
        return not module.IsBuffUp("player", 467)
    end,
}

P["enred_missing"] = {
    fn = function(env)
        if env.mounted then return false end
        return not module.IsBuffUp("player", 16689)
    end,
}

P["demoralizing_roar_missing"] = {
    fn = function(env)
        if env.form ~= module.FORM_BEAR then return false end -- Rugido só em Urso
        if not env.hasActiveEnemy then return false end
        if module.IsDebuffUp("target", 99) then return false end
        return true
    end,
}

-- ---------------------------------------------------------------------------
-- Debuffs da rotação de caster (Balance)
-- ---------------------------------------------------------------------------
P["insect_swarm_missing"] = {
    fn = function(env) return not module.IsDebuffUp("target", 5570) end,
}

P["moonfire_missing"] = {
    fn = function(env) return not module.IsDebuffUp("target", 8921) end,
}

-- ---------------------------------------------------------------------------
-- Rótulos para o editor de rotação (bilingue)
-- ---------------------------------------------------------------------------
local LOCALE = GetLocale and GetLocale() or "enUS"
local PTBR = (LOCALE == "ptBR")
local function LBL(pt, en) return PTBR and pt or en end

local LABELS = {
    always                 = LBL("Sempre", "Always"),
    has_enemy              = LBL("Com inimigo", "With enemy"),
    aoe_and_enemy          = LBL("Área com inimigo", "AoE with enemy"),
    not_cat_form           = LBL("Forma de conjurador", "Caster form"),
    cat_form               = LBL("Forma de gato", "Cat form"),
    bear_form              = LBL("Forma de urso", "Bear form"),
    not_moonkin            = LBL("Não é lua", "Not moonkin"),
    target_casting         = LBL("Alvo conjurando", "Target casting"),
    target_interruptible   = LBL("Alvo conjurando interrompível", "Target casting interruptible"),
    behind                 = LBL("Atrás do alvo", "Behind the target"),
    combo5                 = LBL("5 pontos de combo", "5 combo points"),
    energy40               = LBL("Energia >= 40", "Energy >= 40"),
    my_hp35                = LBL("Meu HP < 35%", "My HP < 35%"),
    pounce_condition       = LBL("Gato, energia >= 40, fora de PvP", "Cat, energy >= 40, not PvP"),
    mark_missing           = LBL("Sem Marca da Selva", "No Mark of the Wild"),
    thorns_missing         = LBL("Sem Espinhos", "No Thorns"),
    enred_missing          = LBL("Sem Garras da Natureza", "No Nature's Grasp"),
    demoralizing_roar_missing = LBL("Sem Rugido Demoralizador", "No Demoralizing Roar"),
    insect_swarm_missing   = LBL("Sem Enxame de Insetos", "No Insect Swarm"),
    moonfire_missing       = LBL("Sem Lua de Fogo", "No Moonfire"),
}
for key, label in pairs(LABELS) do
    if P[key] then P[key].label = label end
end
