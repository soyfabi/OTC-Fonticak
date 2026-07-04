BackButton = {}
BackButton.func = nil
BackButton.params = {}

BackButton.backupFunc = nil
BackButton.backupParams = {}

function RegisterBackButton(func, ...)
    BackButton.func = BackButton.backupFunc
    BackButton.params = BackButton.backupParams

    BackButton.backupFunc = func
    BackButton.backupParams = {...}

    cyclopediaWindow:recursiveGetChildById('backButton'):setVisible(true)
end

function ExecuteBackButton()
    if BackButton.func then
        BackButton.func(unpack(BackButton.params))
        BackButton.func = nil
        BackButton.params = {}

        -- remove button
        cyclopediaWindow:recursiveGetChildById('backButton'):setVisible(false)
    end
end
