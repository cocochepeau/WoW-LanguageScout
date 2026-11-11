local _, ns = ...
-- Pet names themselves still use the original UnitName API below.
local ReadPlayerName = ns.ReadUnitName

local L = ns.L
local SUPPORTED_LANGUAGES = ns.SUPPORTED_LANGUAGES
local FullName = ns.FullName
local NormalizePlayerKey = ns.NormalizePlayerKey
local ResolveChatAuthorPlayerKey = ns.ResolveChatAuthorPlayerKey
local AddPlayerLanguageIfMissing = ns.AddPlayerLanguageIfMissing
local SetPlayerLanguage = ns.SetPlayerLanguage
local EnsureAutoDetectWordsTable = ns.EnsureAutoDetectWordsTable
local IsSupportedLanguage = ns.IsSupportedLanguage
local IsLanguageAutoDetectEnabled = ns.IsLanguageAutoDetectEnabled
local ShowAutoLanguageMarkedMessage = ns.ShowAutoLanguageMarkedMessage

local PET_OWNER_KEYWORDS = {
    DE = {
        "Fledermaus",
        "Bär",
        "Eber",
        "Aasvogel",
        "Katze",
        "Krebs",
        "Krokilisk",
        "Hyäne",
        "Eule",
        "Skorpid",
        "Spinne",
        "Weitschreiter",
        "Schildkröte",
        "Windnatter",
        "Drachenfalke",
        "Felshetzer",
        "Sphärenjäger",
        "Sporensegler",
        "Netherrochen",
        "Schlange",
    },
    ES = {
        "Murciélago",
        "Oso",
        "Jabalí",
        "Carroñero",
        "Felino",
        "Cangrejo",
        "Crocolisco",
        "Hiena",
        "Búho",
        "Escórpido",
        "Araña",
        "Zancaalta",
        "Tortuga",
        "Serpiente alada",
        "Lobo",
        "Dracohalcón",
        "Devastador",
        "Acechador deformado",
        "Esporiélago",
        "Raya abisal",
        "Serpiente",
    },
    FR = {
        "Chauve-souris",
        "Ours",
        "Sanglier",
        "Charognard",
        "Félin",
        "Crabe",
        "Crocilisque",
        "Hyène",
        "Hibou",
        "Scorpide",
        "Araignée",
        "Haut-trotteur",
        "Tortue",
        "Serpent ailé",
        "Loup",
        "Faucon-dragon",
        "Ravageur",
        "Traqueur dimorphique",
        "Chauve-souris des spores",
        "Raie du Néant",
        "Serpent",
    },
    RU = {
        "Летучая мышь",
        "Медведь",
        "Вепрь",
        "Падальщик",
        "Кошка",
        "Краб",
        "Кроколиск",
        "Гиена",
        "Сова",
        "Скорпид",
        "Паук",
        "Долгоног",
        "Черепаха",
        "Крылатый змей",
        "Волк",
        "Дракондор",
        "Опустошитель",
        "Прыгуана",
        "Спороскат",
        "Скат Пустоты",
        "Змей",
    },
}

local petOwnerTooltip = CreateFrame("GameTooltip", "LanguageScoutPetOwnerTooltip", UIParent, "GameTooltipTemplate")
petOwnerTooltip:SetOwner(UIParent, "ANCHOR_NONE")

local DEFAULT_KEYWORD_SCORE = 2
local MIN_LANGUAGE_SCORE = 2

local lowConfidenceKeywordMap = {
    ES = {
        ["Banda"] = true,
    },
    DE = {
        ["für"] = true,
        ["heute"] = true,
        ["morgen"] = true,
        ["melden"] = true,
        ["gerne"] = true,
        ["Interesse"] = true,
        ["Schatten"] = true,
        ["Stiefel"] = true,
        ["Handschuhe"] = true,
        ["Brust"] = true,
        ["Gürtel"] = true,
        ["Muster"] = true,
    },
    FR = {
        ["pour"] = true,
        ["son"] = true,
        ["à"] = true,
        ["depuis"] = true,
        ["semaine"] = true,
        ["Tout"] = true,
    },
    IT = {
        ["Formula:"] = true,
    },
}

local standaloneKeywordMap = {
    DA = {
        ["nyopstartet guild"] = true,
        ["ønsker at hygge"] = true,
    },
    PL = {
        ["rekrutuje"] = true,
        ["Zapraszamy"] = true,
        ["grupy rajdowe"] = true,
    },
    CZSK = {
        ["CZ/SK"] = true,
        ["SK/CZ"] = true,
        ["Hledám skupinu"] = true,
        ["Hledam skupinu"] = true,
        ["Hľadám skupinu"] = true,
        ["Hladam skupinu"] = true,
        ["Hledáme hráče"] = true,
        ["Hledáme nové"] = true,
        ["Hledame nove"] = true,
        ["Hledame hrace"] = true,
        ["Hľadáme hráčov"] = true,
        ["Hladame hracov"] = true,
        ["Hľadá nových členov"] = true,
        ["Hlada novych clenov"] = true,
        ["Hledá nové členy"] = true,
        ["Hleda nove cleny"] = true,
        ["Napíšte pre viac info"] = true,
        ["Napiste pre viac info"] = true,
        ["Zdravíme všetkých"] = true,
        ["Zdravime vsetkych"] = true,
        ["Česká guilda"] = true,
        ["Ceska guilda"] = true,
        ["Slovenská guilda"] = true,
        ["Slovenska guilda"] = true,
    },
    NL = {
        ["Ik zoek"] = true,
        ["Wij zoeken"] = true,
        ["Zoek groep"] = true,
        ["zoekt"] = true,
        ["leden voor versterking"] = true,
        ["Nederlandse"] = true,
        ["Nederlandstalige"] = true,
        ["Nederlands"] = true,
        ["Fluister mij"] = true,
        ["Fluister me"] = true,
        ["Goedemorgen"] = true,
        ["Goedenavond"] = true,
        ["Dankjewel"] = true,
        ["Bedankt"] = true,
    },
    DE = {
        ["sucht"] = true,
        ["Danke"] = true,
        ["Dankeschön"] = true,
        ["Dankeschoen"] = true,
        ["suchen"] = true,
        ["gesucht"] = true,
        ["Eule"] = true,
        ["Vortexe"] = true,
    },
    ES = {
        ["Banda"] = true,
        ["Nosotros también"] = true,
        ["Nosotros tambien"] = true,
        ["Únete a"] = true,
        ["Unete a"] = true,

    },
    FR = {
        ["Bonsoir"] = true,
    },
    PT = {
        ["Obrigado"] = true,
        ["Obrigada"] = true,
    },
}

local keywordMap = {
    CZSK = {
        "CZ/SK",
        "SK/CZ",
        "Hledám skupinu",
        "Hledam skupinu",
        "Hľadám skupinu",
        "Hladam skupinu",
        "Hledáme hráče",
        "Hledáme nové",
        "Hledame nove",
        "Hledame hrace",
        "Hľadáme hráčov",
        "Hladame hracov",
        "Hľadá nových členov",
        "Hlada novych clenov",
        "Hledá nové členy",
        "Hleda nove cleny",
        "Napíšte pre viac info",
        "Napiste pre viac info",
        "Zdravíme všetkých",
        "Zdravime vsetkych",
        "Česká guilda",
        "Ceska guilda",
        "Slovenská guilda",
        "Slovenska guilda",
    },
    NL = {
        "Ik zoek",
        "Wij zoeken",
        "Zoek groep",
        "zoekt",
        "leden voor versterking",
        "Nederlandse",
        "Nederlandstalige",
        "Nederlands",
        "Fluister mij",
        "Fluister me",
        "Goedemorgen",
        "Goedenavond",
        "Dankjewel",
        "Bedankt",
    },
    DE = {
        "Suche Gruppe",
        "Suche eine Gruppe",
        "Suche einen Tank",
        "Suche einen Heiler",
        "Suchen noch einen",
        "Brauchen noch einen",
        "Uns fehlt noch",
        "Wer kommt mit",
        "Hat jemand Lust",
        "Kann jemand helfen",
        "Kann mir jemand helfen",
        "Kannst du mich einladen",
        "Bitte einladen",
        "Danke für die Gruppe",
        "Danke fuer die Gruppe",
        "Vielen Dank",
        "Danke",
        "Dankeschön",
        "Dankeschoen",
        "Bin gleich da",
        "Bin unterwegs",
        "Einen Moment bitte",
        "Guten Morgen",
        "Guten Abend",
        "Bis gleich",
        "Bis später",
        "Bis spaeter",
        "Auf der Suche nach",
        "sucht",
        "suchen",
        "gesucht",
        "für",
        "heute",
        "morgen",
        "Gilde",
        "Raidplätze",
        "Verstärkung",
        "Unterstützung",
        "Spieler",
        "melden",
        "gerne",
        "Interesse",
        "deutschsprachige",
        "Raidzeiten",
        "Raidtage",
        "Stammgruppe",
        "Mitspieler",
        "Schamanen",
        "Schurke",
        "Schloss knacken",
        "Eule",
        "Stiefel",
        "Handschuhe",
        "Brust",
        "Gürtel",
        "Muster",
        "Schatten",
        "Willenskraft",
        "Stärke",
        "Ausdauer",
        "Todesminen",
        "Schlachtzug",
        "Verzauberkunst:",
        "Formel:",
        "Rezept:",
        "Alchimie:",
        "Schmiedekunst:",
        "Schneiderei:",
        "Juwelenschleifen:",
        "Juwelierskunst",
        "Vorlage:",
        "Pläne:",
        "Lebendiger Rubin",
        "Königliches Nachtauge",
        "Philosophenstein",
        "Arkanittransmutation",
        "Friedensblume",
        "Silberblatt",
        "Erdwurzel",
        "Maguskönigskraut",
        "Wilddornrose",
        "Würgetang",
        "Beulengras",
        "Wildstahlblume",
        "Grabmoos",
        "Königsblut",
        "Lebenswurz",
        "Blassblatt",
        "Golddorn",
        "Khadgars Schnurrbart",
        "Winterbiss",
        "Feuerblüte",
        "Lila Lotus",
        "Arthas' Tränen",
        "Sonnengras",
        "Blindkraut",
        "Geisterpilz",
        "Bergsilberweisling",
        "Pestblüte",
        "Eiskappe",
        "Schwarzer Lotus",
        "Leinenstoff",
        "Wollstoff",
        "Seidenstoff",
        "Magiestoff",
        "Runenstoff",
        "Leichtes Leder",
        "Mittleres Leder",
        "Schweres Leder",
        "Dickes Leder",
        "Robustes Leder",
        "Kupfererz",
        "Zinnerz",
        "Eisenerz",
        "Mithrilerz",
        "Thoriumerz",
        "Arkanitbarren",
        "Waffe - Mungo",
        "Waffe - Zauberkraft",
        "Waffe - Mächtige Intelligenz",
        "Waffe - Erhebliche Zaubermacht",
        "Waffe - Kreuzfahrer",
        "Stiefel - Schnelligkeit der Katze",
        "Stiefel - Flinkheit des Ebers",
        "Armschiene - Seelenstärke",
        "Außergewöhnliche Werte",
        "Handschuhe - Überragende Beweglichkeit",
        "Teufelsgehärteter Schlägel",
        "Zauberfaden",
        "Runenverzierter Zauberfaden",
        "Roter Gürtel der Schlacht",
        "Nethervortex",
        "Vortexe",
    },
    ES = {
        "Busco un grupo",
        "Buscamos un tanque",
        "Nos falta un tanque",
        "Nos falta un healer",
        "Nos falta uno",
        "Falta un tanque",
        "Alguien para mazmorras",
        "Quien se apunta",
        "Quién se apunta",
        "Puedes invitarme",
        "Me puedes invitar",
        "Invita por favor",
        "Voy de camino",
        "Ya estoy listo",
        "Ya estoy lista",
        "Un momento por favor",
        "Gracias por el grupo",
        "Muchas gracias",
        "Buenas tardes",
        "Buenas noches",
        "Hasta luego",
        "Buenos días",
        "Buenos dias",
        "Nosotros también",
        "Nosotros tambien",
        "Únete a",
        "Unete a",
        "Busco grupo",
        "Mazmorra",
        "Banda",
        "recluta",
        "roster fijo",
        "Tanque",
        "Druida Pollo",
        "Picaro",
        "Brujo",
        "Otras clases",
        "susurrame",
        "Fórmula:",
        "Encantar arma:",
        "Mangosta",
    },
    RU = {
        "Ищу группу",
        "Подземелье",
        "Рейд",
        "Собираю группу",
        "Собираем группу",
        "Ищем танка",
        "Нужен танк",
        "Нужен хил",
        "Нужен лекарь",
        "Нужен дд",
        "Есть место",
        "Можно в группу",
        "Возьмите в группу",
        "Пригласите в группу",
        "Кто пойдет",
        "Кто хочет пойти",
        "Еще одно место",
        "Осталось одно место",
        "Спасибо за группу",
        "Всем спасибо",
        "Я скоро буду",
        "Я уже иду",
        "Подождите минуту",
        "Помогите с заданием",
        "Всем хорошего вечера",
    },
    UA = {
        "Шукаю групу",
        "Шукаємо танка",
        "Шукаю танка",
        "Потрібен танк",
        "Потрібен хіл",
        "Нам треба танк",
        "Хто хоче піти",
        "Хто йде з нами",
        "Є вільне місце",
        "Можна до групи",
        "Запросіть у групу",
        "Запроси мене",
        "Дякую за групу",
        "Дуже дякую",
        "Зачекайте хвилину",
        "Я вже йду",
        "Гарного вечора",
        "Доброго вечора",
        "Доброго ранку",
        "До зустрічі",
    },
    FR = {
        "Je cherche un groupe",
        "Cherche un groupe",
        "On cherche un tank",
        "Il nous manque",
        "Il reste une place",
        "Qui est partant",
        "Qui veut venir",
        "Quelqu'un pour",
        "Besoin d'un tank",
        "Besoin d'un heal",
        "Peux-tu m'inviter",
        "Tu peux m'inviter",
        "Invite moi",
        "Invitez moi",
        "Je suis disponible",
        "Je suis en route",
        "J'arrive dans",
        "Attendez moi",
        "Merci pour le groupe",
        "Merci beaucoup",
        "Bonne soirée",
        "Bonne soiree",
        "Bonsoir",
        "À bientôt",
        "A bientot",
        "Recherche groupe",
        "Bonjour",
        "recrute",
        "Recrute",
        "chasseur",
        "équi",
        "Démo",
        "Jeudi",
        "Dimanche",
        "Contactez-moi",
        "informations",
        "contenu",
        "depuis",
        "semaine",
        "Tout",
        "pour",
        "son",
        "à",
        "Donjon",
        "Enchantement",
        "Ench. d'arme",
        "Ench. de cape",
        "Ench. de gants",
        "Ench. d'anneau",
        "Ceinture",
        "Agilité excellente",
        "Puissance des sorts majeure",
        "Formule :",
        "Alchimie :",
        "Joaillerie",
        "Rubis vivant",
        "Pierre philosophale",
        "Transmutation d'arcanite",
        "Pacifique",
        "Feuillargent",
        "Terrestrine",
        "Mage royal",
        "Eglantine",
        "Etouffante",
        "Doulourante",
        "Aciérite sauvage",
        "Sang-royal",
        "Viétérule",
        "Pâlerette",
        "Dorépine",
        "Moustache de Khadgar",
        "Hivernale",
        "Fleur de feu",
        "Lotus pourpre",
        "Larmes d'Arthas",
        "Soleillette",
        "Aveuglette",
        "Champignon fantôme",
        "Gromsang",
        "Sansam doré",
        "Feuillerêve",
        "Sauge-argent des montagnes",
        "Fleur de peste",
        "Chapeglace",
        "Lotus noir",
        "Étoffe de lin",
        "Étoffe de laine",
        "Étoffe de soie",
        "Étoffe de tisse-mage",
        "Étoffe runique",
        "Cuir léger",
        "Cuir moyen",
        "Cuir lourd",
        "Cuir épais",
        "Cuir robuste",
        "Minerai de cuivre",
        "Minerai d'étain",
        "Minerai de fer",
        "Minerai de mithril",
        "Minerai de thorium",
        "Barre d'arcanite",
        "Vortex du Néant",
    },
    IT = {
        "Cerco un gruppo",
        "Ci manca un tank",
        "Ci manca un healer",
        "Cerchiamo un tank",
        "Qualcuno per una",
        "Puoi invitarmi",
        "Mi puoi invitare",
        "Invitatemi per favore",
        "Grazie per il gruppo",
        "Grazie mille",
        "Sto arrivando",
        "Sono pronto",
        "Sono pronta",
        "Un attimo per favore",
        "Buona serata",
        "Cerco gruppo",
        "Cerchiamo giocatori",
        "Gilda italiana",
        "Sussurrami",
        "Incantamento:",
        "Formula:",
        "Ricetta:",
    },
    SV = {
        "Söker grupp",
        "Söker spelare",
        "Svensk guild",
        "Rekryterar",
        "Viska mig",
        "Fängelsehåla",
    },
    NO = {
        "Leter etter gruppe",
        "Leter etter spillere",
        "Norsk guild",
        "Rekrutterer",
        "Hvisk meg",
        "Fangehull",
    },
    DA = {
        "Søger gruppe",
        "Søger spillere",
        "Dansk guild",
        "nyopstartet guild",
        "ønsker at hygge",
        "Rekrutterer",
        "Hvisk mig",
        "Fangehul",
    },
    TR = {
        "Grup arıyorum",
        "Oyuncu arıyoruz",
        "Türk loncası",
        "Bana fısılda",
        "Zindan grubu",
    },
    PL = {
        "[PL]",
        "rekrutuje",
        "Zapraszamy",
        "grupy rajdowe",
        "Szukam grupy",
        "Szukamy graczy",
        "Polska gildia",
        "Napisz do mnie",
        "Grupa do lochów",
    },
    PT = {
        "Procuro um grupo",
        "Procuramos um tanque",
        "Falta um tanque",
        "Precisamos de um tank",
        "Precisamos de um healer",
        "Alguem para masmorra",
        "Alguém para masmorra",
        "Pode me convidar",
        "Podes convidar-me",
        "Me convida por favor",
        "Obrigado pelo grupo",
        "Obrigada pelo grupo",
        "Muito obrigado",
        "Muito obrigada",
        "Obrigado",
        "Obrigada",
        "Estou a caminho",
        "Estou chegando",
        "Boa noite",
        "Bom dia",
        "Ate logo",
        "Até logo",
        "Procuro grupo",
        "Procuramos jogadores",
        "Recrutando jogadores",
        "Guilda portuguesa",
        "Manda mensagem",
        "Grupo para masmorra",
    },
}

local petOwnersByGUID = {}
local petOwnerGUIDCount = 0
local PET_OWNER_GUID_CACHE_LIMIT = 1000
local keywordEntryCache = {}
local UPPER_TO_LOWER = {
    { "À", "à" },
    { "Á", "á" },
    { "Â", "â" },
    { "Ã", "ã" },
    { "Ä", "ä" },
    { "Å", "å" },
    { "Æ", "æ" },
    { "Ç", "ç" },
    { "Ć", "ć" },
    { "È", "è" },
    { "É", "é" },
    { "Ê", "ê" },
    { "Ë", "ë" },
    { "Ğ", "ğ" },
    { "Í", "í" },
    { "Î", "î" },
    { "Ï", "ï" },
    { "İ", "i" },
    { "Ł", "ł" },
    { "Ń", "ń" },
    { "Ñ", "ñ" },
    { "Ó", "ó" },
    { "Ô", "ô" },
    { "Ö", "ö" },
    { "Õ", "õ" },
    { "Ø", "ø" },
    { "Œ", "œ" },
    { "Ś", "ś" },
    { "Ş", "ş" },
    { "Ù", "ù" },
    { "Ú", "ú" },
    { "Û", "û" },
    { "Ü", "ü" },
    { "Ÿ", "ÿ" },
    { "Ź", "ź" },
    { "Ż", "ż" },
    { "Ą", "ą" },
    { "Ę", "ę" },
    { "ẞ", "ß" },
    { "А", "а" },
    { "Б", "б" },
    { "В", "в" },
    { "Г", "г" },
    { "Д", "д" },
    { "Е", "е" },
    { "Ё", "ё" },
    { "Ж", "ж" },
    { "З", "з" },
    { "И", "и" },
    { "Й", "й" },
    { "К", "к" },
    { "Л", "л" },
    { "М", "м" },
    { "Н", "н" },
    { "О", "о" },
    { "П", "п" },
    { "Р", "р" },
    { "С", "с" },
    { "Т", "т" },
    { "У", "у" },
    { "Ф", "ф" },
    { "Х", "х" },
    { "Ц", "ц" },
    { "Ч", "ч" },
    { "Ш", "ш" },
    { "Щ", "щ" },
    { "Ъ", "ъ" },
    { "Ы", "ы" },
    { "Ь", "ь" },
    { "Э", "э" },
    { "Ю", "ю" },
    { "Я", "я" },
    { "І", "і" },
    { "Ї", "ї" },
    { "Є", "є" },
    { "Ґ", "ґ" },
}

local function ForgetPetOwner(petGUID)
    if petGUID and petOwnersByGUID[petGUID] ~= nil then
        petOwnersByGUID[petGUID] = nil
        petOwnerGUIDCount = math.max(0, petOwnerGUIDCount - 1)
    end
end

local function RememberPetOwner(petGUID, ownerKey)
    if not petGUID or not ownerKey then
        return
    end

    if petOwnersByGUID[petGUID] == nil then
        if petOwnerGUIDCount >= PET_OWNER_GUID_CACHE_LIMIT then
            wipe(petOwnersByGUID)
            petOwnerGUIDCount = 0
        end
        petOwnerGUIDCount = petOwnerGUIDCount + 1
    end

    petOwnersByGUID[petGUID] = ownerKey
end

local function MarkAutoDetectKeywordsDirty(lang)
    if ns.ClearAutoDetectTextCache then
        ns.ClearAutoDetectTextCache()
    end
    if lang then
        keywordEntryCache[lang] = nil
        return
    end

    for cacheLang in pairs(keywordEntryCache) do
        keywordEntryCache[cacheLang] = nil
    end
end

ns.MarkAutoDetectKeywordsDirty = MarkAutoDetectKeywordsDirty

local utf8LowerLookup = {}
for _, replacement in ipairs(UPPER_TO_LOWER) do
    utf8LowerLookup[replacement[1]] = replacement[2]
end

local function Lower(value)
    if ns.IsSecret(value) or not value then
        return
    end

    local lowered = string.lower(value)
    if not lowered:find("[\128-\255]") then
        return lowered
    end

    -- Normalize complete UTF-8 Latin and Cyrillic characters in one pass;
    -- Lua's built-in lowercasing only handles ASCII. Unmapped letters stay intact.
    lowered = lowered:gsub("[\194-\244][\128-\191]+", utf8LowerLookup)

    return lowered
end

local function GetKeywordScore(lang, word)
    if not lang or not word then
        return DEFAULT_KEYWORD_SCORE
    end

    if lowConfidenceKeywordMap[lang] and lowConfidenceKeywordMap[lang][word] then
        return 1
    end

    return DEFAULT_KEYWORD_SCORE
end

local TOKEN_SEPARATORS = {
    ["’"] = " ", ["‘"] = " ", ["“"] = " ", ["”"] = " ",
    ["–"] = " ", ["—"] = " ", ["‑"] = " ", ["…"] = " ",
    ["¿"] = " ", ["¡"] = " ", ["«"] = " ", ["»"] = " ",
    ["\194\160"] = " ", -- non-breaking space
    ["\226\128\175"] = " ", -- narrow non-breaking space
}

local function NormalizeTokenText(value)
    if not value or value == "" then
        return ""
    end

    local normalized = value
    if normalized:find("[\128-\255]") then
        normalized = normalized:gsub("[\194-\244][\128-\191]+", TOKEN_SEPARATORS)
    end
    normalized = normalized:gsub("[%s%p]+", " ")
    return " " .. normalized .. " "
end

local function HasCyrillic(value)
    return value and value:find("[\208-\211][\128-\191]") ~= nil
end

local UKRAINIAN_SPECIFIC_CHARACTERS = { "і", "І", "ї", "Ї", "є", "Є", "ґ", "Ґ" }
local RUSSIAN_SPECIFIC_CHARACTERS = { "ы", "Ы", "э", "Э", "ъ", "Ъ", "ё", "Ё" }
local TURKISH_SPECIFIC_CHARACTERS = { "ğ", "Ğ", "ı", "İ", "ş", "Ş" }
local POLISH_SPECIFIC_CHARACTERS = { "ą", "Ą", "ę", "Ę", "ł", "Ł", "ń", "Ń", "ś", "Ś", "ź", "Ź", "ż", "Ż" }
local PORTUGUESE_SPECIFIC_CHARACTERS = { "ã", "Ã", "õ", "Õ" }

local function ContainsAnyCharacter(value, characters)
    if not value or value == "" then
        return false
    end

    for _, character in ipairs(characters) do
        if value:find(character, 1, true) then
            return true
        end
    end

    return false
end

local function ContainsUkrainianSpecificCharacters(value)
    return ContainsAnyCharacter(value, UKRAINIAN_SPECIFIC_CHARACTERS)
end

local function ContainsRussianSpecificCharacters(value)
    return ContainsAnyCharacter(value, RUSSIAN_SPECIFIC_CHARACTERS)
end

local function ContainsTurkishSpecificCharacters(value)
    return ContainsAnyCharacter(value, TURKISH_SPECIFIC_CHARACTERS)
end

local function ContainsPolishSpecificCharacters(value)
    return ContainsAnyCharacter(value, POLISH_SPECIFIC_CHARACTERS)
end

local function ContainsPortugueseSpecificCharacters(value)
    return ContainsAnyCharacter(value, PORTUGUESE_SPECIFIC_CHARACTERS)
end

local function ContainsSpanishEnye(value)
    if not value or value == "" then
        return false
    end

    return value:find("ñ", 1, true) ~= nil or value:find("Ñ", 1, true) ~= nil
end

local function ContainsKeyword(text, loweredText, normalizedTokenText, word, loweredWord, requireStandalone, standaloneWord)
    if not word or word == "" then
        return false
    end

    if requireStandalone then
        local standaloneText = normalizedTokenText or NormalizeTokenText(loweredText or text)
        return standaloneText:find(standaloneWord, 1, true) ~= nil
    end

    if word ~= loweredWord and text and text:find(word, 1, true) then
        return true
    end

    if loweredText and loweredWord and loweredText:find(loweredWord, 1, true) then
        return true
    end

    return false
end

local function AddKeywordEntry(entries, lang, word)
    local keywordScore = GetKeywordScore(lang, word)
    -- Phrases match ordered, complete words after punctuation/space normalization.
    local requireStandalone = keywordScore < DEFAULT_KEYWORD_SCORE
        or (standaloneKeywordMap[lang] and standaloneKeywordMap[lang][word])
        or word:find("%s") ~= nil
    local loweredWord = Lower(word)
    local standaloneWord = requireStandalone and NormalizeTokenText(loweredWord or word) or nil

    local entry = {
        word = word,
        loweredWord = loweredWord,
        keywordScore = keywordScore,
        requireStandalone = requireStandalone,
        standaloneWord = standaloneWord,
        standaloneToken = standaloneWord and standaloneWord:match("^ ([^ ]+) $") or nil,
        order = #entries + 1,
    }
    entries[#entries + 1] = entry
    if entry.standaloneToken then
        local tokenEntries = entries.byToken[entry.standaloneToken]
        if not tokenEntries then
            tokenEntries = {}
            entries.byToken[entry.standaloneToken] = tokenEntries
        end
        tokenEntries[#tokenEntries + 1] = entry
    else
        entries.substringEntries[#entries.substringEntries + 1] = entry
    end
end

local function GetKeywordEntriesForLanguage(lang)
    if not lang then
        return {}
    end

    local cachedEntries = keywordEntryCache[lang]
    if cachedEntries then
        return cachedEntries
    end

    local entries = { byToken = {}, substringEntries = {} }
    for _, word in ipairs(keywordMap[lang] or {}) do
        AddKeywordEntry(entries, lang, word)
    end

    EnsureAutoDetectWordsTable()
    local customWords = LanguageScoutDB.autoDetectWords[lang]
    for _, word in ipairs(customWords or {}) do
        AddKeywordEntry(entries, lang, word)
    end

    keywordEntryCache[lang] = entries
    return entries
end

local function DetectLanguageFromText(text, reasonKey, ignoreLanguageOptions)
    if ns.IsSecret(text) then return end
    if not text or text == "" then
        return
    end

    -- Every character-specific signal is non-ASCII. Most LFG messages can
    -- skip all these scans.
    if text:find("[\128-\255]") then
        if ContainsUkrainianSpecificCharacters(text) then
            if ignoreLanguageOptions or IsLanguageAutoDetectEnabled("UA") then
                return "UA", string.format(L(reasonKey or "AUTO_REASON_CHAT_KEYWORD"), "і/ї/є/ґ")
            end
            return
        end

        if ContainsRussianSpecificCharacters(text) then
            if ignoreLanguageOptions or IsLanguageAutoDetectEnabled("RU") then
                return "RU", string.format(L(reasonKey or "AUTO_REASON_CHAT_KEYWORD"), "ы/э/ъ/ё")
            end
            return
        end

        if ContainsTurkishSpecificCharacters(text) then
            if ignoreLanguageOptions or IsLanguageAutoDetectEnabled("TR") then
                return "TR", string.format(L(reasonKey or "AUTO_REASON_CHAT_KEYWORD"), "ğ/ı/ş")
            end
            return
        end

        if ContainsPolishSpecificCharacters(text) then
            if ignoreLanguageOptions or IsLanguageAutoDetectEnabled("PL") then
                return "PL", string.format(L(reasonKey or "AUTO_REASON_CHAT_KEYWORD"), "ą/ę/ł/ż/ź")
            end
            return
        end

        if ContainsPortugueseSpecificCharacters(text) then
            if ignoreLanguageOptions or IsLanguageAutoDetectEnabled("PT") then
                return "PT", string.format(L(reasonKey or "AUTO_REASON_CHAT_KEYWORD"), "ã/õ")
            end
            return
        end

        if (ignoreLanguageOptions or IsLanguageAutoDetectEnabled("ES")) and ContainsSpanishEnye(text) then
            return "ES", string.format(L(reasonKey or "AUTO_REASON_CHAT_KEYWORD"), "ñ")
        end
    end

    local loweredText = Lower(text)
    local normalizedTokenText = NormalizeTokenText(loweredText)
    local tokenLookup = {}
    for token in normalizedTokenText:gmatch("[^ ]+") do
        tokenLookup[token] = true
    end
    local bestLang
    local bestReason
    local bestScore = 0
    local bestKeywordScore = 0
    local hasTie = false

    for _, lang in ipairs(SUPPORTED_LANGUAGES) do
        if ignoreLanguageOptions or IsLanguageAutoDetectEnabled(lang) then
            local score = 0
            local matchedKeyword
            local matchedKeywordScore = 0
            local matchedOrder = math.huge
            local entries = GetKeywordEntriesForLanguage(lang)

            -- Match whole words by looking up the message's tokens rather than
            -- searching the full message once for every standalone keyword.
            for token in pairs(tokenLookup) do
                local tokenEntries = entries.byToken[token]
                if tokenEntries then
                    for _, keyword in ipairs(tokenEntries) do
                        local keywordScore = keyword.keywordScore
                        score = score + keywordScore
                        if keywordScore > matchedKeywordScore
                            or (keywordScore == matchedKeywordScore and keyword.order < matchedOrder)
                        then
                            matchedKeyword = keyword.word
                            matchedKeywordScore = keywordScore
                            matchedOrder = keyword.order
                        end
                    end
                end
            end

            for _, keyword in ipairs(entries.substringEntries) do
                local word = keyword.word
                local keywordScore = keyword.keywordScore

                if ContainsKeyword(text, loweredText, normalizedTokenText, word, keyword.loweredWord, keyword.requireStandalone, keyword.standaloneWord) then
                    score = score + keywordScore

                    if keywordScore > matchedKeywordScore
                        or (keywordScore == matchedKeywordScore and keyword.order < matchedOrder)
                    then
                        matchedKeyword = word
                        matchedKeywordScore = keywordScore
                        matchedOrder = keyword.order
                    end
                end
            end

            if score >= MIN_LANGUAGE_SCORE then
                if score > bestScore or (score == bestScore and matchedKeywordScore > bestKeywordScore) then
                    bestLang = lang
                    bestReason = matchedKeyword and string.format(L(reasonKey or "AUTO_REASON_CHAT_KEYWORD"), matchedKeyword)
                    bestScore = score
                    bestKeywordScore = matchedKeywordScore
                    hasTie = false
                elseif score == bestScore and matchedKeywordScore == bestKeywordScore then
                    hasTie = true
                end
            end
        end
    end

    if bestLang and not hasTie then
        return bestLang, bestReason
    end
end

local AUTO_DETECT_SELF_TEST_CASES = {
    { text = "<Knejt Nejt> er en guild for de danske knejte og knejtinder. Vi er en social guild, der ønsker at hygge omkring spillet, og nyde alle aspekterne af WoW Forever. I længden ønsker vi at raide. Kom glad! /W for invite!", expected = "DA" },
    { text = "Goedemorgen! <Tsunami> Zoekt nederlandse spelers. Wij bestaan al vanaf 2004. Actief geweest in retail en classic en nu in Forever. Kom gezellig levelen en dungeons doen! /w voor een invite.", expected = "NL" },
    { text = "[Knejt Nejt] er en nyopstartet guild for de danske knejte og knejtinder. Vi er en social guild, der ønsker at hygge omkring spillet, og nyde alle aspekterne af WoW Forever. I længden ønsker vi at raide. Kom glad!", expected = "DA" },
    { text = "Er du træt af hardcore krav? BridgeBurner er en nyopstartet guild lavet af nogle kammerater. Vores fokus er 100% casual til en start – vi vil bare gerne hygge, køre dungeons sammen og tage spillet i eget tempo. Perfekt til dig med job/familie.", expected = "DA" },
    { text = "WTS SW 8 slots bag for 2 silver and 8 linen cloth", expected = nil },
    { text = "<Ridders van Oranje> recruiten Nederlands & Vlaams sprekende spelers die op zoek zijn naar een gezellige social raiding guild. /w for inv", expected = "NL" },
    { text = "*** GUARDIANDS OF ETERNITY ***   hledáme nové kámoše do malé guildy, kde hlavni prioritou je malá a verna komunita hrácu, kteri si vzajemne pomahaji.", expected = "CZSK" },
    { text = "Hledame nove kamose do male guildy", expected = "CZSK" },
    { text = "[PL] <Drama Club> rekrutuje! Tworzymy grupy rajdowe na roznych poziomach zaawansowania – od casual po hardcore. Zapraszamy wszystkie klasy i specy! Wiecej info na /w lub Discordzie.", expected = "PL" },
    { text = "<Drama Club> rekrutuje! Tworzymy grupy rajdowe na roznych poziomach zaawansowania – od casual po hardcore. Zapraszamy wszystkie klasy i specy! Wiecej info na /w lub Discordzie.", expected = "PL" },
    { text = "[pl] guild recruiting", expected = "PL" },
    { text = "REKRUTUJE!", expected = "PL" },
    { text = "We need more supplies for the raid.", expected = nil },
    { text = "PL is a player abbreviation.", expected = nil },

    { text = "Balkanski Guild <Banda Zlih Bureka> vrši regurtaciju novih članova. Javite se za više informacija :)", expected = nil },
    { text = "Banda", expected = nil },
    { text = "Banda banda BANDA", expected = nil },
    { text = "Busco banda, susurrame para más información", expected = "ES" },

    { text = "Eres feo? Nosotros tambien. Unete a <La Liga de los Hombres feos> y nos damos amor mutuo", expected = "ES" },
    { text = "NOSOTROS TAMBIÉN. ÚNETE A nuestra hermandad.", expected = "ES" },
    { text = "We can reunete a party later.", expected = nil },
    { text = "Mutual love for our guild.", expected = nil },

    { text = "<CZ/SK> guilda Evil Corp hlada novych clenov. Napiste pre viac info :)", expected = "CZSK" },
    { text = "Zdravime vsetkych (CZ/SK) Pozyvame ta k (nam.Ci) si ostrielany hrác alebo si práve zacal s hrou. Sme  Nase Gilda a radi privítame kazdeho kto si rad (zahra.Pripoj) sa k nam priamo v hre alebo (https://discord.gg/jHcKCFdaU)", expected = "CZSK" },
    { text = "Hledám skupinu na dungeon", expected = "CZSK" },
    { text = "Hladam skupinu na dungeon", expected = "CZSK" },
    { text = "Hľadáme hráčov do guildy", expected = "CZSK" },
    { text = "Hledame hrace do guildy", expected = "CZSK" },
    { text = "(SK/CZ) guild recruiting", expected = "CZSK" },
    { text = "CZ-SK guild recruiting", expected = "CZSK" },
    { text = "LF tank for a dungeon", expected = nil },
    { text = "CZ skirmish team needs a healer", expected = nil },
    { text = "Ask/CZar is a player name", expected = nil },
    { text = "Hladam skupinulol", expected = nil },

    { text = "<Tsunami> Zoekt nederlandse spelers. Wij bestaan al vanaf 2004 actief geweest in retail en classic en nu in Forever. Kom gezellig levelen en dungeons doen! /w voor een invite.", expected = "NL" },
    { text = "Ik zoek een groep voor een dungeon", expected = "NL" },
    { text = "Wij zoeken spelers voor onze guild", expected = "NL" },
    { text = "ZOEK GROEP voor Karazhan", expected = "NL" },
    { text = "Nederlandstalige guild zoekt leden", expected = "NL" },
    { text = "<SOUP> zoekt altijd nog NL/BE leden voor versterking ;) whisp voor invite ^^", expected = "NL" },
    { text = "LF tank, whisp voor invite ^^", expected = nil },
    { text = "Fluister mij voor meer informatie", expected = "NL" },
    { text = "Goedemorgen, allemaal!", expected = "NL" },
    { text = "Dankjewel!", expected = "NL" },
    { text = "We bedankthed the tank.", expected = nil },
    { text = "Nederlandstaliger is a made-up test token.", expected = nil },
    { text = "Ich suche eine Gruppe.", expected = "DE" },

    { text = "Привіт, шукаю групу", expected = "UA" },
    { text = "Ищу группу у подъезда", expected = "RU" },
    { text = "Ищу группу", expected = "RU" },
    { text = "Suche Gruppe für Todesminen", expected = "DE" },
    { text = "Bonjour, notre guilde recrute", expected = "FR" },
    { text = "Busco grupo para mazmorra", expected = "ES" },
    { text = "Cerco gruppo per incursione", expected = "IT" },
    { text = "Söker grupp till fängelsehåla", expected = "SV" },
    { text = "Leter etter gruppe til fangehull", expected = "NO" },
    { text = "Søger gruppe til fangehul", expected = "DA" },
    { text = "Grup arıyorum, bana fısılda", expected = "TR" },
    { text = "Szukam grupy do lochów", expected = "PL" },
    { text = "Procuro grupo para masmorra", expected = "PT" },
    { text = "Recrutando jogadores para a guilda", expected = "PT" },
    { text = "Ищу группу в рейд", expected = "RU" },
    { text = "привет всем", expected = nil },
    { text = "добро", expected = nil },
    { text = "mañana buscamos grupo", expected = "ES" },
    { text = "étoffe de lin", expected = "FR" },
    { text = "WAFFE - MÄCHTIGE INTELLIGENZ", expected = "DE" },
    { text = "I'm at shatrah if someone need [Ench. de cape (Défense excellente)] i've 8 ench for free", expected = "FR" },
    { text = "wtb [Rezept: Fläschchen der obersten Macht] 150G", expected = "DE" },
    { text = "lf [Formel: Waffe - Zauberkraft] one trade", expected = "DE" },
    { text = "LF Enchanter with [Fórmula: encantar arma: mangosta]", expected = "ES" },
    { text = "WTS [Plans: Mithril Spurs]-[Formula: Enchant 2H Weapon - Major Intellect]-[Formula: Enchant Bracer - Greater Stamina]", expected = nil },
    { text = "Vortexe gegen Urnether", expected = "DE" },
    { text = "<Dinolovers> LF Feral, Ret Pala & Ele or BM Hunter TK+SSC Mon 10th @ 20:25st. Raiders mostly BiS except for big items so mostly LF players happy to HR tier tokens, vortexes, patterns and other non big ticket items. /w for more info!", expected = nil },
    { text = "Brust", expected = nil },
    { text = "Brust gesucht", expected = "DE" },
    { text = "we are looking for more players", expected = nil },
    { text = "Er versucht es morgen.", expected = nil },
    { text = "Need a bandage for the tank.", expected = nil },
    { text = "Eine Beule am Kopf.", expected = nil },

    { text = "Kann mir jemand helfen bei dieser Quest?", expected = "DE" },
    { text = "Wir brauchen noch einen Tank, dann geht es los.", expected = "DE" },
    { text = "BITTE,   EINLADEN!", expected = "DE" },
    { text = "Danke fuer die Gruppe!", expected = "DE" },
    { text = "DANKESCHÖN!", expected = "DE" },
    { text = "Je cherche un groupe pour ce soir.", expected = "FR" },
    { text = "Quelqu’un pour une instance ?", expected = "FR" },
    { text = "Tu peux m’inviter ?", expected = "FR" },
    { text = "merci—beaucoup!", expected = "FR" },
    { text = "BONNE SOIRÉE à tous!", expected = "FR" },
    { text = "Nos falta un tanque, alguien viene?", expected = "ES" },
    { text = "Me puedes invitar al grupo?", expected = "ES" },
    { text = "¿Me puedes invitar al grupo?", expected = "ES" },
    { text = "¡MUCHAS GRACIAS!", expected = "ES" },
    { text = "VOY... DE   CAMINO!", expected = "ES" },
    { text = "Muchas gracias por la ayuda!", expected = "ES" },
    { text = "Нужен танк в данж", expected = "RU" },
    { text = "НУЖЕН...ТАНК", expected = "RU" },
    { text = "спасибо за группу!", expected = "RU" },
    { text = "пригласите   в группу", expected = "RU" },
    { text = "ищу группу на вечер", expected = "RU" },
    { text = "Шукаю танка до нас", expected = "UA" },
    { text = "ДУЖЕ\tДЯКУЮ!", expected = "UA" },
    { text = "можна до групи?", expected = "UA" },
    { text = "зачекайте хвилину", expected = "UA" },
    { text = "Cerco un gruppo per stasera", expected = "IT" },
    { text = "Ci manca un tank per partire", expected = "IT" },
    { text = "GRAZIE---MILLE!", expected = "IT" },
    { text = "Puoi invitarmi per favore?", expected = "IT" },
    { text = "Procuro um grupo para hoje", expected = "PT" },
    { text = "podes convidar-me?", expected = "PT" },
    { text = "muito\194\160obrigado!", expected = "PT" },
    { text = "Estou a caminho, um minuto", expected = "PT" },

    { text = "LF tank and healer, invite please", expected = nil },
    { text = "Thanks for the group, see you later!", expected = nil },
    { text = "Group ready? Need one more player for a raid.", expected = nil },
    { text = "gg wp brb afk lol", expected = nil },
    { text = "pour pour pour", expected = nil },
    { text = "beaucoup merci", expected = nil },
    { text = "Please thank Danker for the invite.", expected = nil },
    { text = "We invited Obrigadofoo to the party.", expected = nil },
    { text = "cherche un groupex", expected = nil },
    { text = "ненужен танка", expected = nil },
    { text = "нешукаю танкальфа", expected = nil },
}

ns.RunAutoDetectSelfTests = function()
    local failures = {}
    local passed = 0

    for index, testCase in ipairs(AUTO_DETECT_SELF_TEST_CASES) do
        local actual = DetectLanguageFromText(testCase.text, "AUTO_REASON_CHAT_KEYWORD", true)
        if actual == testCase.expected then
            passed = passed + 1
        else
            failures[#failures + 1] = string.format(
                "#%d expected %s, got %s: %s",
                index,
                tostring(testCase.expected),
                tostring(actual),
                testCase.text
            )
        end
    end

    return passed, #AUTO_DETECT_SELF_TEST_CASES, failures
end

local localizedQuestiePrefixes = {
    {
        lang = "DE",
        tokens = {
            "quest angenommen:",
            "quest abgeschlossen:",
            "quest abgebrochen:",
        },
        tokenGroups = {
            { " aufgehoben, das ", " startet!" },
        },
    },
    {
        lang = "FR",
        tokens = {
            "quête acceptée :",
            "quete acceptee",
            "quête terminée :",
            "quete terminee",
            "quête abandonnée :",
            "quete abandonnee :",
        },
        tokenGroups = {
            { "ramassé ", " qui démarre ", " !" },
            { "ramassé ", " qui demarre ", " !" },
        },
    },
    {
        lang = "ES",
        tokens = {
            "misión aceptada:",
            "mision aceptada:",
            "misión completada:",
            "mision completada:",
            "misión abandonada:",
            "mision abandonada:",
        },
        tokenGroups = {
            { "¡recogió ", " que inicia ", "!" },
        },
    },
    {
        lang = "RU",
        tokens = {
            "задание принято:",
            "задание выполнено:",
            "задание отменено:",
        },
        tokenGroups = {
            { "получен предмет ", "который начинает задание ", "!" },
        },
    },
}

local function DetectLanguageFromQuestieAnnouncement(text)
    if not text or text == "" then
        return
    end

    local hasQuestieMarker = text:find("Questie:", 1, true)
        or text:find("Questie :", 1, true)
        or text:find("|TInterface\\Addons\\Questie\\Icons\\questie.png:0|t", 1, true)
    if not hasQuestieMarker then
        return
    end

    local loweredText = Lower(text)
    if not loweredText then
        return
    end

    for _, pattern in ipairs(localizedQuestiePrefixes) do
        if IsLanguageAutoDetectEnabled(pattern.lang) then
            for _, token in ipairs(pattern.tokens) do
                if loweredText:find(token, 1, true) then
                    return pattern.lang, L("AUTO_REASON_QUESTIE_ANNOUNCEMENT")
                end
            end

            for _, tokenGroup in ipairs(pattern.tokenGroups or {}) do
                local matchedAllTokens = true
                for _, token in ipairs(tokenGroup) do
                    if not loweredText:find(token, 1, true) then
                        matchedAllTokens = false
                        break
                    end
                end

                if matchedAllTokens then
                    return pattern.lang, L("AUTO_REASON_QUESTIE_ANNOUNCEMENT")
                end
            end
        end
    end

    local hasQuestLink = text:find("|Hquest:", 1, true) or text:find("[%[][^%]]+[%]]")
    if not hasQuestLink then
        return
    end

    local patterns = {
        -- Keep these language markers explicit and independent from the generic
        -- keyword scoring. Questie links are deterministic enough that
        -- "für"/"pour"/"para"/"для" should remain direct signals here.
        { lang = "FR", token = " pour " },
        { lang = "DE", token = " für " },
        -- Questie uses "para" for both esES/esMX and ptBR. Since LanguageScout
        -- does not support PT-BR, we map this pattern to ES.
        { lang = "ES", token = " para " },
        { lang = "RU", token = " для " },
    }

    for _, pattern in ipairs(patterns) do
        if IsLanguageAutoDetectEnabled(pattern.lang) and loweredText:find(pattern.token, 1, true) then
            return pattern.lang, L("AUTO_REASON_QUESTIE_ANNOUNCEMENT")
        end
    end
end

local function DetectLanguageFromPetName(petName)
    local language, reason = DetectLanguageFromText(petName, "AUTO_REASON_PET_KEYWORD")
    if language then
        return language, reason
    end

    local loweredPetName = Lower(petName)
    if not loweredPetName or loweredPetName == "" then
        return
    end

    for _, lang in ipairs(SUPPORTED_LANGUAGES) do
        if IsLanguageAutoDetectEnabled(lang) then
            for _, defaultPetName in ipairs(PET_OWNER_KEYWORDS[lang] or {}) do
                local loweredDefaultName = Lower(defaultPetName)
                if petName == defaultPetName or (loweredDefaultName and loweredPetName == loweredDefaultName) then
                    return lang, string.format(L("AUTO_REASON_PET_DEFAULT"), defaultPetName)
                end
            end
        end
    end
end

local PET_NAME_SELF_TEST_CASES = {
    { petName = "Bär", expected = "DE" },
    { petName = "Wolf", expected = nil },
}

ns.RunPetNameSelfTests = function()
    local failures = {}
    local passed = 0

    for index, testCase in ipairs(PET_NAME_SELF_TEST_CASES) do
        local actual = DetectLanguageFromPetName(testCase.petName)
        if actual == testCase.expected then
            passed = passed + 1
        else
            failures[#failures + 1] = string.format(
                "#%d expected %s, got %s: %s",
                index,
                tostring(testCase.expected),
                tostring(actual),
                testCase.petName
            )
        end
    end

    return passed, #PET_NAME_SELF_TEST_CASES, failures
end

local function TryAutoMarkPlayer(playerKey, lang, reason)
    if not playerKey or not IsSupportedLanguage(lang) or not IsLanguageAutoDetectEnabled(lang) then
        return false
    end

    local wasAdded = AddPlayerLanguageIfMissing(playerKey, lang, "automatic")
    if wasAdded then
        ns.SyncNewPlayerLanguage(playerKey, lang)
        ShowAutoLanguageMarkedMessage(playerKey, lang, reason, true)
        return true
    end

    return false
end

local CHAT_SOURCE_KEYS = {
    CHAT_MSG_CHANNEL = "CHAT_SOURCE_CHANNEL",
    CHAT_MSG_GUILD = "CHAT_SOURCE_GUILD",
    CHAT_MSG_SAY = "CHAT_SOURCE_SAY",
    CHAT_MSG_YELL = "CHAT_SOURCE_YELL",
    CHAT_MSG_PARTY = "CHAT_SOURCE_PARTY",
    CHAT_MSG_PARTY_LEADER = "CHAT_SOURCE_PARTY",
    CHAT_MSG_RAID = "CHAT_SOURCE_RAID",
    CHAT_MSG_RAID_LEADER = "CHAT_SOURCE_RAID",
    CHAT_MSG_INSTANCE_CHAT = "CHAT_SOURCE_INSTANCE",
    CHAT_MSG_INSTANCE_CHAT_LEADER = "CHAT_SOURCE_INSTANCE",
}

local function AddChatDetectionDetails(reason, event, channelName, msg)
    if not (LanguageScoutDB and LanguageScoutDB.debugPerformance) then
        return reason
    end

    local source
    if event == "CHAT_MSG_CHANNEL" and type(channelName) == "string" and channelName ~= "" then
        source = channelName
    else
        source = L(CHAT_SOURCE_KEYS[event] or "CHAT_SOURCE_UNKNOWN")
    end

    return string.format(
        L("AUTO_REASON_CHAT_DETAILS"),
        reason or L("UNKNOWN"),
        source,
        tostring(event or "UNKNOWN"),
        type(msg) == "string" and msg or L("UNKNOWN")
    )
end

local function StorePetOwner(petUnit, ownerUnit)
    if not ns.CanInspectUnit(petUnit) or not ns.CanInspectUnit(ownerUnit) then return end
    local petGUID = petUnit and UnitGUID(petUnit)
    if not petGUID then
        return
    end

    ForgetPetOwner(petGUID)

    if not ownerUnit or not UnitExists(ownerUnit) or not UnitIsPlayer(ownerUnit) then
        return
    end

    local _, ownerClass = UnitClass(ownerUnit)
    if ownerClass ~= "HUNTER" then
        return
    end

    local ownerName, ownerRealm = ReadPlayerName(ownerUnit)
    local ownerKey = FullName(ownerName, ownerRealm)
    if ownerKey then
        RememberPetOwner(petGUID, ownerKey)
    end
end

local function StorePetOwnerByGUID(petGUID, ownerName, ownerRealm)
    if not petGUID then
        return
    end

    ForgetPetOwner(petGUID)

    local ownerKey = FullName(ownerName, ownerRealm)
    if ownerKey then
        RememberPetOwner(petGUID, ownerKey)
    end
end

ns.RefreshPetOwnerMappings = function()
    StorePetOwner("pet", "player")

    if IsInRaid and IsInRaid() then
        local count = GetNumGroupMembers and GetNumGroupMembers() or 40
        for index = 1, count do
            StorePetOwner("raidpet" .. index, "raid" .. index)
        end
    elseif IsInGroup and IsInGroup() then
        local count = GetNumSubgroupMembers and GetNumSubgroupMembers() or 4
        for index = 1, count do
            StorePetOwner("partypet" .. index, "party" .. index)
        end
    end
end

local function GetOwnerUnitFromPetUnit(unit)
    if unit == "pet" then
        return "player"
    end

    local partyIndex = unit and unit:match("^party(%d+)pet$")
    if partyIndex then
        return "party" .. partyIndex
    end

    local raidIndex = unit and unit:match("^raid(%d+)pet$")
    if raidIndex then
        return "raid" .. raidIndex
    end
end

local function ExtractOwnerNameFromTooltipText(text)
    if ns.IsSecret(text) then return end
    if not text or text == "" then
        return
    end

    local bracketText = text:match("^%s*<(.+)>%s*$")
    if not bracketText or bracketText == "" then
        return
    end

    local localizedOwnerPatterns = {
        "^(.+)'s .+$",
        "^Begleiter von (.+)$",
        "^Tier von (.+)$",
        "^Haustier von (.+)$",
        "^Mascota de (.+)$",
        "^Familier de (.+)$",
        "^Familier d['’](.+)$",
        "^Питомец (.+)$",
    }

    for _, pattern in ipairs(localizedOwnerPatterns) do
        local ownerName = bracketText:match(pattern)
        if ownerName and ownerName ~= "" then
            return NormalizePlayerKey(ownerName)
        end
    end

    return NormalizePlayerKey(bracketText)
end

local function GetHunterOwnerKeyFromTooltip(unit)
    if not unit or not UnitExists(unit) then
        return
    end

    petOwnerTooltip:ClearLines()
    petOwnerTooltip:SetUnit(unit)

    for lineIndex = 2, petOwnerTooltip:NumLines() do
        local line = _G["LanguageScoutPetOwnerTooltipTextLeft" .. lineIndex]
        local text = line and line:GetText()
        local ownerKey = ExtractOwnerNameFromTooltipText(text)
        if ownerKey then
            return ownerKey
        end
    end
end

local function GetHunterOwnerKeyForPetUnit(unit)
    if not ns.CanInspectUnit(unit) then return end
    if not unit or not UnitExists(unit) then
        return
    end

    local ownerUnit = GetOwnerUnitFromPetUnit(unit)
    if ownerUnit and UnitExists(ownerUnit) and UnitIsPlayer(ownerUnit) then
        local _, ownerClass = UnitClass(ownerUnit)
        if ownerClass == "HUNTER" then
            local ownerName, ownerRealm = ReadPlayerName(ownerUnit)
            return FullName(ownerName, ownerRealm)
        end
    end

    local petGUID = UnitGUID(unit)
    if petGUID then
        local ownerKey = petOwnersByGUID[petGUID]
        if ownerKey then
            return ownerKey
        end
    end

    local tooltipOwnerKey = GetHunterOwnerKeyFromTooltip(unit)
    if tooltipOwnerKey then
        if petGUID and ns.ParseFullName then
            local ownerName, ownerRealm = ns.ParseFullName(tooltipOwnerKey)
            StorePetOwnerByGUID(petGUID, ownerName, ownerRealm)
        end

        return tooltipOwnerKey
    end
end

local function IsPotentialPlayerPetUnit(unit)
    if not unit or not UnitExists(unit) or UnitIsPlayer(unit) then
        return false
    end

    if UnitPlayerControlled and not UnitPlayerControlled(unit) then
        return false
    end

    return true
end

ns.TryAutoDetectFromUnit = function(unit, knownPlayerKey)
    if not ns.CanInspectUnit(unit) then return end
    if not unit or not UnitExists(unit) then
        return
    end

    local isPlayer = UnitIsPlayer(unit)

    if isPlayer then
        local playerKey = knownPlayerKey
        local playerRealm
        if not playerKey then
            local playerName
            playerName, playerRealm = ReadPlayerName(unit)
            playerKey = FullName(playerName, playerRealm)
        end
        if not playerKey then
            return
        end

        if type(ns.RememberUnitHostility) == "function" then
            ns.RememberUnitHostility(unit, playerKey)
        end

        -- Known players can skip guild inspection, but an inferred record may
        -- still be corrected by a nearby player's own language announcement.
        if LanguageScoutDB.players[playerKey] then
            ns.RequestLanguageFromUnit(unit, playerKey)
            return
        end

        local guildAssignmentStart = ns.DebugPerfStart and ns.DebugPerfStart()
        local guildName = GetGuildInfo and GetGuildInfo(unit)
        if type(ns.TryApplyStoredGuildLanguageToUnit) == "function" then
            ns.TryApplyStoredGuildLanguageToUnit(unit, playerKey, guildName, playerRealm)
        end
        if ns.DebugPerfStop then
            ns.DebugPerfStop("AutoDetect:GuildAssignment", guildAssignmentStart, unit)
        end

        local nearbyRequestStart = ns.DebugPerfStart and ns.DebugPerfStart()
        if type(ns.RequestLanguageFromUnit) == "function" then
            ns.RequestLanguageFromUnit(unit, playerKey)
        end
        if ns.DebugPerfStop then
            ns.DebugPerfStop("AutoDetect:NearbyRequest", nearbyRequestStart, unit)
        end

        if LanguageScoutDB.autoDetectGuildNames then
            local guildDetectionStart = ns.DebugPerfStart and ns.DebugPerfStart()
            local guildLanguage, guildReason = DetectLanguageFromText(guildName, "AUTO_REASON_GUILD_KEYWORD")
            if guildLanguage then
                TryAutoMarkPlayer(playerKey, guildLanguage, guildReason)
            end
            if ns.DebugPerfStop then
                ns.DebugPerfStop("AutoDetect:GuildName", guildDetectionStart, unit)
            end
        end

        return
    end

    if LanguageScoutDB.autoDetectPetNames and IsPotentialPlayerPetUnit(unit) then
        local petDetectionStart = ns.DebugPerfStart and ns.DebugPerfStart()
        local ownerKey = GetHunterOwnerKeyForPetUnit(unit)
        if ownerKey then
            local petName = UnitName(unit)
            local petLanguage, petReason = DetectLanguageFromPetName(petName)
            if petLanguage then
                TryAutoMarkPlayer(ownerKey, petLanguage, petReason)
            end
        end
        if ns.DebugPerfStop then
            ns.DebugPerfStop("AutoDetect:Pet", petDetectionStart, unit)
        end
    end
end

-- Repeated advertisements and multiple chat windows often analyze identical
-- text. Cache both hits and misses, with strict size and message-length bounds.
local chatTextCache = {}
local chatTextCacheSize = 0
ns.ClearAutoDetectTextCache = function()
    wipe(chatTextCache)
    chatTextCacheSize = 0
end

local function DetectChatLanguage(msg)
    if not msg or msg == "" then return end
    local cached = chatTextCache[msg]
    if cached then
        return cached.lang, cached.reason
    end
    local lang, reason = DetectLanguageFromQuestieAnnouncement(msg)
    if not lang then
        lang, reason = DetectLanguageFromText(msg, "AUTO_REASON_CHAT_KEYWORD")
    end
    if #msg <= 1024 then
        if chatTextCacheSize >= 128 then
            ns.ClearAutoDetectTextCache()
        end
        chatTextCache[msg] = { lang = lang, reason = reason }
        chatTextCacheSize = chatTextCacheSize + 1
    end
    return lang, reason
end

local function DetectLanguage(msg, author, guid, event, channelName)
    if not ns.IsChatDetectionChannelEnabled(event) then
        return
    end

    local key = ResolveChatAuthorPlayerKey(author, guid)
    if not key then
        return
    end

    local record = LanguageScoutDB.players[key]
    local currentLanguage = type(record) == "table" and record.lang or nil
    if currentLanguage then
        -- Require distinguishing evidence from the message to change an
        -- assignment. A name fallback must not undo a later correction.
        local newLanguage, evidence
        if currentLanguage == "RU" and ContainsUkrainianSpecificCharacters(msg) then
            newLanguage, evidence = "UA", "і/ї/є/ґ"
        elseif currentLanguage == "UA" and not ContainsUkrainianSpecificCharacters(msg)
            and ContainsRussianSpecificCharacters(msg)
        then
            newLanguage, evidence = "RU", "ы/э/ъ/ё"
        end
        if newLanguage and IsLanguageAutoDetectEnabled(newLanguage)
            and SetPlayerLanguage(key, newLanguage, true, "automatic")
        then
            local reason = string.format(L("AUTO_REASON_CHAT_KEYWORD"), evidence)
            ShowAutoLanguageMarkedMessage(key, newLanguage, AddChatDetectionDetails(reason, event, channelName, msg), false)
        end
        return
    end

    local detectedLanguage, detectedReason = DetectChatLanguage(msg)
    if not detectedLanguage and ns.UsesSurnames and HasCyrillic(key) then
        if ContainsUkrainianSpecificCharacters(key) then
            detectedLanguage = "UA"
        elseif ContainsRussianSpecificCharacters(key) then
            detectedLanguage = "RU"
        end
        detectedReason = string.format(L("AUTO_REASON_PLAYER_NAME"), key)
    end
    if detectedLanguage then
        TryAutoMarkPlayer(key, detectedLanguage, AddChatDetectionDetails(detectedReason, event, channelName, msg))
        return
    end
end

local function DetectionFilter(_, event, msg, author, ...)
    if ns.IsSecret(msg) then return false, msg, author, ... end
    local debugStart = ns.DebugPerfStart and ns.DebugPerfStart()
    local channelName = select(2, ...)
    if ns.IsSecret(channelName) then channelName = nil end
    local guid = select(10, ...)
    DetectLanguage(msg, author, guid, event, channelName)
    if debugStart and ns.DebugPerfStop then
        ns.DebugPerfStop("AutoDetect:ChatFilter", debugStart, ResolveChatAuthorPlayerKey(author, guid))
    end
    return false, msg, author, ...
end

local COMBATLOG_OBJECT_TYPE_PET = COMBATLOG_OBJECT_TYPE_PET or 0x00001000

local function TryStorePetOwnerFromCombatLog(sourceGUID, sourceName, sourceFlags)
    if not sourceGUID or not sourceName or not sourceFlags then
        return
    end

    if bit.band(sourceFlags, COMBATLOG_OBJECT_TYPE_PET) == 0 then
        return
    end

    local ownerName = sourceName:match("^.+ <(.+)>$")
    if not ownerName or ownerName == "" then
        return
    end

    local ownerKey = NormalizePlayerKey(ownerName)
    if not ownerKey then
        return
    end

    if ns.ParseFullName then
        local parsedOwnerName, parsedOwnerRealm = ns.ParseFullName(ownerKey)
        StorePetOwnerByGUID(sourceGUID, parsedOwnerName, parsedOwnerRealm)
    end
end

ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", DetectionFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_GUILD", DetectionFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_SAY", DetectionFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_YELL", DetectionFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_PARTY", DetectionFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_PARTY_LEADER", DetectionFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_RAID", DetectionFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_RAID_LEADER", DetectionFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_INSTANCE_CHAT", DetectionFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_INSTANCE_CHAT_LEADER", DetectionFilter)

local unitDetectionFrame = CreateFrame("Frame")

local function UpdatePetDetectionEvents()
    -- Forever does not expose the legacy combat-log stream to addons.
    if ns.UsesSurnames or not CombatLogGetCurrentEventInfo then return end
    if LanguageScoutDB and LanguageScoutDB.autoDetectPetNames then
        if not unitDetectionFrame:IsEventRegistered("COMBAT_LOG_EVENT_UNFILTERED") then
            unitDetectionFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        end
        return
    end

    if unitDetectionFrame:IsEventRegistered("COMBAT_LOG_EVENT_UNFILTERED") then
        unitDetectionFrame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    end
end

ns.UpdatePetDetectionEvents = UpdatePetDetectionEvents

unitDetectionFrame:RegisterEvent("PLAYER_LOGIN")
unitDetectionFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
unitDetectionFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
unitDetectionFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
unitDetectionFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
unitDetectionFrame:RegisterEvent("UNIT_PET")
unitDetectionFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
local function HandleUnitDetectionEvent(_, event, arg1)
    if event == "PLAYER_LOGIN" then
        UpdatePetDetectionEvents()
    end

    if event == "PLAYER_LOGIN" or event == "GROUP_ROSTER_UPDATE" or event == "UNIT_PET" then
        if not (LanguageScoutDB and LanguageScoutDB.autoDetectPetNames) then
            return
        end
        ns.RefreshPetOwnerMappings()
    end

    if event == "PLAYER_TARGET_CHANGED" then
        ns.TryAutoDetectFromUnit("target")
        return
    end

    if event == "PLAYER_FOCUS_CHANGED" then
        ns.TryAutoDetectFromUnit("focus")
        return
    end

    if event == "UPDATE_MOUSEOVER_UNIT" then
        ns.TryAutoDetectFromUnit("mouseover")
        return
    end

    if event == "NAME_PLATE_UNIT_ADDED" then
        ns.TryAutoDetectFromUnit(arg1)
        return
    end

    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if not (LanguageScoutDB and LanguageScoutDB.autoDetectPetNames) then
            return
        end
        local _, _, _, sourceGUID, sourceName, sourceFlags = CombatLogGetCurrentEventInfo()
        TryStorePetOwnerFromCombatLog(sourceGUID, sourceName, sourceFlags)
    end
end

unitDetectionFrame:SetScript("OnEvent", function(frame, event, arg1)
    local debugStart = ns.DebugPerfStart and ns.DebugPerfStart()
    HandleUnitDetectionEvent(frame, event, arg1)
    if ns.DebugPerfStop then
        ns.DebugPerfStop("AutoDetect:" .. tostring(event), debugStart, arg1)
    end
end)
