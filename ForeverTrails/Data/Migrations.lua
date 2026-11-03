local _, FT = ...
FT.Migrations = {}

function FT.Migrations.Open(db)
    if db == nil then db = { schemaVersion = 1, characters = {}, settings = {} } end
    if type(db) ~= "table" or db.schemaVersion ~= 1
        or type(db.characters) ~= "table" or type(db.settings) ~= "table" then
        return nil, "Unsupported or damaged saved history. Back up ForeverTrails.lua before resetting it."
    end
    for key, value in pairs(FT.defaults) do
        if db.settings[key] == nil then db.settings[key] = value end
    end
    for _, key in ipairs({ "characterPointLimit", "accountPointLimit" }) do
        local value = db.settings[key]
        if not FT.Compat.IsNumber(value) or value < 2 then
            db.settings[key] = FT.defaults[key]
        else
            db.settings[key] = math.floor(value)
        end
    end
    return db
end
