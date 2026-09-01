local HEAD_BLEND_NATIVE = 0x2746BD9D88C5C5D0
local HEAD_BLEND_STRUCT_BYTES = 80
-- Native writes an 80-byte struct; skin fields start at offsets 24, 32 and 56.
local function readHeadBlendSkin(ped)
    local buffer = string.blob(HEAD_BLEND_STRUCT_BYTES)
    if not Citizen.InvokeNative(HEAD_BLEND_NATIVE, ped, buffer,
        Citizen.ReturnResultAnyway()) then return nil end
    return buffer:blob_unpack(25, '<i4'), buffer:blob_unpack(33, '<i4'),
        buffer:blob_unpack(57, '<f')
end
local function quantizeTenths(value)
    return math.min(math.max(math.floor(value * 10 + 0.5), 0), 10)
end
local function readFeatures(ped)
    local ok, skinFirst, skinSecond, skinMix = pcall(readHeadBlendSkin, ped)
    if not ok or not skinFirst then return nil end
    local found, overlayValue, _, firstColour, _, overlayOpacity =
        GetPedHeadOverlayData(ped, 1)
    local beardIndex, beardOpacity10, beardColor = 0, 0, 0
    if found then
        beardColor = firstColour
        if overlayValue ~= 255 then
            beardIndex = math.max(overlayValue, 0)
            beardOpacity10 = quantizeTenths(overlayOpacity)
        end
    end
    if skinFirst < 0 or skinFirst > 45 or skinSecond < 0 or skinSecond > 45 then
        return false
    end
    local function colorByte(value)
        if value < 0 or value > 255 then return 255 end
        return value
    end
    local features = {
        skinFirst,
        skinSecond,
        quantizeTenths(skinMix),
        colorByte(GetPedHairColor(ped)),
        colorByte(GetPedHairHighlightColor(ped)),
        beardIndex,
        beardOpacity10,
        colorByte(beardColor),
        colorByte(GetPedEyeColor(ped)),
    }
    return features, 'f' .. table.concat(features, ':') .. ';'
end

CreateThread(function()
    local previousPed
    local previousModel
    local previousSignature
    local previousFeaturesSegment

    while true do
        Wait(Config.AppearancePollIntervalMs)
        local ped = PlayerPedId()

        if not ped or ped == 0 or not DoesEntityExist(ped) then
            previousPed = nil
            previousModel = nil
            previousSignature = nil
            previousFeaturesSegment = nil
        else
            if ped ~= previousPed then
                previousPed = ped
                previousSignature = nil
                previousFeaturesSegment = nil
            end
            local model = GetEntityModel(ped)
            if model ~= previousModel then
                -- FiveM may reuse a ped handle for another model.
                previousModel = model
                previousFeaturesSegment = nil
            end
            local components, props = {}, {}
            local signatureParts = { ('m%d;'):format(model) }
            local transitioning = false
            for componentId = 0, 11 do
                local drawable = GetPedDrawableVariation(ped, componentId)
                if drawable == -1 then
                    -- Skip transient clothing swaps instead of inventing drawable 0.
                    transitioning = true
                    break
                end
                local texture = math.max(GetPedTextureVariation(ped, componentId), 0)
                components[componentId + 1] = { componentId, drawable, texture }
                signatureParts[#signatureParts + 1] = ('%d:%d;'):format(drawable, texture)
            end
            if not transitioning then
                for _, propId in ipairs(Config.AppearancePropIds) do
                    local drawable = GetPedPropIndex(ped, propId)
                    if drawable ~= -1 then
                        local texture = math.max(GetPedPropTextureIndex(ped, propId), 0)
                        props[#props + 1] = { propId, drawable, texture }
                        signatureParts[#signatureParts + 1] =
                            ('p%d:%d:%d;'):format(propId, drawable, texture)
                    end
                end
                local features, featuresSegment = readFeatures(ped)
                -- false clears stale features; nil preserves a prior successful read.
                if features == false then
                    previousFeaturesSegment = nil
                    featuresSegment = ''
                elseif features then
                    previousFeaturesSegment = featuresSegment
                elseif previousFeaturesSegment then
                    featuresSegment = previousFeaturesSegment
                else
                    features = false
                    featuresSegment = ''
                end
                signatureParts[#signatureParts + 1] = featuresSegment
                local signature = table.concat(signatureParts)
                if signature ~= previousSignature then
                    previousSignature = signature
                    TriggerServerEvent('humalike:npc:appearanceChanged', components, props, features)
                end
            end
        end
    end
end)
