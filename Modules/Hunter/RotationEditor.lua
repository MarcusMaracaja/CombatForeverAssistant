-- Combat Forever Assistant — Hunter module: editor de rotação (shim).
--
-- A janela em si é GENÉRICA (Modules/Shared/RotationEditor.lua) — o mesmo
-- código serve para o Hunter e para o Druid. Aqui só informamos:
--   * o prefixo dos frames globais (evita colisão entre classes);
--   * o título da janela;
--   * as abas (as specs do Hunter);
--   * a spec inicial (usada se a detecção falhar).
--
-- Os overrides por personagem ficam em charDb.hunterRotation / charDb.hunterOrder
-- (ver Modules/Shared/RotationStore.lua).
local moduleName, module = ...

local addon = _G.CFA
if not addon or type(addon.CreateRotationEditor) ~= "function" then return end

local editor = addon:CreateRotationEditor(module, {
    frameName = "CFA_HunterRotationEditor",
    scrollName = "CFA_HunterRotationEditorScroll",
    pickerName = "CFA_HunterRotationPicker",
    title = "Editor de rotação — Hunter",
    tabs = {
        { "BM", "Beast Mastery" },
        { "MM", "Marksmanship" },
        { "SV", "Survival" },
    },
    defaultSpec = "SV",
})

if editor then
    module.OpenRotationEditor = editor.Open
end
