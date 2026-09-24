RegisterServerEvent('rsg-character:server:saveOutfit', function(newClothes, _clientIsMale, outfitName)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local isMale = (Player.PlayerData.charinfo?.gender or 0) == 0
    local citizenid = Player.PlayerData.citizenid
    local skinData = MySQL.query.await('SELECT clothes FROM playerskins WHERE citizenid = ?', { citizenid })

    newClothes = newClothes or {}
    local currentClothes = (skinData[1] and skinData[1].clothes and json.decode(skinData[1].clothes)) or {}
    local valid, reason = ValidateClothesData(newClothes, isMale)
    if not valid then
        TriggerClientEvent('ox_lib:notify', src, { title = locale('clothing_validation.title'), description = reason, type = 'error', duration = 5000 })
        return
    end
    local price = CalculatePrice(newClothes, currentClothes, isMale)

    if Player.Functions.RemoveMoney('cash', price, 'buy-clothes') then
        MySQL.execute('UPDATE playerskins SET clothes = @clothes WHERE citizenid = @citizenid', {
            ['@citizenid'] = citizenid,
            ['@clothes'] = json.encode(newClothes),
        })
        if outfitName and type(outfitName) == 'string' and outfitName ~= '' then
            outfitName = outfitName:sub(1, 40)
            MySQL.query.await('INSERT INTO playeroutfit (citizenid, name, clothes) VALUES (@citizenid, @name, @clothes)', {
                ['@citizenid'] = citizenid,
                ['@name'] = outfitName,
                ['@clothes'] = json.encode(newClothes),
            })
        end

        local identityFields = RSG.WebhookIdentityFields(src)
        RSG.SendWebhook('outfit_purchased', {
            title = locale('webhooks.outfit_purchased.title'),
            description = locale('webhooks.outfit_purchased.description', price),
            fields = {
                { name = locale('webhooks.outfit_purchased.field_citizenid'), value = citizenid, inline = true },
                { name = locale('webhooks.outfit_purchased.field_outfit_name'), value = (outfitName and outfitName ~= '') and outfitName or locale('webhooks.common.na'), inline = true },
                identityFields[1],
                identityFields[2],
            },
        })
    else
        TriggerClientEvent('ox_lib:notify', src, { title = locale('insufficient_funds.title'), description = locale('insufficient_funds.description'), type = 'error', duration = 5000 })
    end
end)

RegisterNetEvent('rsg-character:server:saveUseOutfit', function(clothes)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    if clothes ~= nil then
        local citizenid = Player.PlayerData.citizenid
        local isMale = (Player.PlayerData.charinfo?.gender or 0) == 0
        local valid = ValidateClothesData(clothes, isMale)
        if not valid then return end

        local encoded = json.encode(clothes)
        local owned = MySQL.scalar.await('SELECT 1 FROM playeroutfit WHERE citizenid = ? AND clothes = ?', { citizenid, encoded })
        if not owned then
            TriggerClientEvent('ox_lib:notify', src, { title = locale('clothing_validation.title'), description = locale('insufficient_funds.description'), type = 'error', duration = 5000 })
            return
        end

        MySQL.execute('UPDATE playerskins SET clothes = @clothes WHERE citizenid = @citizenid', {
            ['@citizenid'] = citizenid,
            ['@clothes'] = encoded,
        })
    end
end)

RegisterServerEvent('rsg-character:server:DeleteOutfit')
AddEventHandler('rsg-character:server:DeleteOutfit', function(name)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player or type(name) ~= 'string' then return end
    local citizenid = Player.PlayerData.citizenid
    MySQL.Async.execute('DELETE FROM playeroutfit WHERE citizenid = ? AND name = ?', {citizenid, name})
end)

lib.callback.register('rsg-character:server:LoadClothes', function(source)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player then return {} end
    local citizenid = Player.PlayerData.citizenid
    local clothes = {}
    local Result = MySQL.query.await('SELECT clothes FROM playerskins WHERE citizenid = ?', { citizenid })

    if Result[1] ~= nil and Result[1].clothes ~= nil then
        clothes = json.decode(Result[1].clothes)
    end

    return clothes
end)

lib.callback.register('rsg-character:server:getOutfits', function(source)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player then return {} end
    local outfit = {}
    local Result = MySQL.query.await('SELECT * FROM playeroutfit WHERE citizenid=@citizenid', {['@citizenid'] = Player.PlayerData.citizenid})

    for i = 1, #Result do
        Result[i].clothes = json.decode(Result[i].clothes)
        outfit[#outfit+1] = Result[i]
    end

    return outfit
end)