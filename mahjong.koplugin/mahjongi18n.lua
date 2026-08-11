-- Plugin-local translations. Each file in translations/ is a complete language
-- definition, so adding a language does not require changing this loader or UI.

local lfs = require("libs/libkoreader-lfs")

local I18n = {}

local function pluginPath()
    local source = debug.getinfo(1, "S").source or ""
    source = source:gsub("^@", "")
    return source:match("^(.*[/\\])mahjongi18n%.lua$") or "."
end

local function normalizePath(path)
    return (path or ""):gsub("\\", "/"):gsub("/+$", "")
end

local function escapePattern(value)
    return (value:gsub("([^%w])", "%%%1"))
end

local function loadCatalogs()
    local catalogs = {}
    local language_files = {}
    local directory = normalizePath(pluginPath()) .. "/translations"
    if lfs.attributes(directory, "mode") ~= "directory" then
        return catalogs, language_files
    end

    for entry in lfs.dir(directory) do
        local filename = entry:match("^([%w_-]+)%.lua$")
        if filename then
            local path = directory .. "/" .. entry
            local chunk = loadfile(path)
            if chunk then
                local ok, definition = pcall(chunk)
                if ok and type(definition) == "table"
                    and type(definition.code) == "string"
                    and type(definition.name) == "string"
                    and type(definition.strings) == "table"
                then
                    catalogs[definition.code] = definition
                    language_files[#language_files + 1] = filename
                end
            end
        end
    end

    table.sort(language_files)
    return catalogs, language_files
end

local CATALOG, LANGUAGE_FILES = loadCatalogs()
local languages = {}
for code in pairs(CATALOG) do languages[#languages + 1] = code end
table.sort(languages)

local DEFAULT_LANGUAGE = CATALOG.en and "en" or languages[1]
local language = DEFAULT_LANGUAGE

function I18n.isSupported(value)
    return type(value) == "string" and CATALOG[value] ~= nil
end

function I18n.languageForLocale(locale)
    if type(locale) ~= "string" then return DEFAULT_LANGUAGE end
    local normalized = locale:lower():gsub("-", "_")
    for _, code in ipairs(languages) do
        local definition = CATALOG[code]
        for _, alias in ipairs(definition.locales or { code }) do
            alias = alias:lower():gsub("-", "_")
            if normalized == alias or normalized:match("^" .. escapePattern(alias) .. "_") then
                return code
            end
        end
    end
    return DEFAULT_LANGUAGE
end

function I18n.setLanguage(value)
    if not I18n.isSupported(value) then value = DEFAULT_LANGUAGE end
    language = value
    return language
end

function I18n.getLanguage() return language end

function I18n.supportedLanguages()
    local result = {}
    for i, code in ipairs(languages) do result[i] = code end
    return result
end

function I18n.languageName(code)
    local definition = CATALOG[code]
    return definition and definition.name or code
end

function I18n.languageFiles()
    local result = {}
    for i, filename in ipairs(LANGUAGE_FILES) do result[i] = filename end
    return result
end

function I18n.translate(key, ...)
    local active = CATALOG[language] or CATALOG[DEFAULT_LANGUAGE] or {}
    local fallback = CATALOG[DEFAULT_LANGUAGE] or {}
    local active_strings = active.strings or {}
    local fallback_strings = fallback.strings or {}
    local template = active_strings[key] or fallback_strings[key] or key
    if select("#", ...) > 0 then
        return string.format(template, ...)
    end
    return template
end

I18n.t = I18n.translate
I18n.catalog = {}
I18n.languageDefinitions = CATALOG
for code, definition in pairs(CATALOG) do
    I18n.catalog[code] = definition.strings
end
I18n.defaultLanguage = DEFAULT_LANGUAGE

return I18n
