-- Combat Forever Assistant — Druid module: editor de rotação (shim).
--
-- A janela em si é GENÉRICA (Modules/Shared/RotationEditor.lua) — o mesmo
-- código do Hunter. Aqui só informamos as abas (as formas/specs do Druid) e
-- o prefixo dos frames.
--
-- Os overrides por personagem ficam em charDb.druidRotation / charDb.druidOrder.
local addonName, addon = ...
local module = addon.Druid

if not addon or type(addon.CreateRotationEditor) ~= "function" then return end

function module.ResolveRotationEditorSpec()
    local env = module:BuildEnv()
    local _, rotationKey = module:PickRotation(env)
    if rotationKey and module.RotationSpecs[rotationKey] then return rotationKey end
    local spec = module:DetectSpec()
    if spec and module.RotationSpecs[spec] then return spec end
    return "SELF"
end

local editor = addon:CreateRotationEditor(module, {
    frameName = "CFA_DruidRotationEditor",
    scrollName = "CFA_DruidRotationEditorScroll",
    pickerName = "CFA_DruidRotationPicker",
    title = "Editor de rotação — Druid",
    tabs = {
        { "CAT", "Gato" },
        { "BEAR", "Urso" },
        { "BAL", "Equilíbrio" },
        { "REST", "Restauração" },
        { "SELF", "Auto-buffs" },
    },
    defaultSpec = "CAT",
    resolveSpec = function()
        return module.ResolveRotationEditorSpec()
    end,
})

if editor then
    module.OpenRotationEditor = editor.Open
end
