class_name MachineCatalog
extends RefCounted
## Übersicht der Maschinenarten und Handwerkzeuge für den Büro-PC. Reine Daten, noch keine fertigen Maschinen.
## Maschine:  title, desc und optional subs (Unterkategorien mit title, desc und optional owned).
## owned = Name der Maschine, die schon in der Werkstatt steht.

const MACHINES := [
	{
		"title": "Drehmaschinen",
		"desc": "Das Werkstück rotiert, der Drehmeißel trägt Material ab. Für Wellen, Bolzen und Buchsen.",
		"subs": [
			{"title": "CNC", "desc": "Programmgesteuert, für Serien und komplexe Konturen."},
			{"title": "Konventionell", "desc": "Von Hand über Handräder und Vorschub bedient.", "owned": "Weiler E50 HD"},
		],
	},
	{
		"title": "Fräsmaschinen",
		"desc": "Das Werkzeug rotiert und trägt Material ab. Für Flächen, Nuten und Taschen.",
		"subs": [
			{"title": "CNC", "desc": "Programmgesteuert, mehrere Achsen fahren gleichzeitig."},
			{"title": "Konventionell", "desc": "Von Hand über Handräder und Vorschub bedient."},
		],
	},
	{
		"title": "Rundschleifmaschinen",
		"desc": "Schleifen runde Außen- und Innenflächen auf enge Toleranzen und feine Oberflächen.",
	},
	{
		"title": "Flachschleifmaschinen",
		"desc": "Schleifen ebene Flächen maßgenau und mit feiner Oberfläche.",
	},
	{
		"title": "Standbohrmaschinen",
		"desc": "Bohren, Senken und Gewindeschneiden an fest aufgestellter Maschine.",
	},
	{
		"title": "Erodiermaschinen",
		"desc": "Tragen leitfähige Werkstoffe durch Funkenentladung ab, auch sehr harte und filigrane Konturen.",
	},
]

const HAND_TOOLS := [
	{"title": "Feilen", "desc": "Flächen und Kanten von Hand nacharbeiten."},
	{"title": "Handentgrater", "desc": "Grate an Kanten und Bohrungen entfernen."},
	{"title": "Schaber", "desc": "Flächen und Lagerstellen fein von Hand abtragen."},
	{"title": "Körner", "desc": "Bohrungsmitten vor dem Bohren markieren."},
	{"title": "Schlosserhammer", "desc": "Für Körnerschläge und einfache Richtarbeiten."},
	{"title": "Gewindebohrer mit Windeisen", "desc": "Innengewinde von Hand schneiden."},
	{"title": "Handreibahlen", "desc": "Bohrungen von Hand auf Passmaß reiben."},
]
