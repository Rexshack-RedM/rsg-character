RegisterNetEvent('rsg-character:client:ApplySkin', function(skin, clothes)
    exports[GetCurrentResourceName()]:ApplySkinMultiChar(skin, PlayerPedId(), clothes)
end)

local OpenSpawnMenu


local function TeleportToSpawn(coords, heading, isNewCharacter)
    local ped = PlayerPedId()

    DoScreenFadeOut(500)
    local fadeTimeout = GetGameTimer() + 2000
    while not IsScreenFadedOut() and GetGameTimer() < fadeTimeout do
        Wait(0)
    end

    SetEntityCoords(ped, coords.x, coords.y, coords.z, false, false, false, false)

    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    local collisionTimeout = GetGameTimer() + 3000
    local collisionLoaded = false
    while GetGameTimer() < collisionTimeout do
        if HasCollisionLoadedAroundEntity(ped) then
            collisionLoaded = true
            break
        end
        Wait(0)
    end

    if not collisionLoaded and isNewCharacter == false then
        DoScreenFadeIn(500)
        OpenSpawnMenu()
        return
    end

    local groundZ = GetGroundedZ(coords.x, coords.y, coords.z)

    SetEntityCoords(ped, coords.x, coords.y, groundZ, false, false, false, false)
    SetEntityHeading(ped, heading or 0.0)

    FreezeEntityPosition(ped, false)
    SetEntityVisible(ped, true, false)
    Citizen.InvokeNative(0x4D51E59243281D80, PlayerId(), true, 0, false)
    DisplayHud(true)
    DisplayRadar(true)

    if isNewCharacter then
        ExecuteCommand('revive')
    end

    Wait(10000)

    if UI and UI.HideLoadingScreen then UI.HideLoadingScreen() end
    DoScreenFadeIn(1000)
    TriggerServerEvent('RSGCore:Server:OnPlayerLoaded')
    TriggerEvent('RSGCore:Client:OnPlayerLoaded')

end

local function BuildSpawnElements()
    local elements = {}

    for i, loc in ipairs(RSG.SpawnLocations or {}) do
        elements[#elements + 1] = {
            label = loc.label,
            value = 'preset_' .. i,
            desc = locale('spawn.preset.desc'),
            image = loc.image,
        }
    end

    return elements
end

OpenSpawnMenu = function()
    local value = UI.OpenSpawnSelect({
        title = locale('spawn.title'),
        subtitle = locale('spawn.subtitle'),
        elements = BuildSpawnElements(),
    })

    local idx = value and tonumber(value:match('^preset_(%d+)$'))
    local loc = idx and RSG.SpawnLocations[idx]
    if loc then
        UI.ShowLoadingScreen(locale('spawn.loading'))
        TeleportToSpawn(loc.coords, loc.coords.w, true)
    end
end

RegisterNetEvent('rsg-character:client:OpenSpawnSelect', function(lastPos)
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)

    if lastPos then
        TeleportToSpawn(lastPos, lastPos.w, false)
        return
    end

    OpenSpawnMenu()
end)

RegisterNetEvent('RSGCore:Client:OnPlayerLoaded', function()
    local spawnChecks = RSG.SpawnChecks
    if not spawnChecks then
        return
    end

    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)

    if Config.Debug then
        print('Checking spawn: ' .. tostring(playerCoords))
    end

    for checkName, check in pairs(spawnChecks) do
        local radius = check.Radius or check.radius or 200
        local moveTo = getFirstVector(check.moveTo)

        if moveTo then
            for _, badSpawn in ipairs(check.badSpawn or {}) do
                if #(playerCoords - badSpawn) < radius then
                    if Config.Debug then
                        print(('Bad spawn matched: %s'):format(checkName))
                    end
                    SetEntityCoords(playerPed, moveTo.x, moveTo.y, moveTo.z, 0, 0, 0, false)
                    return
                end
            end
        end
    end
end)
