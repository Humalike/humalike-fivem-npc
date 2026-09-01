HumaLike = HumaLike or {}

local state = {
    phase = 'starting',
    detail = 'waiting for bootstrap',
    changedAt = os.time()
}

function HumaLike.SetStatus(phase, detail)
    state.phase = phase
    state.detail = detail
    state.changedAt = os.time()
    print(('[humalike] %s: %s'):format(phase, detail))
end

function HumaLike.Status()
    return {
        phase = state.phase,
        detail = state.detail,
        changedAt = state.changedAt
    }
end

RegisterCommand('humalike_status', function(source)
    if source ~= 0 then return end
    print(('[humalike] status=%s since=%s detail=%s'):format(
        state.phase,
        os.date('!%Y-%m-%dT%H:%M:%SZ', state.changedAt),
        state.detail
    ))

    if type(HumalikeGetProviderStatus) ~= 'function' then
        print('[humalike] integrations=starting')
        return
    end

    local providerStatus = HumalikeGetProviderStatus()
    print(('[humalike] integrations api=%s epoch=%s'):format(
        providerStatus.apiVersion,
        providerStatus.runtimeEpoch
    ))
    for _, domain in ipairs({ 'player', 'inventory', 'dispatch', 'actions' }) do
        local status = providerStatus.domains[domain]
        local selected = status.selected and status.selected.name or 'none'
        local candidates = {}
        for _, candidate in ipairs(status.candidates or {}) do
            candidates[#candidates + 1] = ('%s:%s'):format(
                candidate.name,
                candidate.state
            )
        end
        print(('[humalike] integration domain=%s setting=%s state=%s selected=%s candidates=[%s]%s'):format(
            domain,
            status.setting,
            status.state,
            selected,
            table.concat(candidates, ','),
            status.reason and (' reason=%s'):format(status.reason) or ''
        ))
    end
end, true)
