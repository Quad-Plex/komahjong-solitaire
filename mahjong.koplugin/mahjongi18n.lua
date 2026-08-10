-- luacheck: max line length 240
-- Plugin-local translations.  The active language is deliberately independent
-- of KOReader's global gettext locale so it can be changed from Mahjong's UI.

local I18n = {}

local CATALOG = {
    en = {
        ["app.name"] = "Mahjong Solitaire",
        ["app.description"] = "Mahjong Solitaire tile-matching game for KOReader.",
        ["toolbar.hint"] = "Hint", ["toolbar.pause"] = "Pause",
        ["toolbar.undo"] = "Undo", ["toolbar.shuffle"] = "Shuffle",
        ["toolbar.new_game"] = "New Game", ["toolbar.exit"] = "Exit",
         ["toolbar.close"] = "Close", ["toolbar.play_again"] = "Play again",
         ["toolbar.select_layout"] = "Select Layout",
        ["toolbar.settings"] = "Settings", ["toolbar.stats"] = "Stats",
        ["toolbar.help"] = "Help",
        ["hud.pairs"] = "Pairs", ["hud.free"] = "Free", ["hud.score"] = "Score",
        ["settings.language"] = "Language", ["settings.on"] = "On",
        ["settings.off"] = "Off", ["settings.interaction"] = "On interaction",
        ["settings.periodic"] = "Periodic", ["settings.seconds"] = "%d s",
         ["settings.hints"] = "Allow using Hints", ["settings.deselect_on_empty"] = "Deselect on empty",
         ["settings.timer_update"] = "Timer update",
        ["settings.timer_interval"] = "Timer interval", ["settings.reset"] = "Reset",
        ["settings.save"] = "Save", ["settings.title"] = "Settings",
        ["language.en"] = "English", ["language.de"] = "Deutsch",
        ["picker.title"] = "Choose a Layout",
        ["pause.title"] = "Paused", ["pause.body"] = "The game is paused.",
        ["pause.resume"] = "Resume",
        ["stats.games_played"] = "Games played", ["stats.games_won"] = "Games won",
        ["stats.win_rate"] = "Win rate", ["stats.best_score"] = "Best score",
        ["stats.best_time"] = "Best time", ["stats.average_time"] = "Avg. duration",
        ["stats.current_streak"] = "Current streak", ["stats.longest_streak"] = "Longest streak",
        ["stats.global"] = "Global", ["stats.reset_confirm"] = "Reset all statistics? This cannot be undone.",
         ["game.exit_confirm"] = "Exit Mahjong Solitaire?", ["game.blocked"] = "Tile is blocked",
         ["game.new_game_confirm"] = "Start a new game? Your current game will be stopped.",
        ["game.combo"] = "COMBO +%d", ["game.combo_chain"] = "COMBO-CHAIN +%d",
        ["game.no_moves_shuffle"] = "No moves left! Shuffle the board? (-10 Score)",
        ["game.reshuffle"] = "Reshuffle remaining tiles? (-10 Score)",
        ["game.no_moves_dead"] = "No moves left, and shuffling can't help — this board can't be cleared.\nUndo your last move to try a different approach, or start a new game.",
        ["game.congrats_overall_score_time"] = "Congratulations! New overall best score and best time!",
        ["game.congrats_overall_score"] = "Congratulations! New overall best score!",
        ["game.congrats_overall_time"] = "Congratulations! New overall best time!",
        ["game.congrats_layout_score_time"] = "Congratulations! New best score and time on this layout!",
        ["game.congrats_layout_score"] = "Congratulations! New best score on this layout!",
        ["game.congrats_layout_time"] = "Congratulations! New best time on this layout!",
        ["game.cleared"] = "You cleared the board!", ["game.new_best"] = "(New best!)",
         ["game.layout"] = "Layout", ["game.time"] = "Time",
        ["game.overall_best_score"] = "Overall best score", ["game.overall_best_time"] = "Overall best time",
        ["game.current_streak"] = "Current streak", ["game.hints_used"] = "Hints used",
        ["game.shuffles"] = "Shuffles", ["game.auto_solve_arming"] = "Keep holding to auto-solve…",
        ["game.auto_solving"] = "Auto-solving…", ["game.score_layout"] = "%s best score",
        ["game.time_layout"] = "%s best time", ["game.confirm_shuffle"] = "Shuffle",
        ["help.title"] = "How to play", ["help.tile_groups"] = "Tile Groups",
        ["help.scoring"] = "Scoring", ["help.features"] = "Features",
        ["help.created_by"] = "Created by @Quad-Plex",
        ["help.page_one_1"] = "Remove all tiles to win. Select two matching tiles that are free.",
        ["help.page_one_2"] = "Free tiles have no tile covering them.", ["help.page_one_3"] = "They also have a fully open right or left side,",
        ["help.page_one_4"] = "with no tile covering any part of it.",
        ["help.page_one_5"] = "",
        ["help.page_one_6"] = "Checkmarks are selectable. The raised tile covers the two middle tiles,",
        ["help.page_one_7"] = "and the far-right tile blocks its neighbor's side, so its neighbor is X.",
        ["help.characters"] = "Characters, dots and bamboo: match the same number and suit 1:1.",
        ["help.winds"] = "Winds: match identical winds.", ["help.dragons"] = "Dragons: match identical dragons.",
        ["help.flowers"] = "Flowers: any flower matches any flower.", ["help.seasons"] = "Elements: water, earth, fire and air match any element.",
        ["help.each_pair"] = "Each pair scores 10 points.",
        ["help.chain_bonus"] = "A same-group chain bonus adds 5 points when",
         ["help.chain_method"] = "Consecutive same-group matches also earn a chain bonus.",
         ["help.chain_method_2"] = "Fast clears earn escalating combo bonuses.",
        ["help.combo_1"] = "Clear another pair within 5 seconds for a COMBO:",
        ["help.combo_2"] = "+10 points.", ["help.combo_3"] = "Continue clearing pairs within 5 seconds for a chain",
        ["help.combo_4"] = "combo: +5 more points each time.",
        ["help.hint_penalty"] = "Hint shows a possible pair and costs -5 points",
        ["help.hint_session"] = "once per hint session.",
        ["help.shuffle_penalty"] = "Shuffle rearranges the remaining tiles and costs -10 points.",
        ["help.undo_1"] = "Undo reverses your last pair, but does not refund",
        ["help.undo_2"] = "hint or shuffle penalties.", ["help.pause_1"] = "Pause stops the clock. Choose a layout when",
        ["help.pause_2"] = "starting a new game.",
        ["layout.turtle"] = "Turtle", ["layout.spider"] = "Spider", ["layout.bridge"] = "Bridge",
        ["layout.ziggurat"] = "Ziggurat", ["layout.cloud"] = "Cloud", ["layout.tictactoe"] = "Tic-Tac-Toe",
        ["layout.red-dragon"] = "Red Dragon", ["layout.overpass"] = "Overpass",
        ["layout.pyramid"] = "Pyramid's Walls", ["layout.confounding"] = "Confounding Cross",
         ["layout.taipei"] = "Taipei", ["layout.crab"] = "Crab",
         ["layout.hare"] = "Hare", ["layout.horse"] = "Horse", ["layout.tiger"] = "Tiger",
         ["layout.ram"] = "Ram", ["layout.monkey"] = "Monkey", ["layout.rooster"] = "Rooster",
         ["layout.dog"] = "Dog", ["layout.snake"] = "Snake", ["layout.boar"] = "Boar",
         ["layout.ox"] = "Ox", ["layout.wedges"] = "Wedges", ["layout.hourglass"] = "Hourglass",
    },
    de = {
        ["app.name"] = "Mahjong Solitaire", ["app.description"] = "Mahjong-Solitaire-Spiel für KOReader.",
        ["toolbar.hint"] = "Tipp", ["toolbar.pause"] = "Pause", ["toolbar.undo"] = "Rückgängig",
        ["toolbar.shuffle"] = "Mischen", ["toolbar.new_game"] = "Neues Spiel", ["toolbar.exit"] = "Beenden",
         ["toolbar.close"] = "Schliessen", ["toolbar.play_again"] = "Nochmal spielen",
         ["toolbar.select_layout"] = "Layout wählen",
        ["toolbar.settings"] = "Einstellungen", ["toolbar.stats"] = "Statistik", ["toolbar.help"] = "Hilfe",
        ["hud.pairs"] = "Paare", ["hud.free"] = "Frei", ["hud.score"] = "Punkte",
        ["settings.language"] = "Sprache", ["settings.on"] = "An", ["settings.off"] = "Aus",
         ["settings.interaction"] = "Bei Interaktion", ["settings.periodic"] = "Periodisch",
         ["settings.seconds"] = "%d s", ["settings.hints"] = "Hinweise erlauben",
         ["settings.deselect_on_empty"] = "Bei Leer-Tipp abwählen",
         ["settings.timer_update"] = "Timer-Aktualisierung",
        ["settings.timer_interval"] = "Timer-Intervall", ["settings.reset"] = "Zurücksetzen",
        ["settings.save"] = "Speichern", ["settings.title"] = "Einstellungen",
        ["language.en"] = "English", ["language.de"] = "Deutsch", ["picker.title"] = "Layout wählen",
        ["pause.title"] = "Pausiert", ["pause.body"] = "Das Spiel ist pausiert.", ["pause.resume"] = "Fortsetzen",
        ["stats.games_played"] = "Gespielt", ["stats.games_won"] = "Gewonnen",
        ["stats.win_rate"] = "Siegquote", ["stats.best_score"] = "Höchstpunktzahl",
        ["stats.best_time"] = "Beste Zeit", ["stats.average_time"] = "Durchschn. Dauer",
        ["stats.current_streak"] = "Aktuelle Serie", ["stats.longest_streak"] = "Längste Serie",
        ["stats.global"] = "Gesamt", ["stats.reset_confirm"] = "Alle Statistiken zurücksetzen? Dies kann nicht rückgängig gemacht werden.",
         ["game.exit_confirm"] = "Mahjong Solitaire beenden?", ["game.blocked"] = "Stein ist blockiert",
         ["game.new_game_confirm"] = "Neues Spiel starten? Das aktuelle Spiel wird beendet.",
        ["game.combo"] = "KOMBO +%d", ["game.combo_chain"] = "KOMBO-KETTE +%d",
        ["game.no_moves_shuffle"] = "Keine Züge mehr! Brett mischen? (-10 Punkte)",
        ["game.reshuffle"] = "Verbleibende Steine mischen? (-10 Punkte)",
        ["game.no_moves_dead"] = "Keine Züge mehr und Mischen kann nicht helfen – dieses Brett ist nicht lösbar.\nMache den letzten Zug rückgängig oder starte ein neues Spiel.",
        ["game.congrats_overall_score_time"] = "Glückwunsch! Neuer Punkt- und Zeitrekord!",
        ["game.congrats_overall_score"] = "Glückwunsch! Neue Globale Bestpunktzahl!",
        ["game.congrats_overall_time"] = "Glückwunsch! Neue Gobale Bestzeit!",
        ["game.congrats_layout_score_time"] = "Glückwunsch! Bestzeit und -punktzahl auf diesem Layout!",
        ["game.congrats_layout_score"] = "Glückwunsch! Neuer Highscore für dieses Layout!",
        ["game.congrats_layout_time"] = "Glückwunsch! Neue Bestzeit für dieses Layout!",
        ["game.cleared"] = "Du hast das Brett geleert!", ["game.new_best"] = "(Rekord!)",
         ["game.layout"] = "Layout", ["game.time"] = "Zeit",
        ["game.overall_best_score"] = "Bester Gesamtpunktestand", ["game.overall_best_time"] = "Beste Gesamtzeit",
        ["game.current_streak"] = "Aktuelle Serie", ["game.hints_used"] = "Verwendete Hinweise",
        ["game.shuffles"] = "Mischungen", ["game.auto_solve_arming"] = "Weiter halten zum Auto-Lösen…",
        ["game.auto_solving"] = "Auto-Lösen…", ["game.score_layout"] = "Bester Punktestand: %s",
        ["game.time_layout"] = "Beste Zeit: %s", ["game.confirm_shuffle"] = "Mischen",
        ["help.title"] = "Spielanleitung", ["help.tile_groups"] = "Steingruppen", ["help.scoring"] = "Punktesystem",
        ["help.features"] = "Funktionen", ["help.created_by"] = "Erstellt von @Quad-Plex", ["help.page_one_1"] = "Entferne alle Steine zum Gewinnen. Wähle zwei passende Steine",
        ["help.page_one_2"] = "die frei sind. Freie Steine werden von keinem anderen Stein ", ["help.page_one_3"] = "bedeckt. Ausserdem ist ihre rechte oder linke Seite vollständig",
        ["help.page_one_4"] = "frei, ohne dass ein Stein irgendeinen Teil davon bedeckt.",
        ["help.page_one_5"] = "",
        ["help.page_one_6"] = "Haken markieren auswählbare Steine. Der obere Stein bedeckt die beiden mittleren,",
        ["help.page_one_7"] = "der ganz rechte Stein blockiert die Seite seines Nachbarn.",
        ["help.characters"] = "Zeichen, Punkte und Bambus: gleiche Zahl und gleiche Farbe 1:1.",
        ["help.winds"] = "Winde: gleiche Winde paaren.", ["help.dragons"] = "Drachen: gleiche Drachen paaren.",
        ["help.flowers"] = "Blumen: beliebige Blumen passen zusammen.", ["help.seasons"] = "Elemente: Wasser, Erde, Feuer und Luft paaren beliebig.",
        ["help.each_pair"] = "Jedes Paar bringt 10 Punkte.", ["help.chain_bonus"] = "Eine Ketten-Serie derselben Gruppe bringt 5 Punkte",
         ["help.chain_method"] = "z.B. alle Blumen schnell entfernt.",
         ["help.chain_method_2"] = "Schnelle Züge bringen steigende KOMBO-Boni.", ["help.combo_1"] = "Finde innerhalb von 5 Sekunden ein weiteres Paar für eine",
        ["help.combo_2"] = "KOMBO +10 Punkte.", ["help.combo_3"] = "Finde innerhalb von 5 Sekunden weitere Paare für eine Kette",
        ["help.combo_4"] = "KOMBO: jedes Mal +5 weitere Punkte.", ["help.hint_penalty"] = "Ein Tipp zeigt ein mögliches Paar und kostet -5 Punkte",
        ["help.hint_session"] = "einmal pro Tipp-Session.", ["help.shuffle_penalty"] = "Mischen ordnet die verbleibenden Steine neu und kostet -10 Punkte.",
        ["help.undo_1"] = "Rückgängig macht dein letztes Paar rückgängig, erstattet aber keine",
        ["help.undo_2"] = "Tipp- oder Mischkosten.", ["help.pause_1"] = "Pause stoppt die Uhr. Wähle ein Layout beim Start eines neuen Spiels.",
        ["help.pause_2"] = "", ["layout.turtle"] = "Schildkröte", ["layout.spider"] = "Spinne",
        ["layout.bridge"] = "Brücke", ["layout.ziggurat"] = "Zikkurat", ["layout.cloud"] = "Wolke",
        ["layout.tictactoe"] = "Tic-Tac-Toe", ["layout.red-dragon"] = "Roter Drache", ["layout.overpass"] = "Überführung",
        ["layout.pyramid"] = "Pyramidenwände", ["layout.confounding"] = "Verwirrendes Kreuz",
         ["layout.taipei"] = "Taipeh", ["layout.crab"] = "Krabbe",
         ["layout.hare"] = "Hase", ["layout.horse"] = "Pferd", ["layout.tiger"] = "Tiger",
         ["layout.ram"] = "Widder", ["layout.monkey"] = "Affe", ["layout.rooster"] = "Hahn",
         ["layout.dog"] = "Hund", ["layout.snake"] = "Schlange", ["layout.boar"] = "Wildschwein",
         ["layout.ox"] = "Ochse", ["layout.wedges"] = "Keile", ["layout.hourglass"] = "Sanduhr",
    },
}

local language = "en"

function I18n.isSupported(value)
    return type(value) == "string" and CATALOG[value] ~= nil
end

-- KOReader's gettext module stores its active locale in current_lang.  Only
-- German is selected automatically; every other locale intentionally uses
-- the plugin's English catalog.
function I18n.languageForLocale(locale)
    if type(locale) == "string" then
        local normalized = locale:lower()
        if normalized == "de" or normalized:match("^de[_-]") then
            return "de"
        end
    end
    return "en"
end

function I18n.setLanguage(value)
    if not I18n.isSupported(value) then value = "en" end
    language = value
    return language
end

function I18n.getLanguage() return language end

function I18n.supportedLanguages()
    return { "en", "de" }
end

function I18n.translate(key, ...)
    local template = CATALOG[language][key] or CATALOG.en[key] or key
    if select("#", ...) > 0 then
        return string.format(template, ...)
    end
    return template
end

I18n.t = I18n.translate
I18n.catalog = CATALOG

return I18n
