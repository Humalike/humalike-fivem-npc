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

function HumalikeVoicePtt.Allowed(controlPressed, busy)
    return controlPressed == true and busy ~= true
end
