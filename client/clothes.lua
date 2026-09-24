local RSGCore = exports['rsg-core']:GetCoreObject()
local ClothingCamera = nil
local c_zoom = 2.4
local c_offset = -0.15
local Outfits_tab = {}
local clothing = require 'data.clothing'

local BODY_CATEGORY_MAP = {
    shirts_full = "BODIES_UPPER",
    coats = "BODIES_UPPER",
    coats_closed = "BODIES_UPPER",
    vests = "BODIES_UPPER",
    ponchos = "BODIES_UPPER",
    cloaks = "BODIES_UPPER",
    suspenders = "BODIES_UPPER",
    loadouts = "BODIES_UPPER",
    armor = "BODIES_UPPER",
    pants = "BODIES_LOWER",
    chaps = "BODIES_LOWER",
    skirts = "BODIES_LOWER",
    boots = "BODIES_LOWER",
    spats = "BODIES_LOWER",
    boot_accessories = "BODIES_LOWER",
    leg_attachments = "BODIES_LOWER",
}

function EnsureBareBody(category)
    local ped = PlayerPedId()
    local gender = IsPedMale(ped) and "male" or "female"

    for _, bodyPart in ipairs({ "BODIES_UPPER", "BODIES_LOWER" }) do
        local hash = GetBodyFallbackHash(bodyPart)
        if hash then
            Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, tonumber(hash), false, true, true)
        end
    end

    for cat, v in pairs(ClothesCache) do
        local hash
        if type(v) == "table" then
            local model, texture = tonumber(v.model) or 0, tonumber(v.texture) or 1
            if model > 0 then
                local m = clothing[gender][cat] and clothing[gender][cat][model]
                hash = m and (m[texture] or m[1]) and (m[texture] or m[1]).hash
            elseif v.hash and v.hash ~= 0 then
                hash = v.hash
            end
        end
        if hash then
            NativeSetPedComponentEnabledClothes(ped, tonumber(hash), false, true, true)
            if type(v) == "table" and v.palette then
                NativeSetTextureOutfitTints(ped, joaat(cat), v.palette, v.tint0, v.tint1, v.tint2)
            end
        end
    end
    NativeUpdatePedVariation(ped)
end

function GetBodyFallbackHash(name)
    if (IsInCharCreation or Skinkosong) and CreatorCache and CreatorCache.skin_tone then
        local comps = IsPedMale(PlayerPedId()) and ComponentsMale or ComponentsFemale
        local bodySize = math.min(6, math.max(1, tonumber(CreatorCache.body_size) or 1))
        local skinTone = math.min(6, math.max(1, tonumber(CreatorCache.skin_tone) or 1))
        local idx = GetSkinColorFromBodySize(bodySize, skinTone)
        if comps[name] and idx and comps[name][idx] then return comps[name][idx] end
    end
    local hash = exports['rsg-character']:GetBodyCurrentComponentHash(name)
    if not hash then
        local comps = IsPedMale(PlayerPedId()) and ComponentsMale or ComponentsFemale
        hash = comps[name] and comps[name][1]
    end
    return hash
end
local CurrentPrice = 0
local CurentCoords = {}
local playerHeading = nil
local RoomPrompts = GetRandomIntInRange(0, 0xffffff)
local Divider = "<img style='margin-top: 10px;margin-bottom: 10px; margin-left: -10px;'src='nui://rsg-character/img/divider_line.png'>"
local image = "<img style='max-height:250px;max-width:250px;float: center;'src='nui://rsg-character/img/%s.png'>"

local hashToCache = require 'client.hashtocache'

exports('IsCothingActive', function()
    return LocalPlayer.state.inClothingStore
end)

CreateThread(function()
    for _,v in pairs(RSG.SetDoorState) do
        Citizen.InvokeNative(0xD99229FE93B46286, v.door, 1, 1, 0, 0, 0, 0)
        DoorSystemSetDoorState(v.door, v.state)
    end
end)

function GetDescriptionLayout(value, price)
    local desc = image:format(value.img) .. "<br><br>" .. value.desc .. "<br><br>" .. Divider ..
        "<br><span style='font-family:crock; float:left; font-size: 22px;'>" ..
        RSG.Label.total .. " </span><span style='font-family:crock;float:right; font-size: 22px;'>$" ..
        (price or CurrentPrice) .. "</span><br>" .. Divider
    return desc
end

function OpenClothingMenu()
    UI.CloseAll()
    local elements = {}

    for v, k in pairsByKeys(RSG.MenuElements) do
        elements[#elements + 1] = { label = k.label or v, value = v, category = v, desc = image:format(v) .. "<br><br>" .. Divider .. "<br> " .. locale('clothing_menu.category_desc'), }
    end
    elements[#elements + 1] = { label = locale('clothing_menu.remove_all.label'), value = "remove_all", desc = locale('clothing_menu.remove_all.desc'), danger = true }
    if not (IsInCharCreation or Skinkosong) then
        local descLayout = GetDescriptionLayout({ img = "menu_icon_tick", desc = locale('clothing_menu.confirm_purhcase') })
        elements[#elements + 1] = { label = RSG.Label.save, value = "save", desc = descLayout }
    end
    UI.Open('default', GetCurrentResourceName(), 'clothing_store_menu',
        { title = RSG.Label.clothes, subtext = RSG.Label.options, align = 'top-left', elements = elements, itemHeight = "4vh"},
        function(data, menu)
            if data.current.value == "remove_all" then
                local alert = UI.alertDialog({
                    header = locale('clothing_menu.remove_all.confirm'),
                    centered = true,
                    cancel = true,
                })
                if alert == 'confirm' then RemoveAllClothes() end
                return OpenClothingMenu()
            elseif data.current.value ~= "save" then
                OpenCateogry(data.current.value)
            else
                menu.close()
                destory()
                local alert = UI.alertDialog({
                    header = locale('save_outfit_1'),
                    centered = true,
                    cancel = true,
                })
                if alert == 'confirm' then
                    local input = UI.inputDialog(locale('save_outfit_2_header'), {
                        {
                            type = 'input',
                            label = locale('save_outfit_2_input_label'),
                            required = true,
                        },
                    })
                    local ClothesHash = ConvertCacheToHash(ClothesCache)
                    local isMale = IsPedMale(PlayerPedId())
                    if input and input[1] then
                        TriggerServerEvent("rsg-character:server:saveOutfit", ClothesHash, isMale, input[1])
                    else
                        TriggerServerEvent("rsg-character:server:saveOutfit", ClothesHash, isMale)
                    end
                    if next(CurentCoords) == nil then
                        CurentCoords = RSG.Zones1[1]
                    end
                    TeleportAndFade(CurentCoords.quitcoords, true)
                    Wait(1000)
                    ExecuteCommand('loadskin')
                else
                    local str = Citizen.InvokeNative(0xFA925AC00EB830B9, 10, "LITERAL_STRING", locale('clothing_menu.category_desc'), Citizen.ResultAsLong())
                    Citizen.InvokeNative(0xFA233F8FE190514C, str)
                    Wait(100)
                    GenerateMenu()
                end
            end
        end, function(data, menu)
            if (IsInCharCreation or Skinkosong) then
                menu.close()
                FirstMenu()
            else
                menu.close()
                destory()
                if next(CurentCoords) == nil then
                    CurentCoords = RSG.Zones1[1]
                end
                TeleportAndFade(CurentCoords.quitcoords, true)
                Wait(1000)
                ExecuteCommand('loadskin')
            end
        end)
end

function OpenCateogry(menu_catagory)
    UI.CloseAll()
    local elements = {}
    if IsPedMale(PlayerPedId()) then
        local a = 1
        for v, k in pairsByKeys(RSG.MenuElements[menu_catagory].category) do
            if clothing["male"][k] ~= nil then
                local category = clothing["male"][k]
                if ClothesCache[k] == nil or type(ClothesCache[k]) ~= "table" then
                    ClothesCache[k] = {}
                    ClothesCache[k].model = 0
                    ClothesCache[k].texture = 1
                end
                elements[#elements + 1] = {
                    label = (RSG.Label[k] and (RSG.Price[k] .. "$ " .. RSG.Label[k])) or (RSG.Price[k] .. "$ " .. v),
                    value = ClothesCache[k].model or 0,
                    category = k,
                    group = k,
                    showCount = true,
                    desc = "",
                    type = "slider",
                    min = 0,
                    max = #category,
                    change_type = "model",
                    id = a
                }
                a = a + 1
                elements[#elements + 1] = {
                    label = (RSG.Label[k] and (RSG.Label.color .. RSG.Label[k])) or (RSG.Label.color .. v),
                    value = ClothesCache[k].texture or 1,
                    category = k,
                    group = k,
                    showCount = true,
                    desc = "",
                    type = "slider",
                    min = 1,
                    max = GetMaxTexturesForModel(k, ClothesCache[k].model or 1, true),
                    change_type = "texture",
                    id = a
                }
                a = a + 1
            end
        end
    else
        local a = 1
        for v, k in pairsByKeys(RSG.MenuElements[menu_catagory].category) do
            if clothing["female"][k] ~= nil then
                local category = clothing["female"][k]
                if ClothesCache[k] == nil or type(ClothesCache[k]) ~= "table" then
                    ClothesCache[k] = {}
                    ClothesCache[k].model = 0
                    ClothesCache[k].texture = 0
                end
                elements[#elements + 1] = {
                    label = (RSG.Label[k] and (RSG.Price[k] .. "$ " .. RSG.Label[k])) or (RSG.Price[k] .. "$ " .. v),
                    value = ClothesCache[k].model or 0,
                    category = k,
                    group = k,
                    showCount = true,
                    desc = "",
                    type = "slider",
                    min = 0,
                    max = #category,
                    change_type = "model",
                    id = a
                }
                a = a + 1
                elements[#elements + 1] = {
                    label = (RSG.Label[k] and (RSG.Label.color .. RSG.Label[k])) or (RSG.Label.color .. v),
                    value = ClothesCache[k].texture or 1,
                    category = k,
                    group = k,
                    showCount = true,
                    desc = "",
                    type = "slider",
                    min = 1,
                    max = GetMaxTexturesForModel(k, ClothesCache[k].model or 1, true),
                    change_type = "texture",
                    id = a
                }
                a = a + 1
            end
        end
    end
    UI.Open('default', GetCurrentResourceName(), 'clothing_store_menu_category',
        {title = RSG.Label.clothes, subtext = RSG.Label.options, align = 'top-left', elements = elements, itemHeight = "4vh"}, function(data, menu)
    end, function(data, menu)
        menu.close()
        OpenClothingMenu()
    end, function(data, menu)
        MenuUpdateClothes(data, menu)
    end)
end

function MenuUpdateClothes(data, menu)
    if data.current.change_type == "model" then
        if ClothesCache[data.current.category].model ~= data.current.value then
            ClothesCache[data.current.category].texture = 1
            ClothesCache[data.current.category].model = data.current.value
            if data.current.value > 0 then
                menu.setElement(data.current.id + 1, "max", GetMaxTexturesForModel(data.current.category, data.current.value, true))
                menu.setElement(data.current.id + 1, "min", 1)
                menu.setElement(data.current.id + 1, "value", 1)
                menu.refresh()
                Change(data.current.value, data.current.category, data.current.change_type)
                EnsureBareBody(data.current.category)
            else
                local clearCategory = data.current.category == 'cloaks' and 'ponchos' or data.current.category
                Citizen.InvokeNative(0xD710A5007C2AC539, PlayerPedId(), GetHashKey(clearCategory), 0)
                NativeUpdatePedVariation(PlayerPedId())
                local bodyPart = BODY_CATEGORY_MAP[data.current.category]
                if bodyPart then
                    local hash = GetBodyFallbackHash(bodyPart)
                    if hash then
                        NativeSetPedComponentEnabledClothes(PlayerPedId(), hash, false, true, true)
                    end
                end
                EnsureBareBody(data.current.category)
                menu.setElement(data.current.id + 1, "max", 0)
                menu.setElement(data.current.id + 1, "min", 0)
                menu.setElement(data.current.id + 1, "value", 0)
                menu.refresh()
            end
            if not (IsInCharCreation or Skinkosong) then
                local newPrice = CalculatePrice(ConvertCacheToHash(ClothesCache), ConvertCacheToHash(OldClothesCache), IsPedMale(PlayerPedId()))
                if CurrentPrice ~= newPrice then
                    CurrentPrice = newPrice
                end
            end
        end
    end
    if data.current.change_type == "texture" then
        if ClothesCache[data.current.category].texture ~= data.current.value then
            ClothesCache[data.current.category].texture = data.current.value
            Change(data.current.value, data.current.category, data.current.change_type)
            EnsureBareBody(data.current.category)
        end
    end
end

local clothingLastFrame = GetGameTimer()

function ClothingLight()
    while ClothingCamera do
        Wait(0)
        local now = GetGameTimer()
        local dt = math.min((now - clothingLastFrame) / 16.667, 3.0)
        clothingLastFrame = now

        TogglePrompts({}, true)
    end
end

function Change(id, category, change_type)
    if IsPedMale(PlayerPedId()) then
        if change_type == "model" then
            NativeSetPedComponentEnabledClothes(PlayerPedId(), clothing["male"][category][id][1].hash, false, true, true)
        else
            local hash = clothing["male"][category][ClothesCache[category].model]

            if not hash then return end

            NativeSetPedComponentEnabledClothes(PlayerPedId(), clothing["male"][category][ClothesCache[category].model][id].hash, false, true, true)
        end
    else
        if change_type == "model" then
            NativeSetPedComponentEnabledClothes(PlayerPedId(), clothing["female"][category][id][1].hash, false, true, true)
        else
            local hash = clothing["female"][category][ClothesCache[category].model]

            if not hash then return end

            NativeSetPedComponentEnabledClothes(PlayerPedId(), clothing["female"][category][ClothesCache[category].model][id].hash, false, true, true)
        end
    end
end

RegisterNetEvent('rsg-character:client:ApplyClothes')
AddEventHandler('rsg-character:client:ApplyClothes', function(ClothesComponents, Target)
    CreateThread(function()
        local _Target = Target or PlayerPedId()
        if type(ClothesComponents) ~= "table" then
            SetEntityAlpha(_Target, 255)
            return
        end
        if next(ClothesComponents) == nil then
            SetEntityAlpha(_Target, 255)
            return
        end
        SetEntityAlpha(_Target, 0)
        local ok, err = pcall(function()
            ClothesCache = ClothesComponents
            local appliedCategories = {}
            for k, v in pairs(ClothesComponents) do
                if v ~= nil and v ~= 0 then
                    appliedCategories[k] = true
                    if type(v) ~= "table" then v = { hash = v} end
                    if v.hash and v.hash ~= 0 then
                        NativeSetPedComponentEnabledClothes(_Target, v.hash, false, true, true)
                        if v.palette then
                            NativeSetTextureOutfitTints(_Target,joaat(k),v.palette,v.tint0,v.tint1,v.tint2)
                        end
                    else
                        local id = tonumber(v.model)
                        if id and id >= 1 then
                            if IsPedMale(_Target) then
                                if clothing["male"][k] ~= nil then
                                    if clothing["male"][k][tonumber(v.model)] ~= nil then
                                        if clothing["male"][k][tonumber(v.model)][tonumber(v.texture)] ~= nil then
                                            NativeSetPedComponentEnabledClothes(_Target, tonumber(clothing["male"][k][tonumber(v.model)][tonumber(v.texture)].hash), false, true, true)
                                        end
                                    end
                                end
                            else
                                if clothing["female"][k] ~= nil then
                                    if clothing["female"][k][tonumber(v.model)] ~= nil then
                                        if clothing["female"][k][tonumber(v.model)][tonumber(v.texture)] ~= nil then
                                            NativeSetPedComponentEnabledClothes(_Target, tonumber(clothing["female"][k][tonumber(v.model)][tonumber(v.texture)].hash), false, true, true)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
            local bodyPartCovered = {}
            for cat, bodyPart in pairs(BODY_CATEGORY_MAP) do
                if appliedCategories[cat] then
                    bodyPartCovered[bodyPart] = true
                end
            end
            for cat, bodyPart in pairs(BODY_CATEGORY_MAP) do
                if not bodyPartCovered[bodyPart] then
                    bodyPartCovered[bodyPart] = true
                    local hash = GetBodyFallbackHash(bodyPart)
                    if hash then
                        NativeSetPedComponentEnabledClothes(_Target, hash, false, true, true)
                    end
                end
            end
        end)
        if not ok then
            print(('[rsg-character] ApplyClothes failed, restoring ped visibility anyway: %s'):format(tostring(err)))
        end
        SetEntityAlpha(_Target, 255)
    end)
end)

function destory()
    OldClothesCache = {}
    SetCamActive(ClothingCamera, false)
    RenderScriptCams(false, true, 500, true, true)
    DisplayHud(true)
    DisplayRadar(true)
    DestroyAllCams(true)
    ClothingCamera = nil
    playerHeading = nil
    Citizen.InvokeNative(0x4D51E59243281D80, PlayerId(), true, 0, false)
end

function TeleportAndFade(coords4, resetCoords)
    DoScreenFadeOut(500)
    Wait(1000)
    Citizen.InvokeNative(0x203BEFFDBE12E96A, PlayerPedId(), coords4)
    SetEntityCoordsNoOffset(PlayerPedId(), coords4, true, true, true)
    LocalPlayer.state.inClothingStore = true
    Wait(1500)
    DoScreenFadeIn(1800)
    if resetCoords then
        CurentCoords = {}
        TogglePrompts({}, false)
        LocalPlayer.state.inClothingStore = false
        TriggerServerEvent('rsg-character:server:SetPlayerBucket', 0)
    end
end

local clothingCameraMoving = false
local clothingCameraDirection = nil

local function ClothingCameraMoveLoop()
    if clothingCameraMoving then return end
    clothingCameraMoving = true

    CreateThread(function()
        while clothingCameraMoving do
            if ClothingCamera then
                if clothingCameraDirection == "up" or clothingCameraDirection == "down" then
                    local newOffset
                    if clothingCameraDirection == "up" then
                        newOffset = c_offset + 0.02
                    else
                        newOffset = c_offset - 0.02
                    end

                    if newOffset < 1.2 and newOffset > -1.0 then
                        c_offset = newOffset
                        camera(c_zoom, c_offset)
                    end
                elseif clothingCameraDirection == "zoomin" or clothingCameraDirection == "zoomout" then
                    local newZoom
                    if clothingCameraDirection == "zoomin" then
                        newZoom = c_zoom - 0.03
                    else
                        newZoom = c_zoom + 0.03
                    end

                    if newZoom < 2.5 and newZoom > 0.7 then
                        c_zoom = newZoom
                        camera(c_zoom, c_offset)
                    end
                elseif clothingCameraDirection == "rotateleft" or clothingCameraDirection == "rotateright" then
                    local heading = GetEntityHeading(PlayerPedId())
                    if clothingCameraDirection == "rotateleft" then
                        SetEntityHeading(PlayerPedId(), heading - 1.2)
                    else
                        SetEntityHeading(PlayerPedId(), heading + 1.2)
                    end
                end
            end
            Wait(0)
        end
    end)
end

AddEventHandler('rsg-character:client:CameraMoveStart', function(direction)
    clothingCameraDirection = direction
    ClothingCameraMoveLoop()
end)

AddEventHandler('rsg-character:client:CameraMoveStop', function()
    clothingCameraMoving = false
end)

AddEventHandler('rsg-character:client:CameraReset', function()
    if not ClothingCamera then return end
    c_zoom = 2.4
    c_offset = -0.15
    if playerHeading then SetEntityHeading(PlayerPedId(), playerHeading) end
    camera(c_zoom, c_offset)
end)

function camera(zoom, offset)
    local playerPed = PlayerPedId()
    local coords = GetEntityCoords(playerPed)
    local zoomOffset = zoom
    local angle

    if playerHeading == nil then
        playerHeading = GetEntityHeading(playerPed)
        angle = playerHeading * math.pi / 180.0
    else
        angle = playerHeading * math.pi / 180.0
    end

    local pos = {
        x = coords.x - (zoomOffset * math.sin(angle)),
        y = coords.y + (zoomOffset * math.cos(angle)),
        z = coords.z + offset
    }

    if not ClothingCamera then
        DestroyAllCams(true)
        ClothingCamera = CreateCamWithParams("DEFAULT_SCRIPTED_CAMERA", pos.x, pos.y, pos.z, 300.00, 0.00, 0.00, 50.00, false, 0)

        local pCoords = GetEntityCoords(PlayerPedId())
        PointCamAtCoord(ClothingCamera, pCoords.x, pCoords.y, pCoords.z + offset)

        SetCamActive(ClothingCamera, true)
        RenderScriptCams(true, true, 1000, true, true)
        DisplayRadar(false)
    else
        local ClothingCamera2 = CreateCamWithParams("DEFAULT_SCRIPTED_CAMERA", pos.x, pos.y, pos.z, 300.00, 0.00, 0.00, 50.00, false, 0)
        SetCamActive(ClothingCamera2, true)
        SetCamActiveWithInterp(ClothingCamera2, ClothingCamera, 750)

        local pCoords = GetEntityCoords(PlayerPedId())
        PointCamAtCoord(ClothingCamera2, pCoords.x, pCoords.y, pCoords.z + offset)

        Wait(150)
        SetCamActive(ClothingCamera, false)
        DestroyCam(ClothingCamera)
        ClothingCamera = ClothingCamera2
    end
end

local function EscapeHtml(str)
    return tostring(str):gsub('[&<>"\']', {
        ['&'] = '&amp;', ['<'] = '&lt;', ['>'] = '&gt;', ['"'] = '&quot;', ["'"] = '&#39;',
    })
end

function Outfits()
    UI.CloseAll()
    local Result = lib.callback.await('rsg-character:server:getOutfits', false)
    local elements_outfits = {}
    for k, v in pairs(Result) do
        elements_outfits[#elements_outfits + 1] = {
            name = v.name,
            label = '#' .. k .. '. ' .. EscapeHtml(v.name),
            value = v.clothes,
            desc = RSG.Label.choose
        }
    end
    UI.Open('default', GetCurrentResourceName(), 'outfits_menu',
        {title = RSG.Label.clothes, subtext = RSG.Label.choose, align = 'top-left', elements = elements_outfits, itemHeight = "4vh"},
        function(data, menu)
            OutfitsManage(data.current.value, data.current.name)
        end, function(data, menu)
            menu.close()
        end)
end

function OutfitsManage(outfit, id)
    UI.CloseAll()
    local elements_outfits_manage = {
        {label = RSG.Label.wear, value = "SetOutfits", desc = RSG.Label.wear_desc},
        {label = RSG.Label.delete, value = "DeleteOutfit", desc = RSG.Label.delete_desc}
    }
    UI.Open('default', GetCurrentResourceName(), 'outfits_menu_manage',
        {title = RSG.Label.clothes, subtext = RSG.Label.options, align = 'top-left', elements = elements_outfits_manage, itemHeight = "4vh"}, function(data, menu)
            menu.close()
        if data.current.value == 'SetOutfits' then
            TriggerEvent('rsg-character:client:ApplyClothes', outfit, PlayerPedId())
            local ClothesHash = ConvertCacheToHash(outfit)
            TriggerServerEvent('rsg-character:server:saveUseOutfit', ClothesHash)
        end
        if data.current.value == 'DeleteOutfit' then
            return TriggerServerEvent('rsg-character:server:DeleteOutfit', id)
        end
    end, function(data, menu)
        Outfits()
    end)
end

exports('GetClothesComponents', function()
    return {ComponentsClothesMale, ComponentsClothesFemale}
end)

exports('GetClothesCache', function(name)
    return ClothesCache
end)

exports('GetClothesComponentId', function(name)
    return ClothesCache[name]
end)

exports('GetClothesCurrentComponentHash', function(name)
    local entry = ClothesCache[name]
    if entry == nil then
        return 0
    end
    local genderTable = IsPedMale(PlayerPedId()) and clothing["male"] or clothing["female"]
    local categoryTable = genderTable[name]
    local modelTable = categoryTable and categoryTable[entry.model]
    local textureData = modelTable and modelTable[entry.texture]
    return (textureData and textureData.hash) or 0
end)

RegisterNetEvent('rsg-character:client:outfits', function()
    Outfits()
end)

local Cloakroom = GetRandomIntInRange(0, 0xffffff)

function OpenCloakroom()
    local str = locale('cloack_room_prompt_button')
    CloakPrompt = PromptRegisterBegin()
    PromptSetControlAction(CloakPrompt, RSG.OpenKey)
    str = CreateVarString(10, 'LITERAL_STRING', str)
    PromptSetText(CloakPrompt, str)
    PromptSetEnabled(CloakPrompt, true)
    PromptSetVisible(CloakPrompt, true)
    PromptSetHoldMode(CloakPrompt, true)
    PromptSetGroup(CloakPrompt, Cloakroom)
    PromptRegisterEnd(CloakPrompt)
end

CreateThread(function()
    OpenCloakroom()
    while true do
        Wait(100)
        local sleep = true
        local playerPed = PlayerPedId()
        local coords = GetEntityCoords(playerPed)
        for k, v in pairs(RSG.Cloakroom) do
            local dist = #(coords - v)
            if dist < 2.0 then
                sleep = false
                local PromptGroup = CreateVarString(10, 'LITERAL_STRING', RSG.Cloakroomtext)
                PromptSetActiveGroupThisFrame(Cloakroom, PromptGroup)
                if PromptHasHoldModeCompleted(CloakPrompt) then
                    Outfits()
                    break
                end
            end
        end
        if sleep then
            Wait(1500)
        end
    end
end)

function GenerateMenu()
    TriggerEvent('rsg-horses:client:FleeHorse')
    Wait(0)
    TeleportAndFade(CurentCoords.fittingcoords, false)
    TriggerServerEvent('rsg-character:server:SetPlayerBucket', 0, true)
    local ClothesComponents = lib.callback.await('rsg-character:server:LoadClothes', false)
    ClothesCache = hashToCache.PopulateClothingCache(ClothesComponents, IsPedMale(PlayerPedId()))
    OldClothesCache = deepcopy(ClothesCache)
    camera(2.4, -0.15)
    CreateThread(ClothingLight)
    OpenClothingMenu()
end

CreateThread(function()
    LocalPlayer.state.inClothingStore = false
    CreateBlips()
    if RegisterPrompts() then
        local room = false

        while true do
            room = GetClosestConsumer()

            if room then
                if not PromptsEnabled then TogglePrompts({ "OPEN_CLOTHING_MENU" }, true) end
                if PromptsEnabled then
                    if IsPromptCompleted("OPEN_CLOTHING_MENU") then
                        Citizen.InvokeNative(0x4D51E59243281D80, PlayerId(), false, 0, true)
                        GenerateMenu()
                    end
                end
            else
                if PromptsEnabled then TogglePrompts({ "OPEN_CLOTHING_MENU" }, false) end
                Wait(250)
            end
            Wait(100)
        end
    end
end)

local playerCoords = nil
GetClosestConsumer = function()
    playerCoords = GetEntityCoords(PlayerPedId())

    for _,data in pairs(RSG.Zones1) do
        if (data.promtcoords and #(playerCoords - data.promtcoords) < 1.0) or (data.epromtcoords and #(playerCoords - data.epromtcoords) < 1.0) then
            CurentCoords = data
            return true
        end
    end
    return false
end

RegisterPrompts = function()
    local newTable = {}

    for i=1, #RSG.Prompts do
        local prompt = Citizen.InvokeNative(0x04F97DE45A519419, Citizen.ResultAsInteger())
        Citizen.InvokeNative(0x5DD02A8318420DD7, prompt, CreateVarString(10, "LITERAL_STRING", RSG.Prompts[i].label))
        Citizen.InvokeNative(0xB5352B7494A08258, prompt, RSG.Prompts[i].control or RSGCore.Shared.Keybinds[RSG.Keybind])

        if RSG.Prompts[i].control2  then
            Citizen.InvokeNative(0xB5352B7494A08258, prompt, RSG.Prompts[i].control2)
        end

        Citizen.InvokeNative(0x94073D5CA3F16B7B, prompt, RSG.Prompts[i].time or 1000)

        if RSG.Prompts[i].control  then
            Citizen.InvokeNative(0x2F11D3A254169EA4, prompt, RoomPrompts)
        end

        Citizen.InvokeNative(0xF7AA2696A22AD8B9, prompt)
        Citizen.InvokeNative(0x8A0FB4D03A630D21, prompt, false)
        Citizen.InvokeNative(0x71215ACCFDE075EE, prompt, false)

        table.insert(RSG.CreatedEntries, { type = "PROMPT", handle = prompt })
        newTable[RSG.Prompts[i].id] = prompt
    end

    RSG.Prompts = newTable
    return true
end

TogglePrompts = function(data, state)
    for index,prompt in pairs((data ~= "ALL" and data) or RSG.Prompts) do
        if RSG.Prompts[(data ~= "ALL" and prompt) or index] then
            Citizen.InvokeNative(0x8A0FB4D03A630D21, (data ~= "ALL" and RSG.Prompts[prompt]) or prompt, state)
            Citizen.InvokeNative(0x71215ACCFDE075EE, (data ~= "ALL" and RSG.Prompts[prompt]) or prompt, state)
        end
    end
    local label  = CreateVarString(10, 'LITERAL_STRING', RSG.Label.shop.. ' - ~t6~'..CurrentPrice..'$')
    PromptSetActiveGroupThisFrame(RoomPrompts, label)
    PromptsEnabled = state
end

IsPromptCompleted = function(name)
    if RSG.Prompts[name] then
        return Citizen.InvokeNative(0xE0F65F0640EF0617, RSG.Prompts[name])
    end
    return false
end

CreateBlips = function()
    for _, coordsList in pairs(RSG.Zones1) do
        if #coordsList.blipcoords > 0 and coordsList.showblip then
            local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, coordsList.blipcoords)
            SetBlipSprite(blip, RSG.BlipSprite, 1)
            SetBlipScale(blip, RSG.BlipScale)
            Citizen.InvokeNative(0x9CB1A1623062F402, blip, RSG.BlipName)

            table.insert(RSG.CreatedEntries, { type = "BLIP", handle = blip })
        end
    end
    for _, v in pairs(RSG.Cloakroom) do
        local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, v)
        SetBlipSprite(blip, RSG.BlipSpriteCloakRoom, 1)
        SetBlipScale(blip, RSG.BlipScale)
        Citizen.InvokeNative(0x9CB1A1623062F402, blip, RSG.BlipNameCloakRoom)

        table.insert(RSG.CreatedEntries, { type = "BLIP", handle = blip })
    end
end

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    LocalPlayer.state.inClothingStore = false
    destory()
    for i=1, #RSG.CreatedEntries do
        if RSG.CreatedEntries[i].type == "BLIP" then
            RemoveBlip(RSG.CreatedEntries[i].handle)
        elseif RSG.CreatedEntries[i].type == "PROMPT" then
            Citizen.InvokeNative(0x00EDE88D4D13CF59, RSG.CreatedEntries[i].handle)
            PromptsEnabled = false
        end
    end
end)


function RemoveAllClothes()
    local ped = PlayerPedId()
    local gender = IsPedMale(ped) and "male" or "female"
    for category in pairs(clothing[gender]) do
        local clearCategory = category == 'cloaks' and 'ponchos' or category
        Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey(clearCategory), 0)
        if ClothesCache[category] ~= nil then
            ClothesCache[category] = { model = 0, texture = 1 }
        end
    end
    NativeUpdatePedVariation(ped)

    if (IsInCharCreation or Skinkosong) and CreatorCache and next(CreatorCache) then
        LoadBoody(ped, CreatorCache)
    else
        for _, bodyPart in ipairs({ "BODIES_UPPER", "BODIES_LOWER" }) do
            local hash = GetBodyFallbackHash(bodyPart)
            if hash then NativeSetPedComponentEnabledClothes(ped, hash, false, true, true) end
        end
    end
    NativeUpdatePedVariation(ped)

    if not (IsInCharCreation or Skinkosong) then
        CurrentPrice = CalculatePrice(ConvertCacheToHash(ClothesCache), ConvertCacheToHash(OldClothesCache), IsPedMale(ped))
    end
end
