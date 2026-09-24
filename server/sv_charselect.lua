RSGCore = RSGCore or exports['rsg-core']:GetCoreObject()

local function GetCharacterSlots(license)
    local maxSlots = RSG.MaxCharacterSlots or 4
    local slots = {}
    for i = 1, maxSlots do
        slots[i] = { cid = i, exists = false }
    end

    local rows = MySQL.query.await([[
        SELECT p.citizenid, p.cid, p.charinfo, p.job, p.money, s.skin, s.clothes
        FROM players p
        LEFT JOIN playerskins s ON s.citizenid = p.citizenid
        WHERE p.license = ?
    ]], {license})
    if rows then
        for _, row in ipairs(rows) do
            local cid = tonumber(row.cid)
            if cid and cid >= 1 and cid <= maxSlots then
                local ok, info = pcall(json.decode, row.charinfo)
                info = ok and info or {}

                local skin = nil
                if row.skin then
                    local okSkin, decoded = pcall(json.decode, row.skin)
                    if okSkin then skin = decoded end
                end

                local clothes = nil
                if row.clothes then
                    local okClothes, decoded = pcall(json.decode, row.clothes)
                    if okClothes then clothes = decoded end
                end

                local job = nil
                if row.job then
                    local okJob, decoded = pcall(json.decode, row.job)
                    if okJob then job = decoded end
                end

                local cash = 0
                if row.money then
                    local okMoney, decoded = pcall(json.decode, row.money)
                    if okMoney and decoded then cash = tonumber(decoded.cash) or 0 end
                end

                slots[cid] = {
                    cid = cid,
                    exists = true,
                    citizenid = row.citizenid,
                    firstname = info.firstname,
                    lastname = info.lastname,
                    gender = info.gender,
                    nationality = info.nationality,
                    birthdate = info.birthdate,
                    job = job,
                    cash = cash,
                    skin = skin,
                    clothes = clothes,
                }
            end
        end
    end

    return slots
end

RegisterServerEvent('rsg-character:server:RequestCharacterSlots')
AddEventHandler('rsg-character:server:RequestCharacterSlots', function()
    local _source = source
    local license = RSGCore.Functions.GetIdentifier(_source, 'license')
    if not license then
        SetTimeout(1500, function()
            local retrySource = _source
            if not GetPlayerName(retrySource) then return end
            local retryLicense = RSGCore.Functions.GetIdentifier(retrySource, 'license')
            if not retryLicense then
                TriggerClientEvent('rsg-character:client:CharSelectFailed', retrySource)
                return
            end
            TriggerClientEvent('rsg-character:client:ReceiveCharacterSlots', retrySource, GetCharacterSlots(retryLicense))
        end)
        return
    end
    TriggerClientEvent('rsg-character:client:ReceiveCharacterSlots', _source, GetCharacterSlots(license))
end)

RegisterServerEvent('rsg-character:server:SelectCharacterSlot')
AddEventHandler('rsg-character:server:SelectCharacterSlot', function(citizenid)
    local _source = source
    local license = RSGCore.Functions.GetIdentifier(_source, 'license')
    if not license or not citizenid then
        TriggerClientEvent('rsg-character:client:CharSelectFailed', _source)
        return
    end

    local owner = MySQL.scalar.await('SELECT license FROM players WHERE citizenid = ?', {citizenid})
    if not owner or owner ~= license then
        DropPlayer(_source, locale('charselect.exploit_dropped'))
        return
    end

    if not RSGCore.Player.Login(_source, citizenid) then
        TriggerClientEvent('rsg-character:client:CharSelectFailed', _source)
        return
    end

    local Player = RSGCore.Functions.GetPlayer(_source)
    if not Player then
        TriggerClientEvent('rsg-character:client:CharSelectFailed', _source)
        return
    end

    RSG.LoadSkinForSource(_source)

    local charinfo = Player.PlayerData.charinfo or {}
    local identityFields = RSG.WebhookIdentityFields(_source)
    RSG.SendWebhook('character_selected', {
        title = locale('webhooks.character_selected.title'),
        description = locale('webhooks.character_selected.description',
            charinfo.firstname or locale('webhooks.common.unknown'), charinfo.lastname or '', citizenid
        ),
        fields = { identityFields[1], identityFields[2] },
    })

    local pos = Player.PlayerData.position
    local isValidPos = pos and type(pos) == 'table'
        and tonumber(pos.x) and tonumber(pos.y) and tonumber(pos.z)
        and (math.abs(pos.x) > 1.0 or math.abs(pos.y) > 1.0 or math.abs(pos.z) > 1.0)

    TriggerClientEvent('rsg-character:client:OpenSpawnSelect', _source, isValidPos and pos or nil)
end)

RegisterServerEvent('rsg-character:server:DeleteCharacterSlot')
AddEventHandler('rsg-character:server:DeleteCharacterSlot', function(citizenid)
    local _source = source
    if not citizenid then return end

    local charRow = MySQL.single.await('SELECT charinfo FROM players WHERE citizenid = ?', {citizenid})
    local deletedFirstname, deletedLastname = locale('webhooks.common.unknown'), ''
    if charRow and charRow.charinfo then
        local ok, info = pcall(json.decode, charRow.charinfo)
        if ok and info then
            deletedFirstname = info.firstname or deletedFirstname
            deletedLastname = info.lastname or deletedLastname
        end
    end

    RSGCore.Player.DeleteCharacter(_source, citizenid)

    local identityFields = RSG.WebhookIdentityFields(_source)
    RSG.SendWebhook('character_deleted', {
        title = locale('webhooks.character_deleted.title'),
        description = locale('webhooks.character_deleted.description', deletedFirstname, deletedLastname, citizenid),
        fields = { identityFields[1], identityFields[2] },
    })

    local license = RSGCore.Functions.GetIdentifier(_source, 'license')
    if not license then return end

    Wait(300)
    TriggerClientEvent('rsg-character:client:ReceiveCharacterSlots', _source, GetCharacterSlots(license))
end)

RegisterServerEvent('rsg-character:server:RequestCreateCharacterSlot')
AddEventHandler('rsg-character:server:RequestCreateCharacterSlot', function(cid, selectedSex)
    local _source = source
    local license = RSGCore.Functions.GetIdentifier(_source, 'license')
    if not license then
        TriggerClientEvent('rsg-character:client:CharSelectFailed', _source)
        return
    end

    cid = tonumber(cid)
    local maxSlots = RSG.MaxCharacterSlots or 4
    if not cid or cid < 1 or cid > maxSlots then
        TriggerClientEvent('rsg-character:client:CharSelectFailed', _source)
        return
    end

    selectedSex = tonumber(selectedSex)
    if selectedSex ~= 1 and selectedSex ~= 2 then selectedSex = 1 end

    local existing = MySQL.scalar.await('SELECT citizenid FROM players WHERE license = ? AND cid = ?', {license, cid})
    if existing then
        TriggerClientEvent('ox_lib:notify', _source, { title = locale('charselect.slot_taken.title'), description = locale('charselect.slot_taken.desc'), type = 'error', duration = 5000 })
        TriggerClientEvent('rsg-character:client:ReceiveCharacterSlots', _source, GetCharacterSlots(license))
        return
    end

    TriggerClientEvent('rsg-character:client:OpenCreator', _source, { cid = cid, selectedSex = selectedSex })
end)
