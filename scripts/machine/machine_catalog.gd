class_name MachineCatalog
extends RefCounted
## Übersicht der Maschinenarten und Handwerkzeuge für den Büro-PC. Reine Daten, noch keine fertigen Maschinen.
## Maschine:  title, desc und optional subs (Unterkategorien mit title, desc und optional owned).
## owned = Name der Maschine, die schon in der Werkstatt steht.
## model = 3D-Vorschau aus MillTools.
## tools = Werkzeuge der Maschine (title, desc, model), tool_owner = Maschine, an der sie im Spiel sind.
## lathe_tools = zeigt die Werkzeuge aus LatheTools, die schon an der Maschine im Spiel sind.

const MILL_NAME := "Konventionelle Fräsmaschine 410 mm"

const MILL_TOOLS := [
	{"title": "Schaftfräser", "desc": "4 Schneiden, TiAlN-beschichtet, Ø 6 bis 16 mm. Für Stahl, Edelstahl und Guss.", "model": "end_mills"},
	{"title": "Messerkopf", "desc": "Planfräser Ø 63 mm mit 7 Wendeplatten für große, ebene Flächen.", "model": "face_mill"},
	{"title": "Messerkopf-Aufnahme", "desc": "Steilkegel-Aufnahme mit Mitnehmersteinen und Klemmschraube für den Messerkopf.", "model": "face_mill_arbor"},
	{"title": "Wendeplatten", "desc": "Beschichtete Schneidplatten für den Messerkopf, bei Verschleiß wechselbar.", "model": "inserts"},
	{"title": "Spiralbohrer", "desc": "Bohrer Ø 10 mm für Durchgangs- und Kernlochbohrungen.", "model": "drill"},
	{"title": "Werkzeugaufnahmen", "desc": "Spannzangenfutter mit Spannzangen und Bohrfutter zum Spannen der Werkzeuge.", "model": "holders"},
]

const MACHINES := [
	{
		"title": "Drehmaschinen",
		"desc": "Das Werkstück rotiert, der Drehmeißel trägt Material ab. Für Wellen, Bolzen und Buchsen.",
		"lathe_tools": true,
		"tool_owner": "Weiler E50 HD",
		"subs": [
			{"title": "CNC", "desc": "Programmgesteuert, für Serien und komplexe Konturen."},
			{"title": "Konventionell", "desc": "Von Hand über Handräder und Vorschub bedient. Drehlänge 900 mm, Futter Ø 300 mm.", "owned": "Weiler E50 HD"},
		],
	},
	{
		"title": "Fräsmaschinen",
		"desc": "Das Werkzeug rotiert und trägt Material ab. Für Flächen, Nuten und Taschen.",
		"tools": MILL_TOOLS,
		"tool_owner": MILL_NAME,
		"subs": [
			{"title": "CNC", "desc": "Programmgesteuert, mehrere Achsen fahren gleichzeitig."},
			{"title": "Konventionell", "desc": "Von Hand über Handräder und Stufenhebel bedient. Arbeitsfläche 410 x 210 mm.", "owned": MILL_NAME, "model": "mill_machine"},
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
