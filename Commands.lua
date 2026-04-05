local ADDON_NAME, LR = ...


-------------------------------------------------------------------------------
--- Slash Commands
-------------------------------------------------------------------------------

LR.cmds = {}
LR.cmds.toggle_lock = {
    triggers = { 'lock', 'l' },
    name = "Lock",
    description = "Lock or Unlock the Frame.",
    func = function() LR:ToggleLock() end,
}

LR.cmds.toggle_test = {
    triggers = { 'test', 't' },
    name = "Toggle frame for testing",
    description = "Toggle the frame for test viewing",
    func = function() LR:ToggleTest() end,
}

LR.cmds.toggle_debug = {
    triggers = { 'debug', 'd' },
    name = "Debug Messages",
    description = "Show debug messages",
    func = function() LR:ToggleDebug() end,
}


-------------------------------------------------------------------------------
--- Slash Command Handling
-------------------------------------------------------------------------------

function LR:Help()
    LR:Print("Available Commands:")

    for _, cmd in pairs(LR.cmds) do
        print(string.format("  %s %-10s - %s",
                            SLASH_LUSTREADY1,
                            table.concat(cmd.triggers, ", "),
                            cmd.description))
    end
end

SLASH_LUSTREADY1 = "/lr"

SlashCmdList[strupper(ADDON_NAME)] = function(msg)
    msg = msg:lower():trim()

    LR:VPrint(string.format("%s %s received",
                             SLASH_LUSTREADY1,
                             msg ~= "" and msg or "(no msg)"))

    for _, cmd in pairs(LR.cmds) do
        for _, trigger in ipairs(cmd.triggers) do
            if msg == trigger then
                cmd.func()

                return
            end
        end
    end

    LR:Help()
end
