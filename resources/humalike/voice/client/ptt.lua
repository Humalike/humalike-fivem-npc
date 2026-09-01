HumalikeVoicePtt = {}

function HumalikeVoicePtt.InputPressed(mappedPressed, sharesNativeBinding,
        playerPressed, playerDisabledPressed, frontendPressed,
        frontendDisabledPressed)
    return mappedPressed == true
        or (sharesNativeBinding == true and (
            playerPressed == true
            or playerDisabledPressed == true
            or frontendPressed == true
            or frontendDisabledPressed == true))
end

function HumalikeVoicePtt.Allowed(controlPressed, radioActive, callActive)
    return controlPressed == true and radioActive ~= true and callActive ~= true
end

function HumalikeVoicePtt.CallActive(callChannel, pmaStarted)
    return pmaStarted == true and (tonumber(callChannel) or 0) ~= 0
end
