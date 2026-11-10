class_name Dialects
## Sprachpakete: Hochdeutsch ist der Ausgangstext, die Mundarten werden mit Dialect übersetzt.
## Laut- und Schreibregeln nach den Lernunterlagen in "Turner eigene Dateien/Sprachen":
## Schwäbisch (Ferk, Schwäbisch von A bis Z), Sächsisch (Böhnke/Ufer, Duden Sächsisch),
## Bairisch (Witzlinger, Vortrag Bairisch), Schweizerdeutsch (Dörig, Schweizerdeutsch für alle,
## und Wörterliste mittelschulvorbereitung.ch).

## [Code, Anzeigename, Untertitel im Menü]
const LANGS := [
	["de", "Deutsch", "Hochdeutsch"],
	["swg", "Schwäbisch", "Schwätza, wia oim dr Schnabl gwachsa isch"],
	["sxu", "Sächsisch", "Nu glar, das griechn mor hin"],
	["gsw", "Schweizerdeutsch", "Grüezi mitenand"],
	["bar", "Bayerisch", "Griaß God beinand"],
	["pir", "Piratisch", "Ahoi, ihr Landratten"],
]

## Mitlaute für Regeln, die "vor einem Mitlaut oder am Wortende" greifen
const _C := "[bcdfghjklmnpqrstvwxzß]"


static func codes() -> Array:
	return LANGS.map(func(l): return l[0])


static func display_name(code: String) -> String:
	for l in LANGS:
		if l[0] == code:
			return l[1]
	return code


## Sprachpaket für einen Code bauen, null für Hochdeutsch.
static func make(code: String) -> Dialect:
	var d: Dictionary
	match code:
		"swg": d = _schwaebisch()
		"sxu": d = _saechsisch()
		"gsw": d = _schweizerdeutsch()
		"bar": d = _bayerisch()
		"pir": d = _piratisch()
		_: return null
	return Dialect.new(code, d)


# --------------------------------------------------------------------------- Schwäbisch
## sp/st am Wortanfang bleiben, im Wortinneren und am Ende scht/schp; p/t am Anfang werden b/d;
## ge- wird g-; i/u färben zu e/o (Hond, gsond); ie wird ia; Grundform auf -a, End-e fällt;
## Artikel dr, d', 's, 'm, de.
static func _schwaebisch() -> Dictionary:
	return {
		"phrases": {
			"Fortsetzen": "Weitermacha",
			"Neues Spiel": "A nuis Spiel",
			"Spiel laden": "Spiel lada",
			"Einstellungen": "Eistellonga",
			"Beenden": "Feierobend macha",
			"Sprache": "Sprooch",
			"Zurück": "Zrugg",
			"Speichern": "Speichra",
		},
		"words": {
			# Artikel und Fürwörter
			"anders": "andersch", "andere": "andre", "anderen": "andre", "angst": "Angscht",
			"anker": "Anker", "annehmen": "anemma", "und": "ond", "der": "dr", "die": "d'", "das": "'s", "dem": "'m", "den": "de", "ein": "a", "eine": "a",
			"einen": "an", "einem": "ama", "einer": "oinr", "kein": "koi", "keine": "koine",
			"keinen": "koin", "keiner": "koinr", "ich": "i", "mich": "mi", "dich": "di", "sich": "se",
			"wir": "mir", "uns": "ons", "euch": "eich", "sie": "se", "man": "mr", "mein": "mei",
			"dein": "dei", "sein": "sei", "dieser": "der", "diese": "dia", "dieses": "des",
			# Hilfs- und häufige Zeitwörter
			"ist": "isch", "bist": "bisch", "hast": "hosch", "hat": "hot", "haben": "hend",
			"habe": "han", "hatte": "hot ghet", "sind": "send", "war": "isch gwea", "werden": "weara",
			"wird": "wird", "wurde": "isch woara", "gehen": "gauh", "geht": "gauht", "gehe": "gang",
			"kommen": "komma", "kommt": "kommt", "machen": "macha", "macht": "macht",
			"gemacht": "gmacht", "arbeiten": "schaffa", "arbeitet": "schafft", "kaufen": "kaufa",
			"gekauft": "kauft", "nehmen": "nemma", "nimm": "nemm", "nimmt": "nemmt", "geben": "gea",
			"gibt": "geit", "lassen": "lassa", "stehen": "stauh", "steht": "stauht", "liegt": "leit",
			"liegen": "leiga", "sagen": "saga", "sagt": "sait", "reden": "schwätza", "schauen": "luaga",
			"ansehen": "aluaga", "hören": "losa", "gehören": "gheara", "gehört": "gheart",
			"kann": "ka", "können": "kenna", "muss": "muaß", "müssen": "miaßa", "will": "will",
			"tun": "dua", "tut": "duat", "holen": "hola", "tragen": "traga", "legen": "lega",
			"sitzen": "hocka", "fallen": "nagheia",
			# Kleine Wörter
			"nicht": "net", "nichts": "nix", "auf": "uff", "auch": "au", "noch": "no",
			"schon": "scho", "nur": "bloß", "etwas": "ebbes", "jetzt": "jetzt", "heute": "heit",
			"gut": "guat", "gute": "guate", "guten": "guate", "sehr": "arg", "klein": "kloi",
			"kleine": "kloine", "kleinen": "kloine", "zwei": "zwoi", "nein": "noi", "ja": "jo",
			"hier": "do", "da": "do", "zurück": "zrugg", "wieder": "widder", "immer": "allat",
			"in": "en", "im": "em", "mal": "mol", "einmal": "oimol", "gerade": "grad",
			"bitte": "bitte", "danke": "merci", "hallo": "griaß di", "wie": "wia", "zusammen": "zsema",
			"durcheinander": "duranand", "so": "so", "fertig": "fertig", "mehr": "mea",
			"zum": "zom", "zu": "z'", "vorne": "vorna", "vorn": "vorna", "hinten": "hinda",
			"oben": "oba", "unten": "onda", "links": "lenks", "heiß": "hoiß", "allein": "alloi",
			"bisschen": "bissle", "kaputt": "hee", "neu": "nui", "neue": "nuie", "neues": "nuis",
			"neuen": "nuie", "früher": "friaher", "lieber": "liaber", "müde": "miad", "weg": "fort",
			"teuer": "deier", "kosten": "koschta", "kostet": "koschtet", "wenig": "wenig",
			# Hauptwörter
			"werkstatt": "Werkstatt", "pause": "Veschper", "feierabend": "Feierobend",
			"junge": "Bua", "mädchen": "Mädle", "kind": "Kind", "haus": "Hous", "tag": "Dag",
			"teil": "Doil", "teile": "Doil", "hände": "Händ", "händen": "Händ", "eimer": "Kübel",
			"kiste": "Kischt", "kisten": "Kischta", "auftrag": "Uffdrag", "aufträge": "Uffdräg",
			"kartoffel": "Grombir", "kartoffeln": "Grombira", "zigarette": "Kippa",
			"geld": "Geld", "schraube": "Schraufa", "schrauben": "Schraufa", "ecke": "Egg",
			"sache": "Sach", "sachen": "Sach", "zeug": "Zuig", "schuh": "Schuah", "schuhe": "Schuah",
			"mutter": "Muatter", "buch": "Buach", "tuch": "Duach", "text": "Tekscht",
			"butter": "Butter", "koffer": "Kuufr", "teller": "Deller", "garten": "Gata",
		},
		"rules": [
			["ungen$", "onga"], ["ung$", "ong"], ["lein$", "le"],
			["^ein(.{3,})", "ei$1"], ["^auf(.{3,})", "uff$1"], ["^ge(?=[fhlmnrswz].{3,})", "g"],
			# ge- nach Vorsilben (an-, ab-, ei-, uff- ...) wird g-: angenommen -> agnomma, eingespannt -> eigspannt
			["^(an|ab|uff|aus|ei|vor|zu|mit|weg|nach|zurück|her|hin|um|durch|hoch|frei|fehl|fest|los|weiter)ge(?!hen)(?=[fhlmnrswzäöü])", "$1g"],
			# an- wird a- (nasal): anzünden -> azünda, angenommen -> agnomma
			["^an(?!d|ker)(?=[bcdfghjklmnpqrstvwxz].{3,})", "a"],
			["zeug$", "zuig"], ["und", "ond"], ["ie", "ia"],
			["(?<=[aeouäöürn])st", "scht"], ["(?<=[aeouäöür])sp", "schp"], ["xt", "kscht"],
			["^p(?![fhs])", "b"], ["^t(?![hsz])", "d"], ["en$", "a"], ["(?<=.{4})e$", ""],
		],
	}


# --------------------------------------------------------------------------- Sächsisch
## st/sp werden schd/schb (auch im Wort), k wird g, ck gg, t d, p b, z ds; pf am Anfang f,
## sonst bb; b zwischen Selbstlauten w; -ben wird -m; ei ee, au oo, eu ei, ü i, ö e;
## das e der Endungen fällt; Artikel ä / ne / dr / de / s.
static func _saechsisch() -> Dictionary:
	return {
		"phrases": {
			"Fortsetzen": "Weidermachn",
			"Neues Spiel": "Ä neies Schbiel",
			"Spiel laden": "Schbiel ladn",
			"Einstellungen": "Eenschdellungn",
			"Beenden": "Feieromd machn",
			"Sprache": "Schbrache",
			"Zurück": "Zurigge",
			"Speichern": "Schbeichorn",
		},
		"words": {
			"und": "un", "der": "dr", "die": "de", "das": "s", "den": "de", "dem": "dm", "für": "fier", "ein": "ä", "eine": "ne", "einen": "ään",
			"einem": "äm", "einer": "änner", "kein": "gee", "keine": "geene", "keinen": "geen",
			"ich": "isch", "mir": "mor", "wir": "mor", "dir": "dor", "nicht": "nich",
			"nichts": "nischd", "ist": "is", "sind": "sin", "haben": "ham", "habe": "hawwe",
			"hat": "had", "hast": "hasde", "wird": "wärd", "gibt": "gibd", "mal": "ämah",
			"ja": "nu", "nein": "nee", "auch": "ooch", "auf": "off", "aber": "awwor",
			"oder": "oddor", "etwas": "ewwas", "jetzt": "itze", "gleich": "glei", "eben": "ähmde",
			"allein": "alleene", "alle": "allehaufe", "gut": "guud", "gute": "guude",
			"klein": "gleen", "kleine": "gleene", "zwei": "zwee", "beide": "beede",
			"kaufen": "goofn", "gekauft": "gegooft", "laufen": "loofn", "arbeit": "Arbeed",
			"arbeiten": "arbeedn", "arbeitet": "arbeed", "teil": "Deel", "teile": "Deele",
			"heute": "heide", "leute": "Leide", "tag": "Daach", "mittag": "Middaach",
			"wieder": "widdor", "immer": "immor", "werkstatt": "Wergschdadd", "spiel": "Schbiel",
			"stehen": "schdehn", "steht": "schdehd", "platz": "Bladds", "zurück": "zurigge",
			"geld": "Pinke", "kosten": "gosdn", "kostet": "gosded", "neu": "nei", "neues": "neies",
			"neue": "neie", "klar": "glar", "kann": "gann", "kommt": "gommd", "können": "gönn",
			"schön": "schee", "sehr": "orrndlisch", "fertig": "fertsch", "richtig": "rischdsch",
			"maschine": "Maschiene", "machen": "machn", "hallo": "Gun Daach", "bitte": "bidde",
			"danke": "dange", "hören": "heern", "höre": "heere", "einschalten": "anmachn",
			"anschalten": "anmachn", "anzünden": "anfüngn", "anfassen": "andadschn",
			"schleppen": "asdn", "rennen": "peesn", "kartoffel": "Abern", "kartoffeln": "Abern",
			"kopf": "Kobb", "topf": "Dobb", "apfel": "Abbl", "pferd": "Ferd", "brot": "Bemme",
			"schrott": "Plunder", "pfusch": "Pfusch", "polizist": "Polizeier", "sauber": "proper",
			"pause": "Bause", "kiste": "Gisde", "kisten": "Gisdn", "nehmen": "nehm",
			"verschwinden": "abhaun", "mädchen": "Mäddl", "junge": "Junge",
		},
		"rules": [
			["ck", "gg"], ["tz", "ds"], ["ben$", "m"], ["^pf", "f"], ["pf", "bb"],
			["ich", "isch"], ["ig$", "isch"], ["st", "schd"], ["sp", "schb"],
			["ei", "ee"], ["eu", "ei"], ["äu", "ei"], ["au", "oo"], ["ü", "i"], ["ö", "e"],
			["(?<=[aeiouäöülr])b(?=[aeiouäöü])", "w"],
			["p", "b"], ["t", "d"], ["k", "g"], ["z", "ds"],
			["er$", "or"], ["nen$", "n"], ["(?<!n)en$", "n"], ["(?<!e)el$", "l"],
		],
	}


# --------------------------------------------------------------------------- Schweizerdeutsch
## K- wird Ch-, ei teils ii (Ziit), au teils uu (Huus), eu üü, ie iä, e vor r/l oft ä (Wärt),
## -en wird -e, -ung -ig, -lein -li, ge- wird g-, st im Wort scht, kein ß.
static func _schweizerdeutsch() -> Dictionary:
	return {
		"phrases": {
			"Fortsetzen": "Wiitermache",
			"Neues Spiel": "Es neus Spiil",
			"Spiel laden": "Spiil lade",
			"Einstellungen": "Iistellige",
			"Beenden": "Fiirabig",
			"Sprache": "Sprooch",
			"Zurück": "Zrugg",
			"Speichern": "Spiichere",
		},
		"words": {
			# Artikel und Fürwörter
			"der": "dr", "die": "d", "das": "ds", "den": "de", "dem": "em", "ein": "en", "eine": "e",
			"einen": "en", "einem": "emne", "einer": "ere", "kein": "kei", "keine": "kei",
			"keinen": "kei", "wir": "mir", "uns": "eus", "euch": "eu", "mein": "mii", "dein": "dii",
			"sein": "sii", "etwas": "öppis", "nichts": "nüüt", "nicht": "nöd", "jemand": "öpper",
			# Zeitwörter
			"ist": "isch", "bist": "bisch", "hat": "hät", "haben": "händ", "habe": "ha", "hast": "häsch",
			"sind": "sind", "gehen": "gah", "geht": "gaht", "gehe": "gang", "kommen": "cho",
			"kommt": "chunt", "komm": "chum", "arbeiten": "schaffe", "arbeitet": "schafft",
			"kaufen": "chaufe", "gekauft": "kauft", "einkaufen": "poschte", "kosten": "choschte",
			"kostet": "choschtet", "können": "chöne", "kann": "cha", "kannst": "chasch",
			"muss": "mues", "müssen": "müend", "nehmen": "neh", "nimm": "nimm", "geben": "gee",
			"gibt": "git", "abgeben": "abgää", "lassen": "laa", "lässt": "laat", "stehen": "staa", "steht": "staat",
			"liegt": "liit", "liegen": "ligge", "sehen": "gseh", "sieht": "gseet", "schauen": "luege",
			"ansehen": "aaluege", "anschauen": "aaluege", "zuhören": "lose", "heben": "lüpfe",
			"halten": "hebe", "hält": "hebt", "fallen": "gheie", "herunterfallen": "abegheie",
			"anrufen": "aalüüte", "anziehen": "aalegge", "anzünden": "aazünde", "berühren": "aalange",
			"wegräumen": "versorge", "aufräumen": "uufruume", "sitzen": "hocke", "tun": "tue",
			"tut": "tuet", "sagen": "säge", "sagt": "seit", "laden": "lade", "speichern": "spiichere",
			"schleifen": "schliife",
			# Kleine Wörter
			"auf": "uf", "aus": "us", "auch": "au", "noch": "no", "schon": "scho", "heute": "hüt",
			"gut": "guet", "gute": "gueti", "guten": "guete", "viel": "vill", "klein": "chlii",
			"kleine": "chliini", "kleinen": "chliine", "wenig": "chli", "groß": "gross",
			"zwei": "zwei", "drei": "drüü", "nein": "nei", "ja": "jo", "hier": "da", "dort": "det",
			"zurück": "zrugg", "weg": "ewägg", "fort": "ewägg", "runter": "abe", "hinunter": "abe",
			"herunter": "abe", "hinauf": "ufe", "herauf": "ufe", "hinaus": "use", "heraus": "use",
			"hinein": "ine", "herein": "ine", "immer": "immer", "häufig": "allpott", "gerade": "grad",
			"bitte": "bitte", "danke": "merci", "hallo": "grüezi", "tschüss": "adieu",
			"sehr": "huere", "schnell": "tifig", "praktisch": "gäbig", "weit": "wiit",
			"weiter": "wiiter", "zeit": "Ziit", "frei": "frei", "neu": "neu", "neues": "neus",
			"neue": "neui", "ende": "Änd", "leer": "läär", "noch nicht": "nonig",
			"nicht mehr": "nümme", "falsch": "lätz", "von": "vo", "unter": "under", "dann": "denn",
			"bei": "bi", "mit": "mit", "für": "für", "allein": "elei", "zusammen": "zäme",
			# Hauptwörter
			"arbeit": "Büez", "arbeiter": "Büezer", "fabrik": "Buude", "werkstatt": "Wärchstatt",
			"geld": "Stutz", "haus": "Huus", "kiste": "Chischte", "kisten": "Chischte",
			"eimer": "Chessel", "spiel": "Spiil", "pause": "Znüni", "mittagessen": "Zmittag",
			"abendessen": "Znacht", "feierabend": "Fiirabig", "zigarette": "Zigi", "kaffee": "Kafi",
			"fahrrad": "Velo", "motorrad": "Töff", "handy": "Natel", "tüte": "Sack",
			"tasche": "Täsche", "kurve": "Rank", "durcheinander": "Puff", "unsinn": "Seich",
			"kopf": "Grind", "kind": "Goof", "küche": "Chuchi", "kartoffel": "Härdöpfel",
			"kartoffeln": "Härdöpfel", "butter": "Anke", "hausmeister": "Abwart",
			"getränkekasten": "Harass", "kneipe": "Beiz", "hände": "Händ", "händen": "Händ",
			"fehler": "Fähler", "schraube": "Schruube",
		},
		"rules": [
			["ungen$", "ige"], ["ung$", "ig"], ["lein$", "li"],
			["^ein(.{3,})", "ii$1"], ["^auf(.{3,})", "uf$1"], ["^aus(.{3,})", "us$1"],
			["^ge(?=[fhlmnrswz].{3,})", "g"],
			["werk", "wärch"], ["zeug", "züüg"], ["kühl", "küel"], ["spiel", "spiil"],
			["schleif", "schliif"], ["scheib", "schiib"], ["zeit", "ziit"], ["preis", "priis"],
			["schreib", "schriib"], ["bleib", "bliib"], ["eisen", "iise"], ["haus", "huus"],
			["schraub", "schruub"], ["brauch", "bruuch"], ["^bau", "buu"], ["führ", "füer"],
			["eu", "üü"], ["äu", "üü"], ["ie", "iä"],
			["(?<=[bcdfghjklmnpqrstwx])e(?=r[bcdfghjklmnpqstvwxz])", "ä"],
			["(?<=[bcdfghjklmnpqrstvwxz])e(?=ll$|ll[bcdfghjkmnpqrstvwxz]|l[dt])", "ä"],
			["^k", "ch"], ["ck", "gg"], ["lich$", "li"], ["(?<=[aeouäöür])st", "scht"],
			["en$", "e"],
		],
		"post": [["ß", "ss"]],
	}


# --------------------------------------------------------------------------- Bayerisch
## l nach Selbstlaut wird i (Goid, Gäid, Spui, Huif), -el wird -l/-e, er am Ende a,
## eu/äu ei, ie ia, ei teils oa (hoaß, Stoa), a dunkel o (Dog, mocha), ü i, ö e,
## p/t am Anfang b/d, ck gg, tt dd, b zwischen Selbstlauten w, -en je nach Stamm -a/-n/-m,
## End-e wird -n oder fällt, ge- wird g-, ver- va-; Artikel da, d', 's, a, an, am.
static func _bayerisch() -> Dictionary:
	var c := _C
	return {
		"phrases": {
			"Fortsetzen": "Weidamocha",
			"Neues Spiel": "A neis Spui",
			"Spiel laden": "Spui lon",
			"Einstellungen": "Eistellunga",
			"Beenden": "Feierabnd mocha",
			"Sprache": "Sproch",
			"Zurück": "Zruck",
			"Speichern": "Speichan",
		},
		"words": {
			# Artikel und Fürwörter
			"der": "da", "die": "d'", "das": "'s", "dem": "am", "den": "an", "ein": "a", "eine": "a",
			"einen": "an", "einem": "am", "einer": "ana", "kein": "koa", "keine": "koane",
			"keinen": "koan", "ich": "i", "mich": "mi", "dich": "di", "sich": "si", "wir": "mia",
			"mir": "mia", "dir": "dia", "euch": "eich", "sie": "se", "etwas": "ebbs", "was": "wos",
			"nichts": "nix", "nicht": "ned", "niemand": "neamd", "eins": "oans",
			# Zeitwörter
			"ist": "is", "bist": "bist", "sind": "san", "war": "is gwen", "gewesen": "gwen",
			"hat": "hod", "haben": "ham", "habe": "hob", "hast": "host", "hatte": "hod ghobt",
			"wird": "wiad", "werden": "wean", "tun": "doa", "tut": "duad", "getan": "do",
			"sagen": "song", "sagt": "sogt", "gesagt": "gsogt", "gehen": "geh", "gegangen": "ganga",
			"kommen": "kemma", "kommt": "kimmt", "gekommen": "kumma", "machen": "mocha",
			"macht": "mocht", "gemacht": "gmocht", "gebracht": "brocht", "arbeiten": "oarwatn",
			"kaufen": "kaffa", "gekauft": "kafft", "verkaufen": "vakaafa", "laufen": "laffa",
			"können": "kinna", "kann": "ko", "muss": "muaß", "müssen": "miassn", "darf": "derf",
			"möchte": "mecht", "würde": "daad", "nehmen": "nehma", "geben": "gebn", "heben": "hebn", "abgeben": "abgebn", "gibt": "gibt",
			"lassen": "lassn", "stehen": "steh", "steht": "stehd", "sitzen": "hocka",
			"schauen": "schaun", "holen": "hoin", "zahlen": "zoin", "laden": "lon",
			# Kleine Wörter
			"auch": "aa", "noch": "no", "schon": "scho", "nur": "bloß", "jetzt": "iatz",
			"heute": "heid", "immer": "oiwei", "gut": "guad", "gute": "guade", "guten": "guadn",
			"sehr": "saggrisch", "viel": "vui", "viele": "vui", "klein": "gloa", "kleine": "gloane",
			"kleinen": "gloana", "zwei": "zwoa", "heiß": "hoaß", "weiß": "woaß", "breit": "broad",
			"allein": "alloa", "alles": "ois", "alle": "olle", "also": "oiso", "hier": "do",
			"da": "do", "dort": "dot", "oben": "om", "unten": "unt", "hinten": "hint",
			"zurück": "zruck", "wieder": "wieda", "mal": "amoi", "einmal": "amoi", "gerade": "grad",
			"egal": "wuaschd", "ruhig": "staad", "langsam": "staad", "kaputt": "hi", "zu": "zua",
			"mit": "mid", "von": "vo", "für": "fia", "oder": "oda", "aber": "aba", "über": "iba",
			"unter": "unta", "nie": "nia", "nicht mehr": "nimma", "schön": "schee",
			"hallo": "servus", "tschüss": "pfiad di", "danke": "merci", "bitte": "bittschee",
			"achtung": "Obacht", "eben": "hoit", "halt": "hoit", "neu": "nei", "neues": "neis",
			"neue": "neie", "leer": "laar", "voll": "voi",
			# Hauptwörter
			"tag": "Dog", "mann": "Mo", "vater": "Vadda", "mutter": "Muadda", "bruder": "Bruada",
			"junge": "Bua", "mädchen": "Deandl", "werkstatt": "Werkstod", "stadt": "Stod",
			"platz": "Blotz", "wagen": "Wong", "teller": "Della", "stein": "Stoa", "teil": "Toal",
			"teile": "Toal", "heimat": "Hoamat", "reise": "Roas", "teig": "Doag", "fuß": "Fuaß",
			"schuh": "Schuah", "pause": "Brotzeit", "feierabend": "Feierabnd", "spaß": "Gaudi",
			"glück": "Dusl", "schrott": "Glump", "gerümpel": "Graffe", "kartoffel": "Erdäpfe",
			"kartoffeln": "Erdäpfe", "brötchen": "Semme", "fahrrad": "Radl", "spiel": "Spui",
			"maschine": "Maschin", "maschinen": "Maschina", "hände": "Händ", "händen": "Händ",
			"zigarette": "Zigarettn", "kiste": "Kistn", "kisten": "Kistn", "eimer": "Kübe",
		},
		"rules": [
			["ungen$", "unga"], ["^ein(.{3,})", "ei$1"], ["^ver(?=.{3,})", "va"],
			["^ge(?=[fhlmnrswz].{3,})", "g"], ["^ch", "k"], ["ig$", "ik"], ["ben$", "m"],
			["eu", "ei"], ["äu", "ei"], ["iel", "ui"],
			["(?<=[tszpß])e$", "n"], ["(?<=[^aeiouäöü])e$", ""],
			["(?<=[fbw])el$", "e"], ["el$", "l"],
			["(?<![aeo])(?:ie|ih|i|üh|ü)ll?(?=%s|$)" % c, "ui"],
			["(?<![ae])(?:uh|u)ll?(?=%s|$)" % c, "ui"],
			["(?:ah|a)ll?(?=%s|$)" % c, "oi"], ["(?:oh|o)ll?(?=%s|$)" % c, "oi"],
			["(?:ell|ehl|äll|ähl)(?=%s|$)" % c, "äi"], ["el(?=[dt])", "äi"],
			["ie(?!g)", "ia"], ["o(?=mm|nn|nst)", "u"],
			["ck", "gg"], ["tt", "dd"], ["^t(?![hsz])", "d"], ["^p(?![fhs])", "b"],
			["^k(?=[rl])", "g"], ["(?<=[aeiouäöü])b(?=[aeiou])", "w"],
			["ü", "i"], ["ö", "e"], ["er$", "a"],
			["(?<=[fkmn]|ch)en$", "a"], ["en$", "n"],
		],
	}


# --------------------------------------------------------------------------- Piratisch
static func _piratisch() -> Dictionary:
	return {
		"phrases": {
			"Fortsetzen": "Weitersegeln",
			"Neues Spiel": "Neue Kaperfahrt",
			"Spiel laden": "Logbuch aufschlagen",
			"Einstellungen": "Takelage",
			"Beenden": "Von Bord gehen",
			"Sprache": "Mundart",
			"Zurück": "Zurück an Deck",
			"Speichern": "Ins Logbuch schreiben",
		},
		"words": {
			"ja": "aye", "nein": "nee", "hallo": "Ahoi", "freund": "Maat", "freunde": "Maate",
			"geld": "Gold", "werkstattkasse": "Schatztruhe", "kasse": "Schatztruhe",
			"fahren": "segeln", "fährt": "segelt", "gehen": "schippern", "geht": "schippert",
			"bewegung": "Manöver", "kamera": "Fernrohr", "zeichnung": "Schatzkarte",
			"werkstückzeichnung": "Schatzkarte", "rohteil": "Rohling", "sprache": "Mundart",
			"einstellungen": "Takelage", "kaufen": "erbeuten", "gekauft": "erbeutet",
			"verkaufen": "verscherbeln", "preis": "Lösegeld", "lager": "Laderaum",
			"lagerhalle": "Laderaum", "regal": "Stauraum", "lagerregal": "Stauregal",
			"gabelstapler": "Lastenesel", "hallenkran": "Ladebaum", "kran": "Ladebaum",
			"haken": "Enterhaken", "kette": "Ankerkette", "boden": "Planken", "wand": "Bordwand",
			"tür": "Luke", "schutztür": "Schutzluke", "tor": "Luke", "rolltor": "Ladeluke",
			"hoftor": "Hafentor", "mitarbeiter": "Matrose", "kunde": "Kaufmann",
			"kunden": "Kaufleute", "werkstatt": "Werft", "halle": "Werft", "hof": "Hafen",
			"spieler": "Pirat", "chef": "Käpt'n", "meister": "Käpt'n",
			"meisterbüro": "Kapitänskajüte", "büro": "Kajüte", "computer": "Rechenknecht",
			"auftrag": "Kaperbrief", "aufträge": "Kaperbriefe", "aufträgen": "Kaperbriefen",
			"fräsauftrag": "Fräs-Kaperbrief", "bohrauftrag": "Bohr-Kaperbrief",
			"pause": "Landgang", "zigarette": "Pfeife", "rauchen": "paffen", "kaffee": "Grog",
			"bier": "Rum", "kühlschmierstoff": "Bilgenwasser", "schrott": "Strandgut",
			"abfall": "Strandgut", "müll": "Strandgut", "container": "Fass", "behälter": "Fass",
			"spänebehälter": "Spänefass", "eimer": "Pütz", "kiste": "Truhe", "kisten": "Truhen",
			"spänekiste": "Spänetruhe", "gut": "famos", "schlecht": "lausig", "sehr": "verflucht",
			"achtung": "Klar Schiff", "warnung": "Sturmwarnung", "not": "Seenot",
			"nicht": "nich", "ist": "is", "das": "dat", "was": "wat", "leute": "Mannschaft",
			"team": "Mannschaft", "fertig": "klar", "bereit": "klar zum Entern",
			"links": "backbord", "rechts": "steuerbord", "fenster": "Bullauge",
			"feierabend": "Schicht im Schacht", "beenden": "abheuern", "fortsetzen": "weitersegeln",
			"speichern": "verstauen", "spiel": "Kaperfahrt", "fernbedienung": "Kommandopfeife",
			"material": "Beute", "lieferung": "Fracht", "bestellung": "Frachtauftrag",
			"tag": "Tag", "euro": "Dublonen", "skilltree": "Seemannskunst",
		},
		"exclaim": " Arr!",
	}
