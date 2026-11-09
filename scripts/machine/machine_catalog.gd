class_name MachineCatalog
extends RefCounted
## Übersicht der Maschinenarten und Handwerkzeuge für den Büro-PC. Reine Daten, noch keine fertigen Maschinen.
## Maschine:  title, desc und optional subs (Unterkategorien mit title, desc und optional owned).
## owned = Name der Maschine, die schon in der Werkstatt steht.
## model = 3D-Vorschau, siehe ToolPreview.VIEWS.

const MILL_NAME := "Konventionelle Fräsmaschine 410 mm"

const MACHINES := [
	{
		"title": "Drehmaschinen",
		"desc": "Das Werkstück rotiert, der Drehmeißel trägt Material ab. Für Wellen, Bolzen und Buchsen.",
		"subs": [
			{"title": "CNC", "desc": "Programmgesteuert, für Serien und komplexe Konturen. Bedienpult mit Zyklen und NC-Programmen.", "owned": "Weiler E50 HD", "model": "lathe_cnc"},
			{"title": "Konventionell", "desc": "Von Hand über Handräder bedient, Drehzahl und Vorschub mit Drehknöpfen und Stufentasten. Drehlänge 900 mm.", "owned": "Konventionelle Drehmaschine", "model": "lathe_conv"},
		],
	},
	{
		"title": "Fräsmaschinen",
		"desc": "Das Werkzeug rotiert und trägt Material ab. Für Flächen, Nuten und Taschen.",
		"subs": [
			{"title": "CNC", "desc": "Programmgesteuert, mehrere Achsen fahren gleichzeitig."},
			{"title": "Konventionell", "desc": "Von Hand über Handräder und Stufenhebel bedient. Arbeitsfläche 410 x 210 mm.", "owned": MILL_NAME, "model": "mill_machine"},
		],
	},
	{
		"title": "Sägemaschinen",
		"desc": "Trennen Stangen auf Länge. Die Rollbahn trägt die Stange, der Anschlag gibt das Maß vor.",
		"owned": "Bandsäge mit Rollbahn",
		"model": "band_saw",
	},
	{
		"title": "Rundschleifmaschinen",
		"desc": "Schleifen runde Außenflächen auf enge Toleranzen und feine Oberflächen. Scheibe Ø300 mm, Teile vom Drehauftrag.",
		"owned": "Konventionelle Rundschleifmaschine",
		"model": "round_grinder",
	},
	{
		"title": "Flachschleifmaschinen",
		"desc": "Schleifen ebene Flächen maßgenau und mit feiner Oberfläche. Scheibe Ø200 mm, Magnetspannplatte, Teile vom Fräsauftrag.",
		"owned": "Konventionelle Flachschleifmaschine",
		"model": "flat_grinder",
	},
	{
		"title": "Standbohrmaschinen",
		"desc": "Bohren an fest aufgestellter Maschine, mit Kreuztisch und Pinole. Bringt eigene Bohraufträge.",
		"owned": "Konventionelle Standbohrmaschine",
		"model": "drill_press",
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
