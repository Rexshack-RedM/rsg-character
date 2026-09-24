RSGCore = exports['rsg-core']:GetCoreObject()

RegisterServerEvent('rsg-character:server:SaveSkin')
AddEventHandler('rsg-character:server:SaveSkin', function(skin, clothes, oldplayer)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player then return end
    if type(skin) ~= 'table' or type(clothes) ~= 'table' then return end

    local isMale = tonumber(skin.sex) ~= 2
    local validClothes = ValidateClothesData(clothes, isMale)
    if not validClothes then return end

    local encode = json.encode(skin)
    local encode2 = json.encode(clothes)
    if #encode > 32768 or #encode2 > 32768 then return end

    local citizenid = Player.PlayerData.citizenid

    if oldplayer then
        local result = MySQL.query.await('SELECT * FROM playerskins WHERE citizenid = ?', {citizenid})

        if result and #result > 0 then
            local existingSkin = json.decode(result[1].skin)
            local existingClothes = json.decode(result[1].clothes)

            for k, v in pairs(skin) do
                existingSkin[k] = v
            end

            for k, v in pairs(clothes) do
                existingClothes[k] = v
            end

            local encodedSkin = json.encode(existingSkin)
            local encodedclothes = json.encode(existingClothes)
            MySQL.Async.execute('UPDATE playerskins SET skin = @skin, clothes = @clothes WHERE citizenid = @citizenid',
            {
                ['citizenid'] = citizenid,
                ['skin'] = encodedSkin,
                ['clothes'] = encodedclothes,
            })
        else
            MySQL.Async.insert('INSERT INTO playerskins (citizenid, skin, clothes) VALUES (?, ?, ?);', { citizenid, encode, encode2 })
        end
    else
        MySQL.Async.insert('INSERT INTO playerskins (citizenid, skin, clothes) VALUES (?, ?, ?);', { citizenid, encode, encode2 })
        TriggerClientEvent('rsg-character:client:OpenSpawnSelect', source)
    end

    local identityFields = RSG.WebhookIdentityFields(source)
    RSG.SendWebhook('appearance_saved', {
        title = oldplayer and locale('webhooks.appearance_saved.title_update') or locale('webhooks.appearance_saved.title_initial'),
        description = locale('webhooks.appearance_saved.description', citizenid),
        fields = {
            { name = locale('webhooks.appearance_saved.field_citizenid'), value = citizenid, inline = true },
            identityFields[1],
            identityFields[2],
        },
    })
end)

RegisterServerEvent('rsg-character:server:SetPlayerBucket')
AddEventHandler('rsg-character:server:SetPlayerBucket', function(b, random)
    if random then
        local BucketID = RSGCore.Shared.RandomInt(1000, 9999)
        SetRoutingBucketPopulationEnabled(BucketID, false)
        SetPlayerRoutingBucket(source, BucketID)
    else
        local bucket = tonumber(b)
        if not bucket or bucket < 0 or bucket > 0xffffff then return end
        SetPlayerRoutingBucket(source, math.floor(bucket))
    end
end)

function RSG.LoadSkinForSource(_source)
    local User = RSGCore.Functions.GetPlayer(_source)
    if not User then return end
    local citizenid = User.PlayerData.citizenid
    local skins = MySQL.query.await('SELECT * FROM playerskins WHERE citizenid = ?', {citizenid})
    if skins[1] then
        local skin = skins[1].skin
        local clothes = skins[1].clothes
        local decodedSkin = json.decode(skin)
        local decodedClothes = json.decode(clothes)
        TriggerClientEvent('rsg-character:client:ApplySkin', _source, decodedSkin, decodedClothes)
    else
        TriggerClientEvent('rsg-character:client:OpenCreator', _source, nil, true)
    end
end

RegisterServerEvent('rsg-character:server:LoadSkin')
AddEventHandler('rsg-character:server:LoadSkin', function()
    RSG.LoadSkinForSource(source)
end)

RegisterServerEvent('rsg-multicharacter:server:createCharacter')
AddEventHandler('rsg-multicharacter:server:createCharacter', function(newData)
    local _source = source
    if not newData or not newData.cid then return end

    local license = RSGCore.Functions.GetIdentifier(_source, 'license')
    if not license then return end

    local cid = tonumber(newData.cid)
    if not cid or cid < 1 or cid > (RSG.MaxCharacterSlots or 4) then return end

    local existing = MySQL.scalar.await('SELECT citizenid FROM players WHERE license = ? AND cid = ?', {license, cid})
    if existing then
        TriggerClientEvent('ox_lib:notify', _source, { title = locale('charselect.slot_taken.title'), description = locale('charselect.slot_taken.desc'), type = 'error', duration = 5000 })
        TriggerClientEvent('rsg-character:client:OpenCharSelect', _source)
        return
    end

    local gender = tonumber(newData.gender) or 0
    if gender ~= 0 and gender ~= 1 then gender = 0 end

    RSGCore.Player.Login(_source, nil, {
        cid = cid,
        charinfo = {
            firstname = newData.firstname,
            lastname = newData.lastname,
            nationality = newData.nationality,
            birthdate = newData.birthdate,
            gender = gender,
        }
    })

    local Player = RSGCore.Functions.GetPlayer(_source)
    if not Player then return end

    for _, entry in ipairs(RSG.StarterItems or {}) do
        local itemName = entry.item
        local amount = tonumber(entry.amount) or 1
        if itemName and amount > 0 and RSGCore.Shared.Items[itemName] then
            Player.Functions.AddItem(itemName, amount)
            TriggerClientEvent('rsg-inventory:client:ItemBox', _source, RSGCore.Shared.Items[itemName], 'add')
        end
    end

    TriggerClientEvent('RSGCore:Client:OnPlayerLoaded', _source)

    local identityFields = RSG.WebhookIdentityFields(_source)
    RSG.SendWebhook('character_created', {
        title = locale('webhooks.character_created.title'),
        description = locale('webhooks.character_created.description',
            newData.firstname or locale('webhooks.common.unknown'), newData.lastname or '', cid
        ),
        fields = {
            { name = locale('webhooks.character_created.field_citizenid'), value = Player.PlayerData.citizenid, inline = true },
            { name = locale('webhooks.character_created.field_gender'), value = gender == 0 and locale('webhooks.character_created.male') or locale('webhooks.character_created.female'), inline = true },
            { name = locale('webhooks.character_created.field_nationality'), value = newData.nationality or locale('webhooks.common.na'), inline = true },
            { name = locale('webhooks.character_created.field_birthdate'), value = newData.birthdate or locale('webhooks.common.na'), inline = true },
            identityFields[1],
            identityFields[2],
        },
    })
end)

RSGCore.Functions.CreateCallback('rsg-multicharacter:server:getAppearance', function(source, cb)
    local User = RSGCore.Functions.GetPlayer(source)
    if not User then return cb({}) end
    local citizenid = User.PlayerData.citizenid
    local result = MySQL.query.await('SELECT * FROM playerskins WHERE citizenid = ?', {citizenid})
    if result and result[1] then
        cb({ skin = json.decode(result[1].skin), clothes = json.decode(result[1].clothes) })
    else
        cb({ skin = {}, clothes = {} })
    end
end)


RegisterServerEvent('rsg-character:server:deleteSkin')
AddEventHandler('rsg-character:server:deleteSkin', function()
    local _source = source
    local Player = RSGCore.Functions.GetPlayer(_source)
    if not Player then return end
    local citizenid = Player.PlayerData.citizenid
    MySQL.Async.execute('DELETE FROM playerskins WHERE citizenid = ?', {citizenid})
end)

RegisterServerEvent('rsg-character:server:updategender', function(gender)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player then return end

    gender = tonumber(gender)
    if gender ~= 0 and gender ~= 1 then return end

    local citizenid = Player.PlayerData.citizenid
    local license = RSGCore.Functions.GetIdentifier(source, 'license')

    local result = MySQL.query.await('SELECT * FROM players WHERE citizenid = ? AND license = ?', {citizenid, license})
    if not result or not result[1] then return end
    local Charinfo = json.decode(result[1].charinfo)
    Charinfo.gender = gender

    Player.PlayerData.charinfo = Charinfo
    if Player.Functions.SetPlayerData then
        Player.Functions.SetPlayerData('charinfo', Charinfo)
    end
    Player.Functions.Save()
end)
